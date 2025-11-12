#Requires -Version 7.0

<#
.SYNOPSIS
    Script de test pour le design de la page des paramètres, basé sur le modèle CreateUser.
.DESCRIPTION
    Ce script est un bac à sable. Il utilise la structure complète et validée d'un script
    enfant autonome (verrouillage, initialisation, nettoyage) pour charger et afficher
    l'interface des paramètres en cours de développement.
#>

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
    Import-Module "Core", "UI", "Localization", "Logging", "Database" -Force
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
    [System.Windows.MessageBox]::Show("Erreur critique lors du verrouillage :`n$($_.Exception.Message)", "Erreur de Verrouillage", "OK", "Error"); exit 1
}

# =====================================================================
# 4. BLOC D'EXÉCUTION PRINCIPAL
# =====================================================================
try {
    # --- Initialisation du contexte ---
    $Global:AppConfig = Get-AppConfiguration
    $VerbosePreference = if ($Global:AppConfig.enableVerboseLogging) { "Continue" } else { "SilentlyContinue" }
    
    Initialize-AppLocalization -ProjectRoot $projectRoot -Language $Global:AppConfig.defaultLanguage
    
    $scriptLangFile = "$scriptRoot\Localization\$($Global:AppConfig.defaultLanguage).json"
    if(Test-Path $scriptLangFile){ Add-AppLocalizationSource -FilePath $scriptLangFile }

    # --- Chargement de l'interface ---
    $xamlPath = Join-Path $scriptRoot "SettingsDesigner.xaml"
    $window = Import-AppXamlTemplate -XamlPath $xamlPath
    
    # On charge les composants de Layout ET d'Inputs
    Initialize-AppUIComponents -Window $window -ProjectRoot $projectRoot -Components 'Layouts', 'Inputs', 'Buttons'

    # --- LIAISON DES DONNÉES DEPUIS POWERSHELL (AVEC COULEURS) ---
    $generalCard = $window.FindName("GeneralSettingsCard")
    $uiCard = $window.FindName("UiSettingsCard")
    $azureCard = $window.FindName("AzureSettingsCard")
    $securityCard = $window.FindName("SecuritySettingsCard")

    $generalCard.Tag = [PSCustomObject]@{
        Icon     = "🌐"
        Title    = Get-AppText 'settings.section_general'
        Subtitle = "Configuration de base de l'application"
        IconBackgroundColor = "#3b82f6" # Bleu
    }
    $uiCard.Tag = [PSCustomObject]@{
        Icon     = "🖼️"
        Title    = Get-AppText 'settings.section_ui'
        Subtitle = "Ajustement des dimensions du lanceur"
        IconBackgroundColor = "#8b5cf6" # Violet
    }
    $azureCard.Tag = [PSCustomObject]@{
        Icon     = "☁️"
        Title    = Get-AppText 'settings.section_azure'
        Subtitle = "Paramètres de connexion à Microsoft 365"
        IconBackgroundColor = "#06b6d4" # Cyan
    }
    $securityCard.Tag = [PSCustomObject]@{
        Icon     = "🔒"
        Title    = Get-AppText 'settings.section_security'
        Subtitle = "Gestion des accès et des droits"
        IconBackgroundColor = "#f97316" # Orange
    }
    # ---------------------------------------------

    $window.ShowDialog() | Out-Null

} catch {
    [System.Windows.MessageBox]::Show("Une erreur fatale est survenue :`n$($_.Exception.Message)`n$($_.ScriptStackTrace)", "Erreur Fatale", "OK", "Error")
} finally {
    # --- NETTOYAGE FINAL ---
    Unlock-AppScriptLock -OwnerPID $PID
}