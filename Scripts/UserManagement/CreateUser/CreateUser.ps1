#Requires -Version 5.1

<#
.SYNOPSIS
    (TEMPLATE) Interface autonome pour une action métier avec UI.
.DESCRIPTION
    Ce script est un modèle d'application autonome. Il gère son propre cycle de vie :
    - Chargement des assemblages WPF.
    - Importation des modules de l'application.
    - Verrouillage pour empêcher les exécutions multiples.
    - Initialisation du contexte (Configuration, Authentification, Traduction).
    - Chargement de son interface XAML.
    - Exécution de sa logique métier.
    - Nettoyage (libération du verrou) à la fermeture.
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
    # Si le test passe, on enregistre immédiatement notre verrou.
    Add-AppScriptLock -Script $manifest -OwnerPID $PID
} catch {
    $title = Get-AppText -Key 'messages.lock_error_title'
    [System.Windows.MessageBox]::Show("Erreur critique lors du verrouillage :`n$($_.Exception.Message)", $title, "OK", "Error"); exit 1
}

# =====================================================================
# 4. BLOC D'EXÉCUTION PRINCIPAL
# =====================================================================
try {
    # --- Initialisation du contexte ---
    $Global:AppConfig = Get-AppConfiguration
    $VerbosePreference = if ($Global:AppConfig.enableVerboseLogging) { "Continue" } else { "SilentlyContinue" }

    Connect-MgGraph -Scopes $Global:AppConfig.azure.authentication.userAuth.scopes -NoWelcome
    Write-Verbose ((Get-AppText 'messages.auth_context_init') + " $((Get-MgContext).Account).")
    
    Initialize-AppLocalization -ProjectRoot $projectRoot -Language $Global:AppConfig.defaultLanguage
    
    # --- Fusion des traductions locales ---
    $scriptLangFile = "$scriptRoot\Localization\$($Global:AppConfig.defaultLanguage).json"
    if(Test-Path $scriptLangFile){ Add-AppLocalizationSource -FilePath $scriptLangFile }

    # --- Chargement de l'interface ---
    $xamlPath = Join-Path $scriptRoot "CreateUser.xaml"
    $window = Import-AppXamlTemplate -XamlPath $xamlPath
    $testApiButton = $window.FindName("TestApiButton")
    $resultTextBox = $window.FindName("ResultTextBox")

    # --- Gestion des événements ---
    $testApiButton.Add_Click({
        $resultTextBox.Text = (Get-AppText 'create_user.api_call_inprogress')
        try {
            $me = Invoke-MgGraphRequest -Uri '/v1.0/me?$select=displayName' -Method GET
            $resultTextBox.Text = (Get-AppText 'create_user.api_call_success') + " $($me.displayName)"
        } catch {
            $resultTextBox.Text = (Get-AppText 'create_user.api_call_error') + " $($_.Exception.Message)"
        }
    })

    $window.Add_Closing({
        Write-Verbose (Get-AppText 'messages.window_closing_log')
    })

    # --- Affichage de la fenêtre ---
    $window.ShowDialog() | Out-Null

} catch {
    $title = Get-AppText -Key 'messages.fatal_error_title'
    [System.Windows.MessageBox]::Show("Une erreur fatale est survenue :`n$($_.Exception.Message)`n$($_.ScriptStackTrace)", $title, "OK", "Error")
} finally {
    # --- NETTOYAGE FINAL ---
    # Le script est TOUJOURS responsable de libérer son propre verrou.
    Unlock-AppScriptLock -OwnerPID $PID
}