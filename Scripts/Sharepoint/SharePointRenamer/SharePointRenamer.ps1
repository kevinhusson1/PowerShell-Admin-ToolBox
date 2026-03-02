#Requires -Version 7.0

<#
.SYNOPSIS
    SharePoint Renamer (Maintenance Tool)

.DESCRIPTION
    Outil de maintenance pour renommer des dossiers racines SharePoint et mettre à jour leurs métadonnées
    ainsi que réparer les liens internes.
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
# PRÉ-CHARGEMENT CRITIQUE : Évite un conflit de version MSAL avec PnP.PowerShell
Import-Module Microsoft.Graph.Authentication -MinimumVersion 2.32.0 -ErrorAction SilentlyContinue

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
    Import-Module "PSSQLite", "Core", "UI", "Localization", "Logging", "Database", "Azure" -Force
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
    $xamlPath = Join-Path $scriptRoot "SharePointRenamer.xaml"
    $window = Import-AppXamlTemplate -XamlPath $xamlPath
    
    if (-not $window) { throw "Impossible de charger la fenêtre XAML (Resultat null)." }
    
    # Injection Styles
    Initialize-AppUIComponents -Window $window -ProjectRoot $projectRoot -Components 'Buttons', 'Inputs', 'Layouts', 'Display', 'ProfileButton'

    Send-Progress 80 "Configuration visuelle..."

    # Icône En-tête (Reuse Deployer Icon or specific)
    $imgBrush = $window.FindName("HeaderIconBrush")
    # Tenter icone specifique
    $iconPath = Join-Path $projectRoot "Templates\Resources\Icons\PNG\edit.png" # Hypothèse
    if (-not (Test-Path $iconPath)) { $iconPath = Join-Path $projectRoot "Templates\Resources\Icons\PNG\edit.png" }
    
    if ((Test-Path $iconPath) -and $imgBrush) {
        $imgBrush.ImageSource = [System.Windows.Media.Imaging.BitmapImage]::new([Uri]$iconPath)
    }
    
    # Textes Manifest
    $tTitle = $window.FindName("HeaderTitleText")
    if ($tTitle) { $tTitle.Text = "SharePoint Renamer" }
    $tSub = $window.FindName("HeaderSubtitleText")
    if ($tSub) { $tSub.Text = "Maintenance des dossiers et réparation des liens" }


    # ===============================================================
    # LOGIQUE MÉTIER & AUTHENTIFICATION
    # ===============================================================
    
    # 1. Logique Principale (RenamerLogic)
    $logicPath = Join-Path $scriptRoot "Functions\Initialize-RenamerLogic.ps1"
    if (Test-Path $logicPath) {
        . $logicPath
        Initialize-RenamerLogic -Window $window -ScriptRoot $scriptRoot
    }

    # --- GESTION DE L'IDENTITÉ (Standard v3.0) ---
    
    # Récupération de la config globale si les paramètres ne sont pas passés (Robustesse)
    if (-not $TenantId) { $TenantId = $Global:AppConfig.azure.tenantId }
    if (-not $ClientId) { $ClientId = $Global:AppConfig.azure.authentication.userAuth.appId }
    
    # A. Initialisation de l'identité
    $userIdentity = $null

    # PRIORITÉ 1: Nouvelle méthode Secure (UPN via Token Cache)
    if (-not [string]::IsNullOrWhiteSpace($AuthUPN)) {
        Write-Verbose "[Renamer] AuthUPN reçu : $AuthUPN. Tentative de reprise de session..."
        try {
            $userIdentity = Connect-AppChildSession -AuthUPN $AuthUPN -TenantId $TenantId -ClientId $ClientId
            if (-not $userIdentity.Connected) {
                Write-Warning "[Renamer] Connect-AppChildSession a retourné Connected=$false (Erreur: $($userIdentity.Error))"
            }
        }
        catch {
            Write-Warning "[Renamer] Exception Auth Secure: $_" 
            $userIdentity = @{ Connected = $false }
        }
    } 
    # PRIORITÉ 2: Ancienne méthode (Fallback Legacy)
    elseif (-not [string]::IsNullOrWhiteSpace($AuthContext)) {
        Write-Verbose "[Renamer] AuthContext Legacy détecté."
        try {
            $json = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($AuthContext))
            $rawObj = $json | ConvertFrom-Json
            $userIdentity = $rawObj.UserAuth 
        }
        catch { 
            Write-Warning "[Renamer] Echec Auth Legacy: $_"
            $userIdentity = @{ Connected = $false } 
        }
    }
    else {
        # Aucune info -> Non connecté
        Write-Verbose "[Renamer] Aucun contexte d'authentification initial."
        $userIdentity = @{ Connected = $false }
    }

    # Définition des actions pour le mode autonome
    $OnConnect = {
        # Chargement à la volée des configs si nécessaire (si non passé par Launcher)
        if (-not $Global:AppConfig) { $Global:AppConfig = Get-AppConfiguration -ProjectRoot $ProjectRoot }
        
        $newIdentity = Connect-AppAzureWithUser -AppId $Global:AppConfig.azure.authentication.userAuth.appId -TenantId $Global:AppConfig.azure.tenantId
        
        if (-not $newIdentity.Connected) {
            Write-Warning "[Renamer] Authentification échouée ou annulée : $($newIdentity.ErrorMessage)"
            $msg = Get-AppText 'messages.auth_failed'
            if (-not $msg) { $msg = "L'authentification a échoué." }
            [System.Windows.MessageBox]::Show("$msg`nErreur : $($newIdentity.ErrorMessage)", "Erreur de Connexion", "OK", "Warning") | Out-Null
        }

        # Mise à jour immédiate de l'UI après tentative de connexion
        Set-AppWindowIdentity -Window $window -UserSession $newIdentity -LauncherPID $LauncherPID -OnConnect $OnConnect -OnDisconnect $OnDisconnect
        
        # --- SPÉCIFIQUE DEPLOYER : Rafraîchissement des données ---
        if ($newIdentity.Connected -and $Global:RenamerLoadAction) { 
            & $Global:RenamerLoadAction -UserAuth $newIdentity
        }
    }

    $OnDisconnect = {
        Disconnect-AppAzureUser
        $nullIdentity = @{ Connected = $false }
        Set-AppWindowIdentity -Window $window -UserSession $nullIdentity -LauncherPID $LauncherPID -OnConnect $OnConnect -OnDisconnect $OnDisconnect
        
        # [CORRECTION] Mise à jour UI Renamer
        if ($Global:RenamerLoadAction) { 
            & $Global:RenamerLoadAction -UserAuth $nullIdentity
        }
    }

    # Application Visuelle (Module UI)
    Set-AppWindowIdentity -Window $window -UserSession $userIdentity -LauncherPID $LauncherPID -OnConnect $OnConnect -OnDisconnect $OnDisconnect

    # [CORRECTION] Chargement initial des données si déjà authentifié (Secure Token)
    if ($userIdentity.Connected) {
        if ($Global:RenamerLoadAction) {
            Write-Verbose "[Renamer] Identité pré-établie. Lancement du chargement des données..."
            & $Global:RenamerLoadAction -UserAuth $userIdentity
        }
    }
}
catch {
    [System.Windows.MessageBox]::Show("Erreur critique Runtime :`n$($_.Exception.Message)", "Erreur", "OK", "Error")
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
