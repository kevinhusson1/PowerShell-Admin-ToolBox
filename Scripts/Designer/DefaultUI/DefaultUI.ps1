#Requires -Version 5.1

<#
.SYNOPSIS
    (TEMPLATE) Interface autonome pour une action métier avec UI.
#>

param(
    [string]$LauncherPID
)

# =====================================================================
# 1. PRÉ-CHARGEMENT DES ASSEMBLAGES WPF REQUIS
# =====================================================================
try {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
} catch {
    Write-Error "Impossible de charger les assemblages WPF. Le script ne peut pas continuer."
    Read-Host "Appuyez sur Entrée pour quitter."; exit 1
}

# =====================================================================
# 2. DÉFINITION DES CHEMINS ET IMPORTS
# =====================================================================
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = (Get-Item $scriptRoot).Parent.Parent.Parent.FullName
$Global:ProjectRoot = $projectRoot
$env:PSModulePath = "$($projectRoot)\Modules;$($projectRoot)\Vendor;$($env:PSModulePath)"

try {
    Import-Module "PSSQLite" -Force
    Import-Module "Core", "UI", "Localization", "Azure", "Logging", "Database" -Force
} catch {
    [System.Windows.MessageBox]::Show("Erreur critique lors de l'import des modules :`n$($_.Exception.Message)", "Erreur de Démarrage", "OK", "Error"); exit 1
}

# =====================================================================
# 3. GESTION DU VERROU (LOCK) VIA BASE DE DONNÉES
# =====================================================================
try {
    Initialize-AppDatabase -ProjectRoot $projectRoot
    $manifest = Get-Content (Join-Path $scriptRoot "manifest.json") -Raw | ConvertFrom-Json
    
    if (-not (Test-AppScriptLock -Script $manifest)) {
        $title = Get-AppText -Key 'messages.execution_forbidden_title'
        $message = Get-AppText -Key 'messages.execution_limit_reached'
        [System.Windows.MessageBox]::Show("$message '$($manifest.name)'.", $title, "OK", "Error"); exit 1
    }
    Add-AppScriptLock -Script $manifest -OwnerPID $PID
} catch {
    $title = Get-AppText -Key 'messages.lock_error_title'
    [System.Windows.MessageBox]::Show("Erreur critique lors du verrouillage :`n$($_.Exception.Message)", $title, "OK", "Error"); exit 1
}

# =====================================================================
# 4. BLOC D'EXÉCUTION PRINCIPAL
# =====================================================================
try {
    # --- Étape 1 : Initialisation du contexte et du logging ---
    $Global:AppConfig = Get-AppConfiguration
    $VerbosePreference = if ($Global:AppConfig.enableVerboseLogging) { "Continue" } else { "SilentlyContinue" }

    # --- Étape 2 : Détermination du mode et rapport de progression initial ---
    $isLauncherMode = -not ([string]::IsNullOrEmpty($LauncherPID))
    if ($isLauncherMode) {
        Write-Verbose "Mode Lanceur détecté (lancé par le PID: $LauncherPID)."
        Set-AppScriptProgress -OwnerPID $PID -ProgressPercentage 10 -StatusMessage "10% Initialisation du contexte..."
    } else {
        Write-Verbose "Mode Autonome détecté."
    }

    if ($isLauncherMode) {
        Set-AppScriptProgress -OwnerPID $PID -ProgressPercentage 30 -StatusMessage "30% Configuration chargée."
    }
    
    # --- Étape 3 : Logique métier (connexion, etc.) ---
    if ($isLauncherMode) {
        Set-AppScriptProgress -OwnerPID $PID -ProgressPercentage 60 -StatusMessage "60% Contexte d'authentification établi."
    }

    Initialize-AppLocalization -ProjectRoot $projectRoot -Language $Global:AppConfig.defaultLanguage
    
    $scriptLangFile = "$scriptRoot\Localization\$($Global:AppConfig.defaultLanguage).json"
    if(Test-Path $scriptLangFile){ Add-AppLocalizationSource -FilePath $scriptLangFile }

    if ($isLauncherMode) {
        Set-AppScriptProgress -OwnerPID $PID -ProgressPercentage 80 -StatusMessage "80% Chargement de l'interface utilisateur..."
    }

    # --- Chargement de l'interface ---
    $xamlPath = Join-Path $scriptRoot "DefaultUI.xaml"
    $window = Import-AppXamlTemplate -XamlPath $xamlPath

    $window.Add_Closing({
        Write-Verbose (Get-AppText 'messages.window_closing_log')
    })

    # --- Affichage de la fenêtre ---
    if ($isLauncherMode) {
        Set-AppScriptProgress -OwnerPID $PID -ProgressPercentage 100 -StatusMessage "100% Interface prête."
    }
    $window.ShowDialog() | Out-Null

} catch {
    $title = Get-AppText -Key 'messages.fatal_error_title'
    [System.Windows.MessageBox]::Show("Une erreur fatale est survenue :`n$($_.Exception.Message)`n$($_.ScriptStackTrace)", $title, "OK", "Error")
} finally {
    # --- NETTOYAGE FINAL ---
    Unlock-AppScriptLock -OwnerPID $PID
}