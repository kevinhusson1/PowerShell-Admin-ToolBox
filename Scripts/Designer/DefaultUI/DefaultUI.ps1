#Requires -Version 7.0

<#
.SYNOPSIS
    SQUELETTE DE RÉFÉRENCE (TEMPLATE) v2.0
    Ce script sert de base pour toute nouvelle application intégrée à la Toolbox.
#>

param(
    [string]$LauncherPID,
    [string]$AuthContext
)

# =====================================================================
# 1. PRÉ-CHARGEMENT (BOILERPLATE)
# =====================================================================
try {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
} catch {
    Write-Error "WPF non disponible."; exit 1
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = (Get-Item $scriptRoot).Parent.Parent.Parent.FullName
$Global:ProjectRoot = $projectRoot
$env:PSModulePath = "$($projectRoot)\Modules;$($projectRoot)\Vendor;$($env:PSModulePath)"

# =====================================================================
# 2. CHARGEMENT DES MODULES & PROGRESSION (10%)
# =====================================================================
# Fonction locale pour le feedback Launcher
function Send-Progress { param([int]$Percent, [string]$Msg) if($LauncherPID){ Set-AppScriptProgress -OwnerPID $PID -ProgressPercentage $Percent -StatusMessage $Msg } }

Send-Progress 10 "Initialisation des modules..."
try {
    Import-Module "PSSQLite", "Core", "UI", "Localization", "Logging", "Database", "Azure" -Force
} catch {
    [System.Windows.MessageBox]::Show("Erreur critique import modules :`n$($_.Exception.Message)", "Erreur", "OK", "Error"); exit 1
}

# =====================================================================
# 3. VERROUILLAGE & CONTEXTE (30%)
# =====================================================================
Send-Progress 30 "Vérification des droits et verrous..."
try {
    Initialize-AppDatabase -ProjectRoot $projectRoot
    $manifest = Get-Content (Join-Path $scriptRoot "manifest.json") -Raw | ConvertFrom-Json
    
    # Vérification Concurrence BDD
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
    if(Test-Path $localLang){ Add-AppLocalizationSource -FilePath $localLang }

} catch {
    [System.Windows.MessageBox]::Show("Erreur démarrage :`n$($_.Exception.Message)", "Erreur", "OK", "Error"); exit 1
}

# =====================================================================
# 4. CHARGEMENT UI (60% -> 80%)
# =====================================================================
Send-Progress 60 "Chargement de l'interface..."
if ($LauncherPID) { Start-Sleep -Milliseconds 200 } # Simulation charge utile

try {
    # Import XAML
    $window = Import-AppXamlTemplate -XamlPath (Join-Path $scriptRoot "DefaultUI.xaml")
    
    # Injection Styles
    Initialize-AppUIComponents -Window $window -ProjectRoot $projectRoot -Components 'Buttons', 'Inputs', 'Layouts', 'Display', 'ProfileButton'

    Send-Progress 80 "Configuration visuelle..."
    if ($LauncherPID) { Start-Sleep -Milliseconds 200 } # Simulation charge utile

    # --- LOGIQUE DE PRÉSENTATION (En-tête dynamique) ---
    # On peuple l'en-tête automatiquement avec les infos du Manifeste
    $imgBrush = $window.FindName("HeaderIconBrush")
    if ($imgBrush -and $manifest.icon) {
        $iconPath = Join-Path $projectRoot "Templates\Resources\Icons\PNG\$($manifest.icon.value)"
        if (Test-Path $iconPath) {
            $imgBrush.ImageSource = [System.Windows.Media.Imaging.BitmapImage]::new([Uri]$iconPath)
        }
    }

    # ===============================================================
    # GESTION DE L'IDENTITÉ (Appel Modulaire)
    # ===============================================================
    $authFunctionPath = Join-Path $scriptRoot "Functions\Enable-ScriptIdentity.ps1"
    
    if (Test-Path $authFunctionPath) {
        try {
            # 1. Chargement de la fonction (Dot-Sourcing)
            . $authFunctionPath
            
            # 2. Exécution de la logique déportée
            Enable-ScriptIdentity -Window $window -LauncherPID $LauncherPID -AuthContext $AuthContext
            
        } catch {
            Write-Warning "Erreur lors de l'initialisation du module d'identité : $($_.Exception.Message)"
        }
    } else {
        Write-Warning "Fichier de fonction introuvable : $authFunctionPath"
    }

    # Optionnel : Forcer le titre/sous-titre si on ne veut pas utiliser le Binding XAML ##loc:##
    # $window.FindName("HeaderTitleText").Text = Get-AppText $manifest.name
    # $window.FindName("HeaderSubtitleText").Text = Get-AppText $manifest.description

    # --- INITIALISATION DU SCRIPT (Event Handlers) ---
    # C'est ici que vous feriez : . (Join-Path $scriptRoot "Functions\Initialize-MyUI.ps1")
    # $controls = Initialize-MyUI -Window $window

} catch {
    [System.Windows.MessageBox]::Show("Erreur UI :`n$($_.Exception.Message)", "Erreur", "OK", "Error")
    Unlock-AppScriptLock -OwnerPID $PID
    exit 1
}

# =====================================================================
# 5. AFFICHAGE (100%) & NETTOYAGE
# =====================================================================
Send-Progress 100 "Prêt."
if ($LauncherPID) { Start-Sleep -Milliseconds 300 } # Juste pour voir le 100%

try {
    $window.ShowDialog() | Out-Null
} finally {
    Unlock-AppScriptLock -OwnerPID $PID
}