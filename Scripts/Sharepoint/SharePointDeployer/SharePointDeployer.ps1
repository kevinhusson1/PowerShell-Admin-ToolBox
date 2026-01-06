#Requires -Version 7.0

<#
.SYNOPSIS
    SharePoint Deployer
    Interface simplifiée pour le déploiement de structures SharePoint basées sur des configurations pré-établies.
#>

param(
    [string]$LauncherPID,
    [string]$AuthContext
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

    # 2. Identité
    $authFunctionPath = Join-Path $scriptRoot "Functions\Enable-ScriptIdentity.ps1"
    if (Test-Path $authFunctionPath) {
        . $authFunctionPath
        Enable-ScriptIdentity -Window $window -LauncherPID $LauncherPID -AuthContext $AuthContext -OnAuthChange $Global:DeployerLoadAction
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
