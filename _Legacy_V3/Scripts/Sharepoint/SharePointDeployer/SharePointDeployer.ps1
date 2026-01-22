#Requires -Version 7.0

<#
.SYNOPSIS
    SharePoint Deployer (Architecture V3)

.DESCRIPTION
    Interface simplifiée pour le déploiement de structures SharePoint basées sur des configurations pré-établies.
    Architecture modulaire, exécution asynchrone et stockage SQLite distribué.
#>

param(
    [string]$LauncherPID,
    [string]$AuthContext,
    [string]$AuthUPN,     # Nouvelle méthode (Secure)
    [string]$TenantId,    # ID du Tenant pour l'auth
    [string]$ClientId     # ID de l'App (AppId)
)

# =====================================================================
# 1. PRÉ-CHARGEMENT
# =====================================================================
try {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
}
catch {
    Write-Error "WPF non disponible."; exit 1
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = (Get-Item $scriptRoot).Parent.Parent.Parent.FullName
$Global:ProjectRoot = $projectRoot
$env:PSModulePath = "$($projectRoot)\Modules;$($projectRoot)\Vendor;$($env:PSModulePath)"

# =====================================================================
# 2. MODULES
# =====================================================================
function Send-Progress { param([int]$Percent, [string]$Msg) if ($LauncherPID) { Set-AppScriptProgress -OwnerPID $PID -ProgressPercentage $Percent -StatusMessage $Msg } }

Send-Progress 10 "Initialisation des modules..."
try {
    Import-Module "PSSQLite", "Core", "UI", "Localization", "Logging", "Database", "Azure", "Toolbox.SharePoint" -Force
}
catch {
    [System.Windows.MessageBox]::Show("Erreur critique import modules :`n$($_.Exception.Message)", "Erreur", "OK", "Error"); exit 1
}

# =====================================================================
# 3. VERROUILLAGE & CONTEXTE
# =====================================================================
Send-Progress 30 "Vérification des droits et verrous..."
try {
    Initialize-AppDatabase -ProjectRoot $projectRoot
    $manifest = Get-Content (Join-Path $scriptRoot "manifest.json") -Raw | ConvertFrom-Json
    
    if (-not (Test-AppScriptLock -Script $manifest)) {
        [System.Windows.MessageBox]::Show((Get-AppText 'messages.execution_limit_reached'), (Get-AppText 'messages.execution_forbidden_title'), "OK", "Error"); exit 1
    }
    Add-AppScriptLock -Script $manifest -OwnerPID $PID

    # Chargement Config & Langue
    $Global:AppConfig = Get-AppConfiguration
    $VerbosePreference = if ($Global:AppConfig.enableVerboseLogging) { "Continue" } else { "SilentlyContinue" }
    
    # Localisation "Mille-Feuille" (Global -> Modules -> Local)
    Initialize-AppLocalization -ProjectRoot $projectRoot -Language $Global:AppConfig.defaultLanguage
    $localLang = "$scriptRoot\Localization\$($Global:AppConfig.defaultLanguage).json"
    if (Test-Path $localLang) { Add-AppLocalizationSource -FilePath $localLang }

}
catch {
    [System.Windows.MessageBox]::Show("Erreur démarrage :`n$($_.Exception.Message)", "Erreur", "OK", "Error"); exit 1
}

# =====================================================================
# 4. UI
# =====================================================================
Send-Progress 60 "Chargement de l'interface..."

try {
    $xamlPath = Join-Path $scriptRoot "SharePointDeployer.xaml"
    $window = Import-AppXamlTemplate -XamlPath $xamlPath
    
    # Injection Styles
    Initialize-AppUIComponents -Window $window -ProjectRoot $projectRoot -Components 'Buttons', 'Inputs', 'Layouts', 'Display', 'ProfileButton', 'Colors', 'Typography'

    Send-Progress 80 "Configuration visuelle..."

    # Icône En-tête
    $imgBrush = $window.FindName("HeaderIconBrush")
    if ($imgBrush -and $manifest.icon) {
        $iconPath = Join-Path $projectRoot "Templates\Resources\Icons\PNG\$($manifest.icon.value)"
        # Fallback si l'icone n'existe pas encore, on prend une par défaut si possible
        if (-not (Test-Path $iconPath)) { $iconPath = Join-Path $projectRoot "Templates\Resources\Icons\PNG\folder-structure.png" }
        
        if (Test-Path $iconPath) {
            $imgBrush.ImageSource = [System.Windows.Media.Imaging.BitmapImage]::new([Uri]$iconPath)
        }
    }
    
    # Textes Manifest
    $window.FindName("HeaderTitleText").Text = "Déploiement SharePoint"
    $window.FindName("HeaderSubtitleText").Text = "Sélectionnez une configuration et lancez le déploiement."


    # ===============================================================
    # LOGIQUE MÉTIER & AUTHENTIFICATION
    # ===============================================================
    
    # 1. Logique Principale (DeployerLogic)
    $logicPath = Join-Path $scriptRoot "Functions\Initialize-DeployerLogic.ps1"
    if (Test-Path $logicPath) {
        . $logicPath
        Initialize-DeployerLogic -Window $window -ScriptRoot $scriptRoot
    }

    # --- GESTION DE L'IDENTITÉ (Standard v3.0) ---
    
    # Récupération de la config globale si les paramètres ne sont pas passés (Robustesse)
    if (-not $TenantId) { $TenantId = $Global:AppConfig.azure.tenantId }
    if (-not $ClientId) { $ClientId = $Global:AppConfig.azure.authentication.userAuth.appId }
    
    # A. Initialisation de l'identité
    $userIdentity = $null

    # PRIORITÉ 1: Nouvelle méthode Secure (UPN via Token Cache)
    if (-not [string]::IsNullOrWhiteSpace($AuthUPN)) {
        Write-Verbose "[Deployer] AuthUPN reçu : $AuthUPN. Tentative de reprise de session..."
        try {
            $userIdentity = Connect-AppChildSession -AuthUPN $AuthUPN -TenantId $TenantId -ClientId $ClientId
            if (-not $userIdentity.Connected) {
                Write-Warning "[Deployer] Connect-AppChildSession a retourné Connected=$false (Erreur: $($userIdentity.Error))"
            }
        }
        catch {
            Write-Warning "[Deployer] Exception Auth Secure: $_" 
            $userIdentity = @{ Connected = $false }
        }
    } 
    # PRIORITÉ 2: Ancienne méthode (Fallback Legacy)
    elseif (-not [string]::IsNullOrWhiteSpace($AuthContext)) {
        Write-Verbose "[Deployer] AuthContext Legacy détecté."
        try {
            $json = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($AuthContext))
            $rawObj = $json | ConvertFrom-Json
            $userIdentity = $rawObj.UserAuth 
        }
        catch { 
            Write-Warning "[Deployer] Echec Auth Legacy: $_"
            $userIdentity = @{ Connected = $false } 
        }
    }
    else {
        # Aucune info -> Non connecté
        Write-Verbose "[Deployer] Aucun contexte d'authentification initial."
        $userIdentity = @{ Connected = $false }
    }

    # Définition des actions pour le mode autonome
    $OnConnect = {
        # Chargement à la volée des configs si nécessaire (si non passé par Launcher)
        if (-not $Global:AppConfig) { $Global:AppConfig = Get-AppConfiguration -ProjectRoot $ProjectRoot }
        
        $newIdentity = Connect-AppAzureWithUser -AppId $Global:AppConfig.azure.authentication.userAuth.appId -TenantId $Global:AppConfig.azure.tenantId
        
        # Mise à jour immédiate de l'UI après connexion réussie
        Set-AppWindowIdentity -Window $window -UserSession $newIdentity -LauncherPID $LauncherPID -OnConnect $OnConnect -OnDisconnect $OnDisconnect
        
        # --- SPÉCIFIQUE DEPLOYER : Rafraîchissement des données ---
        if ($newIdentity.Connected -and $Global:DeployerLoadAction) { 
            & $Global:DeployerLoadAction -UserAuth $newIdentity
        }
    }

    $OnDisconnect = {
        Disconnect-AppAzureUser
        $nullIdentity = @{ Connected = $false }
        Set-AppWindowIdentity -Window $window -UserSession $nullIdentity -LauncherPID $LauncherPID -OnConnect $OnConnect -OnDisconnect $OnDisconnect
    }

    # Application Visuelle (Module UI)
    Set-AppWindowIdentity -Window $window -UserSession $userIdentity -LauncherPID $LauncherPID -OnConnect $OnConnect -OnDisconnect $OnDisconnect

    # [CORRECTION] Chargement initial des données si déjà authentifié (Secure Token)
    if ($userIdentity.Connected) {
        if ($Global:DeployerLoadAction) {
            Write-Verbose "[Deployer] Identité pré-établie. Lancement du chargement des données..."
            & $Global:DeployerLoadAction -UserAuth $userIdentity
        }
    }

}
catch {
    [System.Windows.MessageBox]::Show("Erreur UI :`n$($_.Exception.Message)", "Erreur", "OK", "Error")
    Unlock-AppScriptLock -OwnerPID $PID
    exit 1
}

# =====================================================================
# 5. SHOW
# =====================================================================
Send-Progress 100 "Prêt."
try {
    $null = $window.ShowDialog()
}
catch {
    $errInfo = "Error showing dialog: $($_.Exception.Message)`n$($_.ScriptStackTrace)"
    [System.Windows.MessageBox]::Show($errInfo, "Fatal Error", "OK", "Error")
}
finally {
    Unlock-AppScriptLock -OwnerPID $PID
}
