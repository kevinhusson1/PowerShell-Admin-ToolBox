#Requires -Version 7.0

<#
.SYNOPSIS
    Annuaire Utilisateurs (Architectured V3.0)
    Script modulaire de recherche et d'export via Microsoft Graph.
#>

param(
    [string]$LauncherPID,
    [string]$AuthContext,
    [string]$AuthUPN,     # Méthode Secure
    [string]$TenantId,
    [string]$ClientId
)

# =====================================================================
# 1. PRÉ-CHARGEMENT (BOILERPLATE)
# =====================================================================
try { Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase } catch { exit 1 }

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = (Get-Item $scriptRoot).Parent.Parent.Parent.FullName
$Global:ProjectRoot = $projectRoot
$env:PSModulePath = "$($projectRoot)\Modules;$($projectRoot)\Vendor;$($env:PSModulePath)"

# Fonction Feedback Launcher
function Send-Progress { param([int]$Percent, [string]$Msg) if ($LauncherPID) { Set-AppScriptProgress -OwnerPID $PIDs -ProgressPercentage $Percent -StatusMessage $Msg } }

Send-Progress 10 "Initialisation..."

# =====================================================================
# 2. CHARGEMENT MODULES & CONFIG
# =====================================================================
try {
    Import-Module "PSSQLite", "Core", "UI", "Localization", "Logging", "Database", "Azure", "ThreadJob" -Force
    
    # Chargement dynamique des fonctions locales
    Get-ChildItem -Path (Join-Path $scriptRoot "Functions") -Filter "*.ps1" | ForEach-Object { . $_.FullName }

    Initialize-AppDatabase -ProjectRoot $projectRoot
    $manifest = Get-Content (Join-Path $scriptRoot "manifest.json") -Raw | ConvertFrom-Json
    
    # Verrouillage
    if (-not (Test-AppScriptLock -Script $manifest)) {
        [System.Windows.MessageBox]::Show((Get-AppText 'messages.execution_limit_reached'), "Stop", "OK", "Error"); exit 1
    }
    Add-AppScriptLock -Script $manifest -OwnerPID $PIDs

    # Config & Langue
    $Global:AppConfig = Get-AppConfiguration
    $VerbosePreference = if ($Global:AppConfig.enableVerboseLogging) { "Continue" } else { "SilentlyContinue" }

    Initialize-AppLocalization -ProjectRoot $projectRoot -Language $Global:AppConfig.defaultLanguage
    $localLang = "$scriptRoot\Localization\$($Global:AppConfig.defaultLanguage).json"
    if (Test-Path $localLang) { Add-AppLocalizationSource -FilePath $localLang }


}
catch {
    [System.Windows.MessageBox]::Show("Erreur critique : $($_.Exception.Message)", "Fatal", "OK", "Error"); exit 1
}

# =====================================================================
# 3. AUTHENTIFICATION (ZERO-TRUST)
# =====================================================================
Send-Progress 30 "Authentification..."

if (-not $TenantId) { $TenantId = $Global:AppConfig.azure.tenantId }
if (-not $ClientId) { $ClientId = $Global:AppConfig.azure.authentication.userAuth.appId }

# Tentative de connexion silencieuse
$userIdentity = @{ Connected = $false }
if (-not [string]::IsNullOrWhiteSpace($AuthUPN)) {
    try {
        $userIdentity = Connect-AppChildSession -AuthUPN $AuthUPN -TenantId $TenantId -ClientId $ClientId
    }
    catch { Write-Warning "Auth Error: $_" }
}

# =====================================================================
# 4. CHARGEMENT UI & DONNÉES
# =====================================================================
Send-Progress 40 "Préparation de l'interface..."

try {
    $window = Import-AppXamlTemplate -XamlPath (Join-Path $scriptRoot "ListUserGraph.xaml")
    Initialize-AppUIComponents -Window $window -ProjectRoot $projectRoot -Components 'Buttons', 'Inputs', 'Layouts', 'Display', 'ProfileButton'

    # --- LOGIQUE DE PRÉSENTATION (En-tête dynamique) ---
    # On peuple l'en-tête automatiquement avec les infos du Manifeste
    $rootForIcons = if ($Global:AppRoot) { $Global:AppRoot } else { $projectRoot }
    
    # 1. Icône
    $imgBrush = $window.FindName("HeaderIconBrush")
    if ($imgBrush -and $manifest.icon) {
        $iconPath = Join-Path $rootForIcons "Templates\Resources\Icons\PNG\$($manifest.icon.value)"
        if (Test-Path $iconPath) {
            try {
                $imgBrush.ImageSource = [System.Windows.Media.Imaging.BitmapImage]::new([Uri]$iconPath)
            }
            catch { Write-Warning "Impossible de charger l'icône : $_" }
        }
    }

    # 2. Titres
    # Optionnel : Forcer le titre/sous-titre si on ne veut pas utiliser le Binding XAML ##loc:##
    # Ici on utilise le manifest mais on applique la traduction via Get-AppText
    $txtTitle = $window.FindName("HeaderTitleText")
    if ($txtTitle -and $manifest.name) { $txtTitle.Text = Get-AppText $manifest.name }

    $txtDesc = $window.FindName("HeaderSubtitleText")
    if ($txtDesc -and $manifest.description) { $txtDesc.Text = Get-AppText $manifest.description }

    # --- LOGIQUE DE CHARGEMENT DES DONNÉES (ASYNC) ---
    $LoadAction = {
        param($UserAuth)
        if ($UserAuth.Connected) {
            # On passe la société définie dans la config globale comme filtre par défaut
            $companyFilter = if ($Global:AppConfig.companyName) { $Global:AppConfig.companyName } else { $null }
            $certThumb = $Global:AppConfig.azure.certThumbprint
            
            # Paramètres pour le Job
            $jobParams = @{
                TenantId      = $TenantId
                ClientId      = $ClientId
                Thumb         = $certThumb
                CompanyFilter = $companyFilter
                ScriptRoot    = $scriptRoot
                ProjectRoot   = $projectRoot
            }

            # Démarrage du Job
            $loadingJob = Start-ThreadJob -ArgumentList $jobParams -ScriptBlock {
                param($ArgsMap)

                $ErrorActionPreference = 'Stop'
                
                # Re-chargement minimal des modules nécessaires dans le Runspace du Job
                $projectRoot = $ArgsMap.ProjectRoot
                $env:PSModulePath = "$($projectRoot)\Modules;$($projectRoot)\Vendor;$($env:PSModulePath)"
                
                Import-Module "Azure", "Core" -Force

                # -- Authentification dans le Job --
                # Note: On doit ré-authentifier le contexte du Job (Connect-MgGraph est session-based)
                # Cas 1: Certificat (App-Only) favorisé pour la stabilité
                if ([string]::IsNullOrWhiteSpace($ArgsMap.Thumb) -eq $false) {
                    Connect-AppAzureCert -TenantId $ArgsMap.TenantId -ClientId $ArgsMap.ClientId -Thumbprint $ArgsMap.Thumb
                }
                else {
                    # TODO: Cas User Delegated dans un ThreadJob est complexe (Token Cache).
                    # Pour l'instant on assume que le contexte process suffit ou on devra passer le Token.
                    # Fallback simple: on tente de récupérer le contexte du process parent via Azure module si implémenté, 
                    # sinon on risque de devoir passer l'AccessToken explicitement. 
                    # Pour ListUserGraph v3, assumons que le certificat est la cible principale.
                }

                # Appel de la fonction de récupération
                return Get-AppAzureDirectoryUsers -CompanyNameFilter $ArgsMap.CompanyFilter
            }

            # Boucle d'attente non-bloquante (UI Pump)
            Send-Progress 60 "Récupération de l'annuaire (Async)..."
            
            while ($loadingJob.State -eq 'Running') {
                [System.Windows.Forms.Application]::DoEvents()
                Start-Sleep -Milliseconds 50
            }

            # Traitement résultat
            try {
                $result = Receive-Job -Job $loadingJob -Wait -ErrorAction Stop
                
                if ($loadingJob.State -eq 'Failed') {
                    throw $loadingJob.ChildJobs[0].Error[0]
                }
                
                $users = $result | Sort-Object DisplayName
                
                Send-Progress 80 "Construction de l'affichage..."
                Initialize-ListUserUI -Window $window -AllUsersData $users
            }
            catch {
                [System.Windows.MessageBox]::Show("Erreur Graph API (Job) : $($_.Exception.Message)", "Erreur Données", "OK", "Error")
            }
            finally {
                Remove-Job -Job $loadingJob -Force -ErrorAction SilentlyContinue
            }
        }
    }

    # Configuration Identité UI
    $OnConnect = { 
        # En cas de connexion manuelle (Mode Autonome)
        $newId = Connect-AppAzureWithUser -AppId $ClientId -TenantId $TenantId
        
        if (-not $newId.Connected) {
            Write-Warning "[ListUser] Authentification échouée ou annulée : $($newId.ErrorMessage)"
            [System.Windows.MessageBox]::Show((Get-AppText 'messages.auth_failed' -Default "L'authentification a échoué.`nErreur : $($newId.ErrorMessage)"), "Erreur de Connexion", "OK", "Warning") | Out-Null
        }

        Set-AppWindowIdentity -Window $window -UserSession $newId -LauncherPID $LauncherPID -OnConnect $OnConnect -OnDisconnect $OnDisconnect
        
        # Déclenchement du chargement après connexion
        if ($newId.Connected) { & $LoadAction -UserAuth $newId }
    }
    
    $OnDisconnect = { 
        Disconnect-AppAzureUser
        Set-AppWindowIdentity -Window $window -UserSession @{Connected = $false } -LauncherPID $LauncherPID -OnConnect $OnConnect -OnDisconnect $OnDisconnect 
    }
    
    Set-AppWindowIdentity -Window $window -UserSession $userIdentity -LauncherPID $LauncherPID -OnConnect $OnConnect -OnDisconnect $OnDisconnect

    # --- CHARGEMENT INITIAL (Si hérité du Launcher) ---
    if ($userIdentity.Connected) {
        & $LoadAction -UserAuth $userIdentity
    }

}
catch {
    [System.Windows.MessageBox]::Show("Erreur UI : $($_.Exception.Message)", "Crash", "OK", "Error")
    Unlock-AppScriptLock -OwnerPID $PIDs
    exit 1
}

# =====================================================================
# 5. AFFICHAGE FINAL
# =====================================================================
Send-Progress 100 "Prêt."
try {
    $window.ShowDialog() | Out-Null
}
finally {
    Unlock-AppScriptLock -OwnerPID $PIDs
}
