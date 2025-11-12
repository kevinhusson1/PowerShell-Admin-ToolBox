# Launcher.ps1

<#
.SYNOPSIS
    Point d'entrée principal du Script Tools Box.
.DESCRIPTION
    Ce script est l'orchestrateur de l'application. Il est responsable de :
    - L'initialisation de l'environnement (modules, configuration, base de données).
    - Le chargement de l'interface graphique principale.
    - La découverte et le filtrage des scripts disponibles.
    - La gestion des événements de l'interface et du cycle de vie des scripts enfants.
#>

# =====================================================================
# ÉTAPE 0 : CONFIGURATION DE BASE
# =====================================================================
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Global:ProjectRoot = $projectRoot
$env:PSModulePath = "$($projectRoot)\Modules;$($projectRoot)\Vendor;$($env:PSModulePath)"

# On définit une préférence Verbose par défaut pour la phase de démarrage.
# Elle sera écrasée par la configuration de la base de données à l'étape 2.
$VerbosePreference = "Continue" 

# =====================================================================
# VARIABLES GLOBALES
# =====================================================================
$Global:AppActiveScripts = [System.Collections.Generic.List[object]]::new()
$Global:AppAzureAuth = @{ UserAuth = @{ Connected = $false } }
$Global:AppControls = @{}
$Global:IsAppAdmin = $false

# =====================================================================
# ÉTAPE 1 : IMPORTATION DES MODULES
# =====================================================================
try {
    # On importe d'abord notre dépendance externe embarquée
    Import-Module "$projectRoot\Vendor\PSSQLite" -Force

    # Ensuite, on importe nos propres modules
    Import-Module "$projectRoot\Modules\Azure" -Force
    Import-Module "$projectRoot\Modules\Core" -Force
    Import-Module "$projectRoot\Modules\Database" -Force
    Import-Module "$projectRoot\Modules\LauncherUI" -Force
    Import-Module "$projectRoot\Modules\Localization" -Force
    Import-Module "$projectRoot\Modules\Logging" -Force
    Import-Module "$projectRoot\Modules\UI" -Force
}
catch {
    [System.Windows.MessageBox]::Show("Erreur critique lors de l'import des modules : $($_.Exception.Message)", "Erreur de démarrage", "OK", "Error")
    exit 1
}

# =====================================================================
# ÉTAPE 2 : CHARGEMENT DE LA CONFIGURATION
# =====================================================================
try {
    Initialize-AppDatabase -ProjectRoot $projectRoot
    $Global:AppConfig = Get-AppConfiguration
    if ($null -eq $Global:AppConfig) { throw "Get-AppConfiguration n'a retourné aucune configuration." }
    
    $VerbosePreference = if ($Global:AppConfig.enableVerboseLogging) { "Continue" } else { "SilentlyContinue" }
    
    Initialize-AppLocalization -ProjectRoot $projectRoot -Language $Global:AppConfig.defaultLanguage

    if ($Global:AppConfig.security.startupAuthMode -eq 'User') {
        $authResult = Connect-AppAzureWithUser -Scopes $Global:AppConfig.azure.authentication.userAuth.scopes
        if ($authResult.Success) { $Global:AppAzureAuth.UserAuth = $authResult }
    }
    
    $Global:IsAppAdmin = Test-IsAppAdmin
}
catch {
    [System.Windows.MessageBox]::Show("Erreur critique lors du chargement de la configuration : $($_.Exception.Message)", "Erreur de démarrage", "OK", "Error")
    exit 1
}

# =====================================================================
# ÉTAPE 3 : RÉCUPÉRATION DES DONNÉES INITIALES
# =====================================================================
$Global:AppAvailableScripts = Get-FilteredAndEnrichedScripts -ProjectRoot $projectRoot

# =====================================================================
# ÉTAPE 4 : CHARGEMENT, PRÉPARATION ET GESTION DE L'UI
# =====================================================================
try {
    # --- 1. Définition des fonctions locales à l'UI ---
    # Cette fonction est privée au lanceur car elle dépend de l'existence de l'UI.
    function Write-LauncherLog {
        param([string]$Message, [string]$Level = 'Info')
        Write-AppLog -Message $Message -Level $Level -LogToUI
    }

    # --- 2. Chargement de l'interface ---
    $mainXamlPath = "$projectRoot\Templates\Layouts\MainLauncher.xaml"
    $mainWindow = Import-AppXamlTemplate -XamlPath $mainXamlPath
    $mainWindow.Title = "$(Get-AppText 'app.title') - $($Global:AppConfig.companyName)" 
    $mainWindow.Width = $Global:AppConfig.ui.launcherWidth
    $mainWindow.Height = $Global:AppConfig.ui.launcherHeight
    
    # ... (configuration de la fenêtre)
    Initialize-AppUIComponents -Window $mainWindow -ProjectRoot $projectRoot -Components @('Buttons', 'Inputs', 'Display', 'Navigation', 'ProfileButton', 'Layouts')

    # --- 3. Peuplement de la hashtable de contrôles ---
    $Global:AppControls.Clear()

    $Global:AppControls['mainWindow']                 = $mainWindow
    $Global:AppControls['scriptsListBox']             = $mainWindow.FindName('ScriptsListBox')
    $Global:AppControls['executeButton']              = $mainWindow.FindName('ExecuteButton')
    $Global:AppControls['statusTextBlock']            = $mainWindow.FindName('StatusTextBlock')
    $Global:AppControls['globalCloseAppsButton']      = $mainWindow.FindName('GlobalCloseAppsButton')
    $Global:AppControls['authStatusButton']           = $mainWindow.FindName('AuthStatusButton')
    $Global:AppControls['descriptionTextBlock']       = $mainWindow.FindName('DescriptionTextBlock')
    $Global:AppControls['versionTextBlock']           = $mainWindow.FindName('VersionTextBlock')
    $Global:AppControls['defaultDetailText']          = $mainWindow.FindName('DefaultDetailText')
    $Global:AppControls['scriptDetailPanel']          = $mainWindow.FindName('ScriptDetailPanel')

    # --- CONTRÔLES DE L'ONGLET "ACCUEIL" ---
    $Global:AppControls['scriptsTabItem'] = $mainWindow.FindName('ScriptsTabItem')

    # --- CONTRÔLES DE L'ONGLET "LOG" ---
    $Global:AppControls['launcherLogRichTextBox']     = $mainWindow.FindName('LauncherLogRichTextBox')
    $Global:AppControls['clearLocksButton']           = $mainWindow.FindName('ClearLocksButton')

    # --- CONTRÔLES DE L'ONGLET "PARAMÈTRES" ---
    $Global:AppControls['settingsTabItem'] = $mainWindow.FindName('SettingsTabItem')

    #Section Expender
    $Global:AppControls['generalSettingsCard']  = $mainWindow.FindName('GeneralSettingsCard')
    $Global:AppControls['uiSettingsCard']       = $mainWindow.FindName('UiSettingsCard')
    $Global:AppControls['azureSettingsCard']    = $mainWindow.FindName('AzureSettingsCard')
    $Global:AppControls['securitySettingsCard'] = $mainWindow.FindName('SecuritySettingsCard')

    # Section Générale
    $Global:AppControls['settingsSaveButton']         = $mainWindow.FindName('SettingsSaveButton')
    $Global:AppControls['settingsCompanyNameTextBox'] = $mainWindow.FindName('SettingsCompanyNameTextBox')
    $Global:AppControls['settingsAppVersionTextBox']        = $mainWindow.FindName('SettingsAppVersionTextBox')
    $Global:AppControls['settingsLanguageComboBox']   = $mainWindow.FindName('SettingsLanguageComboBox')
    $Global:AppControls['settingsVerboseLoggingCheckBox']   = $mainWindow.FindName('SettingsVerboseLoggingCheckBox')

    # Section UI
    $Global:AppControls['settingsLauncherWidthTextBox']     = $mainWindow.FindName('SettingsLauncherWidthTextBox')
    $Global:AppControls['settingsLauncherHeightTextBox']    = $mainWindow.FindName('SettingsLauncherHeightTextBox')

    # Section Azure
    $Global:AppControls['settingsTenantIdTextBox']   = $mainWindow.FindName('SettingsTenantIdTextBox')
    $Global:AppControls['settingsUserAuthAppIdTextBox'] = $mainWindow.FindName('SettingsUserAuthAppIdTextBox')
    $Global:AppControls['settingsUserAuthScopesTextBox'] = $mainWindow.FindName('SettingsUserAuthScopesTextBox')
    $Global:AppControls['settingsCertAuthAppIdTextBox'] = $mainWindow.FindName('SettingsCertAuthAppIdTextBox')
    $Global:AppControls['settingsCertAuthThumbprintTextBox'] = $mainWindow.FindName('SettingsCertAuthThumbprintTextBox')

    # Section Sécurité
    $Global:AppControls['settingsAdminGroupTextBox'] = $mainWindow.FindName('SettingsAdminGroupTextBox')
    $Global:AppControls['SettingsStartupAuthModeComboBox'] = $mainWindow.FindName('SettingsStartupAuthModeComboBox')

    # --- 4. Initialisation des données de l'UI ---
    Initialize-LauncherData

    # --- 5. Attachement des événements ---
    Register-LauncherEvents -ProjectRoot $projectRoot
    
    # --- 6. Finitions UI (icône) ---
    $headerIconMask = $mainWindow.FindName('HeaderIconMask')
    $headerIconPath = Join-Path -Path $projectRoot -ChildPath "Templates\Resources\Icons\PNG\terminal.png"
    if (Test-Path $headerIconPath) {
        $bitmap = [System.Windows.Media.Imaging.BitmapImage]::new()
        $bitmap.BeginInit()
        $bitmap.UriSource = [System.Uri]::new($headerIconPath, [System.UriKind]::Absolute)
        $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bitmap.EndInit()
        $bitmap.Freeze()
        $headerIconMask.ImageSource = $bitmap
    }

    # --- 7. Log de Démarrage ---
    Write-LauncherLog -Message (Get-AppText 'launcherLog.successLaunch') -Level Success
}
catch {
    [System.Windows.MessageBox]::Show("Erreur critique lors du chargement de l'interface : $($_.Exception.Message)`n$($_.ScriptStackTrace)", "Erreur de démarrage", "OK", "Error")
    exit 1
}


# =====================================================================
# GESTION DES TÂCHES DE FOND (TIMER)
# =====================================================================
$uiTimer = New-Object System.Windows.Threading.DispatcherTimer
$uiTimer.Interval = [TimeSpan]::FromSeconds(2)
$uiTimer.Add_Tick({
    # Sécurité : ne rien faire si les contrôles ne sont pas encore chargés.
    if (-not $Global:AppControls.ContainsKey('scriptsListBox')) { return }

    # On cherche tous les processus de script qui se sont terminés.
    $scriptsToRemove = @($Global:AppActiveScripts | Where-Object { $_.HasExited })
    
    if ($scriptsToRemove.Count -gt 0) {
        foreach($process in $scriptsToRemove){
            # On retrouve l'objet script correspondant dans notre liste interne.
            $finishedScript = $Global:AppAvailableScripts | Where-Object { $_.pid -eq $process.Id }

            if ($finishedScript) {
                
                Write-LauncherLog -Message "Le script '$($finishedScript.name)' (PID: $($finishedScript.pid)) a été détecté comme terminé." -Level Info

                # --- LE LANCEUR NE GÈRE QUE SON PROPRE ÉTAT ---
                
                # 1. On réinitialise l'état de l'objet script en mémoire.
                $finishedScript.IsRunning = $false
                $finishedScript.pid = $null
                
                # 2. Si le script terminé était sélectionné, on met à jour l'UI du bouton principal.
                if ($Global:AppControls.scriptsListBox.SelectedItem -eq $finishedScript) {
                    $Global:AppControls.executeButton.Content = Get-AppText -Key 'launcher.execute_button'
                    $Global:AppControls.executeButton.Style = $Global:AppControls.executeButton.FindResource('PrimaryButtonStyle')
                }
            }
            # On retire le processus de la liste des scripts actifs.
            $Global:AppActiveScripts.Remove($process)
        }
        # On force l'interface (les tuiles) à se redessiner pour refléter le nouvel état.
        $Global:AppControls.scriptsListBox.Items.Refresh()
    }

    # --- MISE À JOUR DE L'UI GLOBALE (ne change pas) ---

    # Mise à jour du bouton "Fermer toutes les applications"
    if ($Global:AppActiveScripts.Count -gt 0) {
        $Global:AppControls.globalCloseAppsButton.Visibility = 'Visible'
    } else {
        $Global:AppControls.globalCloseAppsButton.Visibility = 'Collapsed'
    }

    # Mise à jour de la barre de statut
    $activeScriptsCount = $Global:AppActiveScripts.Count
    $statusTextAvailable = Get-AppText 'launcher.status_available'
    $statusTextActive = Get-AppText 'launcher.status_active'
    $Global:AppControls.statusTextBlock.Text = "$statusTextAvailable : $($Global:AppAvailableScripts.Count)  •  $statusTextActive : $activeScriptsCount"
})
$uiTimer.Start()

# =====================================================================
# ÉTAPE FINALE : AFFICHAGE DE LA FENÊTRE
# =====================================================================
$mainWindow.ShowDialog() | Out-Null