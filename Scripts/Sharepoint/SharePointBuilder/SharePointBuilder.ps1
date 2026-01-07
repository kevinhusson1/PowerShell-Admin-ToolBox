#Requires -Version 7.0


param(
    [string]$LauncherPID,
    [string]$AuthContext,

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

    # --- GESTION DE L'IDENTITÉ (Alignement sur DefaultUI) ---
    $authFunctionPath = Join-Path $scriptRoot "Functions\Enable-ScriptIdentity.ps1"
    
    if (Test-Path $authFunctionPath) {
        # 1. Chargement
        . $authFunctionPath
        
        # 2. Exécution DIRECTE (Comme DefaultUI)
        # On ne passe plus par Add_Loaded. La fonction s'exécute, initialise l'état,
        # met à jour les boutons, et lance les process async (PnP) en interne.
        Enable-ScriptIdentity -Window $window -LauncherPID $LauncherPID -AuthContext $AuthContext
    }

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