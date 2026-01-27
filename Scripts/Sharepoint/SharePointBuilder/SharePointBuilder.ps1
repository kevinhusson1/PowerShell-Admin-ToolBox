#Requires -Version 7.0


param(
    [string]$LauncherPID,
    [string]$AuthContext,
    [string]$AuthUPN,     # Nouvelle méthode (Secure)
    [string]$TenantId,    # ID du Tenant pour l'auth
    [string]$ClientId,    # ID de l'App (AppId)

    # Paramètres Autopilot
    [string]$AutoSiteUrl,       # URL du site cible
    [string]$AutoLibraryName,   # Nom de la bibliothèque
    [string]$AutoTemplateId,    # ID du modèle à forcer
    [hashtable]$AutoFormData    # Données pour le formulaire (ex: @{Client="Total"; Year="2024"})
)

# --- CORRECTIF : NETTOYAGE PRÉVENTIF DES VARIABLES GLOBALES ---
# Cela évite que des tests précédents dans la même console ne polluent l'état
$Global:AppAzureAuth = $null
$Global:AppControls = @{}

$VerbosePreference = 'Continue' 

# 1. PRÉ-CHARGEMENT
try { Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase } catch { exit 1 }

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = (Get-Item $scriptRoot).Parent.Parent.Parent.FullName
$Global:ProjectRoot = $projectRoot
$env:PSModulePath = "$($projectRoot)\Modules;$($projectRoot)\Vendor;$($env:PSModulePath)"

# 2. MODULES
function Send-Progress { param([int]$Percent, [string]$Msg) if ($LauncherPID) { Set-AppScriptProgress -OwnerPID $PID -ProgressPercentage $Percent -StatusMessage $Msg } }

Send-Progress 10 "Initialisation des modules..."
try {
    Import-Module "PSSQLite", "Core", "UI", "Localization", "Logging", "Database", "Azure", "Toolbox.SharePoint" -Force
}
catch {
    [System.Windows.MessageBox]::Show("Erreur modules : $($_.Exception.Message)", "Fatal", "OK", "Error"); exit 1
}

# 3. INIT & LOCK
Send-Progress 30 "Vérification des droits et verrous..."
try {
    Initialize-AppDatabase -ProjectRoot $projectRoot
    $manifest = Get-Content (Join-Path $scriptRoot "manifest.json") -Raw | ConvertFrom-Json
    
    if (-not (Test-AppScriptLock -Script $manifest)) { 
        [System.Windows.MessageBox]::Show("Déjà en cours d'exécution.", "Stop", "OK", "Warning"); exit 1 
    }
    Add-AppScriptLock -Script $manifest -OwnerPID $PID

    # Chargement Config & Langue
    $Global:AppConfig = Get-AppConfiguration
    $VerbosePreference = if ($Global:AppConfig.enableVerboseLogging) { "Continue" } else { "SilentlyContinue" }

    Initialize-AppLocalization -ProjectRoot $projectRoot -Language $Global:AppConfig.defaultLanguage
    
    # Chargement Loc Locale
    $localLang = "$scriptRoot\Localization\$($Global:AppConfig.defaultLanguage).json"
    if (Test-Path $localLang) { Add-AppLocalizationSource -FilePath $localLang }

}
catch {
    [System.Windows.MessageBox]::Show("Erreur init : $($_.Exception.Message)", "Fatal", "OK", "Error"); exit 1
}

# 4. UI
Send-Progress 60 "Chargement de l'interface..."
try {
    $window = Import-AppXamlTemplate -XamlPath (Join-Path $scriptRoot "SharePointBuilder.xaml")
    Initialize-AppUIComponents -Window $window -ProjectRoot $projectRoot -Components 'Buttons', 'Inputs', 'Layouts', 'Display', 'ProfileButton', 'Navigation'

    # Icône
    $imgBrush = $window.FindName("HeaderIconBrush")
    if ($imgBrush -and $manifest.icon) {
        $iconPath = Join-Path $projectRoot "Templates\Resources\Icons\PNG\$($manifest.icon.value)"
        if (Test-Path $iconPath) { $imgBrush.ImageSource = [System.Windows.Media.Imaging.BitmapImage]::new([Uri]$iconPath) }
    }

    Send-Progress 80 "Configuration visuelle..."

    # --- LOGIQUE MÉTIER (BuilderLogic) ---
    # On le place AVANT l'auth pour que les champs soient prêts si l'auth est rapide
    $builderLogicPath = Join-Path $scriptRoot "Functions\Initialize-BuilderLogic.ps1"
    if (Test-Path $builderLogicPath) {
        . $builderLogicPath
        $context = @{ 
            Window          = $window;
            ScriptRoot      = $scriptRoot;
            AutoSiteUrl     = $AutoSiteUrl;
            AutoLibraryName = $AutoLibraryName;
            AutoTemplateId  = $AutoTemplateId;
            AutoFormData    = $AutoFormData;
        }
        Initialize-BuilderLogic -Context $context
    }

    # --- GESTION DE L'IDENTITÉ (Standard v3.0) ---
    
    # Récupération de la config globale si les paramètres ne sont pas passés (Robustesse)
    if (-not $TenantId) { $TenantId = $Global:AppConfig.azure.tenantId }
    if (-not $ClientId) { $ClientId = $Global:AppConfig.azure.authentication.userAuth.appId }
    
    # A. Initialisation de l'identité
    $userIdentity = $null

    # PRIORITÉ 1: Nouvelle méthode Secure (UPN via Token Cache)
    if (-not [string]::IsNullOrWhiteSpace($AuthUPN)) {
        Write-Verbose "[Builder] AuthUPN reçu : $AuthUPN. Tentative de reprise de session..."
        try {
            $userIdentity = Connect-AppChildSession -AuthUPN $AuthUPN -TenantId $TenantId -ClientId $ClientId
            if (-not $userIdentity.Connected) {
                Write-Warning "[Builder] Connect-AppChildSession a retourné Connected=$false (Erreur: $($userIdentity.Error))"
            }
        }
        catch {
            Write-Warning "[Builder] Exception Auth Secure: $_" 
            $userIdentity = @{ Connected = $false }
        }
    } 
    # PRIORITÉ 2: Ancienne méthode (Fallback Legacy)
    elseif (-not [string]::IsNullOrWhiteSpace($AuthContext)) {
        Write-Verbose "[Builder] AuthContext Legacy détecté."
        try {
            $json = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($AuthContext))
            $rawObj = $json | ConvertFrom-Json
            $userIdentity = $rawObj.UserAuth 
        }
        catch { 
            Write-Warning "[Builder] Echec Auth Legacy: $_"
            $userIdentity = @{ Connected = $false } 
        }
    }
    else {
        # Aucune info -> Non connecté
        Write-Verbose "[Builder] Aucun contexte d'authentification initial."
        $userIdentity = @{ Connected = $false }
    }

    # Définition des actions pour le mode autonome
    $OnConnect = {
        # Chargement à la volée des configs si nécessaire (si non passé par Launcher)
        if (-not $Global:AppConfig) { $Global:AppConfig = Get-AppConfiguration -ProjectRoot $ProjectRoot }
        
        $newIdentity = Connect-AppAzureUser -AppId $Global:AppConfig.azure.authentication.userAuth.appId -TenantId $Global:AppConfig.azure.tenantId
        
        # Mise à jour immédiate de l'UI après connexion réussie
        Set-AppWindowIdentity -Window $window -UserSession $newIdentity -LauncherPID $LauncherPID -OnConnect $OnConnect -OnDisconnect $OnDisconnect
    }

    $OnDisconnect = {
        Disconnect-AppAzureUser
        $nullIdentity = @{ Connected = $false }
        Set-AppWindowIdentity -Window $window -UserSession $nullIdentity -LauncherPID $LauncherPID -OnConnect $OnConnect -OnDisconnect $OnDisconnect
    }

    # Application Visuelle (Module UI)
    Set-AppWindowIdentity -Window $window -UserSession $userIdentity -LauncherPID $LauncherPID -OnConnect $OnConnect -OnDisconnect $OnDisconnect



}
catch {
    [System.Windows.MessageBox]::Show("Erreur UI : $($_.Exception.Message)", "Fatal", "OK", "Error")
    Unlock-AppScriptLock -OwnerPID $PID
    exit 1
}

# 5. SHOW
Send-Progress 100 "Prêt."
try {
    $window.ShowDialog() | Out-Null
}
finally {
    Unlock-AppScriptLock -OwnerPID $PID
}