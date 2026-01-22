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
function Send-Progress { param([int]$Percent, [string]$Msg) if ($LauncherPID) { Set-AppScriptProgress -OwnerPID $PID -ProgressPercentage $Percent -StatusMessage $Msg } }

Send-Progress 10 "Initialisation..."

# =====================================================================
# 2. CHARGEMENT MODULES & CONFIG
# =====================================================================
try {
    Import-Module "PSSQLite", "Core", "UI", "Localization", "Logging", "Database", "Azure" -Force
    
    # Chargement dynamique des fonctions locales
    Get-ChildItem -Path (Join-Path $scriptRoot "Functions") -Filter "*.ps1" | ForEach-Object { . $_.FullName }

    Initialize-AppDatabase -ProjectRoot $projectRoot
    $manifest = Get-Content (Join-Path $scriptRoot "manifest.json") -Raw | ConvertFrom-Json
    
    # Verrouillage
    if (-not (Test-AppScriptLock -Script $manifest)) {
        [System.Windows.MessageBox]::Show((Get-AppText 'messages.execution_limit_reached'), "Stop", "OK", "Error"); exit 1
    }
    Add-AppScriptLock -Script $manifest -OwnerPID $PID

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

    # --- LOGIQUE DE CHARGEMENT DES DONNÉES ---
    $LoadAction = {
        param($UserAuth)
        if ($UserAuth.Connected) {
            Send-Progress 60 "Récupération de l'annuaire depuis Microsoft Graph..."
            # On passe la société définie dans la config globale comme filtre par défaut
            # Si Config vide (mode autonome brut), on peut laisser $null ou un par défaut
            $companyFilter = if ($Global:AppConfig.companyName) { $Global:AppConfig.companyName } else { $null }
            
            # Utilisation du thread UI pour simplifier (Async/Await pattern possible pour V4)
            try {
                # On force un rafraichissement UI pour montrer le chargement
                [System.Windows.Forms.Application]::DoEvents() 
                
                $users = Get-GraphDirectoryUsers -CompanyNameFilter $companyFilter
                
                Send-Progress 80 "Construction de l'affichage..."
                Initialize-ListUserUI -Window $window -AllUsersData $users
            }
            catch {
                [System.Windows.MessageBox]::Show("Erreur Graph API : $($_.Exception.Message)", "Erreur Données", "OK", "Error")
            }
        }
    }

    # Configuration Identité UI
    $OnConnect = { 
        # En cas de connexion manuelle (Mode Autonome)
        $newId = Connect-AppAzureWithUser -AppId $ClientId -TenantId $TenantId
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
    Unlock-AppScriptLock -OwnerPID $PID
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
    Unlock-AppScriptLock -OwnerPID $PID
}
