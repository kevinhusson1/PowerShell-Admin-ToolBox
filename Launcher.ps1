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
try {Add-Type -AssemblyName WindowsBase, PresentationCore, PresentationFramework} catch {}

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Global:ProjectRoot = $projectRoot
$env:PSModulePath = "$($projectRoot)\Modules;$($projectRoot)\Vendor;$($env:PSModulePath)"

# On définit une préférence Verbose par défaut pour la phase de démarrage.
# Elle sera écrasée par la configuration de la base de données à l'étape 2.
$VerbosePreference = "Continue" 
# $VerbosePreference = "SilentlyContinue" 

# =====================================================================
# VARIABLES GLOBALES
# =====================================================================
$Global:AppActiveScripts = [System.Collections.Generic.List[object]]::new()
$Global:AppAzureAuth = @{ UserAuth = @{ Connected = $false } }
$Global:AppControls = @{}
$Global:IsAppAdmin = $false

# Variables globales pour la gestion Active Directory
$Global:ADPasswordManuallyChanged = $false
$Global:PIDsToMonitor = [System.Collections.Generic.List[int]]::new()

#création des timers globaux
$Global:PIDsToMonitor = [System.Collections.Generic.List[int]]::new()
$Global:uiTimer = New-Object System.Windows.Threading.DispatcherTimer
$Global:progressTimer = New-Object System.Windows.Threading.DispatcherTimer

# =====================================================================
# DÉFINITION DES UTILITAIRES D'API WIN32
# =====================================================================
try {
    # On définit les constantes nécessaires pour ShowWindow
    $showWindowAsyncConstants = @{ SW_RESTORE = 9 }
    
    Add-Type -Name "WindowUtils" -Namespace "App" -MemberDefinition @"
        [DllImport("user32.dll")]
        public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool SetForegroundWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool IsIconic(IntPtr hWnd);
"@
} catch {
    Write-Warning "Impossible de charger les utilitaires d'API Win32 pour la gestion des fenêtres."
}

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
    Import-Module "$projectRoot\Modules\Toolbox.ActiveDirectory" -Force
    Import-Module "$projectRoot\Modules\Toolbox.Security" -Force
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

    # Important : On vérifie le statut Admin APRÈS la tentative de connexion
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
    $mainWindow.Width = 650
    $mainWindow.Height = 750
    
    # ... (configuration de la fenêtre)
    Initialize-AppUIComponents -Window $mainWindow -ProjectRoot $projectRoot -Components @('Buttons', 'Inputs', 'Display', 'Navigation', 'ProfileButton', 'Layouts', 'LauncherDisplay')

    # --- 3. Peuplement de la hashtable de contrôles ---
    $Global:AppControls.Clear()

    $Global:AppControls['mainWindow']                 = $mainWindow
    $Global:AppControls['scriptsListBox']             = $mainWindow.FindName('ScriptsListBox')
    $Global:AppControls['executeButton']              = $mainWindow.FindName('ExecuteButton')
    $Global:AppControls['bringToFrontButton']         = $mainWindow.FindName('BringToFrontButton')
    $Global:AppControls['statusTextBlock']            = $mainWindow.FindName('StatusTextBlock')
    $Global:AppControls['globalCloseAppsButton']      = $mainWindow.FindName('GlobalCloseAppsButton')
    $Global:AppControls['authStatusButton']           = $mainWindow.FindName('AuthStatusButton')
    $Global:AppControls['AuthTextButton']             = $mainWindow.FindName('AuthTextButton')

    $Global:AppControls['ConnectPromptPanel']         = $mainWindow.FindName('ConnectPromptPanel')
    $Global:AppControls['descriptionTextBlock']       = $mainWindow.FindName('DescriptionTextBlock')
    $Global:AppControls['versionTextBlock']           = $mainWindow.FindName('VersionTextBlock')
    $Global:AppControls['defaultDetailText']          = $mainWindow.FindName('DefaultDetailText')
    $Global:AppControls['scriptDetailPanel']          = $mainWindow.FindName('ScriptDetailPanel')
    $Global:AppControls['DetailsPanelBorder']         = $mainWindow.FindName('DetailsPanelBorder')
    $Global:AppControls['StatusBarBorder']            = $mainWindow.FindName('StatusBarBorder')

    $Global:AppControls['scriptLoadingPanel']         = $mainWindow.FindName('ScriptLoadingPanel')
    $Global:AppControls['loadingScriptName']          = $mainWindow.FindName('LoadingScriptName')
    $Global:AppControls['loadingStatusText']          = $mainWindow.FindName('LoadingStatusText')
    $Global:AppControls['loadingStatusText']          = $mainWindow.FindName('LoadingStatusText')
    $Global:AppControls['loadingProgressBar']         = $mainWindow.FindName('LoadingProgressBar')
    $Global:AppControls['loadingProgressText']        = $mainWindow.FindName('LoadingProgressText')

    # --- CONTRÔLES DE L'ONGLET "ACCUEIL" ---
    $Global:AppControls['scriptsTabItem'] = $mainWindow.FindName('ScriptsTabItem')

    # --- CONTRÔLES DE L'ONGLET "GOUVERNANCE" ---
    $Global:AppControls['GovernanceTabItem']         = $mainWindow.FindName('GovernanceTabItem')
    $Global:AppControls['PermissionRequestsListBox'] = $mainWindow.FindName('PermissionRequestsListBox')
    $Global:AppControls['NoRequestsText']            = $mainWindow.FindName('NoRequestsText')
    $Global:AppControls['CurrentScopesListBox']      = $mainWindow.FindName('CurrentScopesListBox')
    $Global:AppControls['AddPermissionButton']       = $mainWindow.FindName('AddPermissionButton')
    $Global:AppControls['SyncAzureButton']           = $mainWindow.FindName('SyncAzureButton')
    $Global:AppControls['GrantConsentButton']        = $mainWindow.FindName('GrantConsentButton')
    $Global:AppControls['AdminMembersListBox']       = $mainWindow.FindName('AdminMembersListBox')
    $Global:AppControls['UserMembersListBox']        = $mainWindow.FindName('UserMembersListBox')

    # --- CONTRÔLES DE L'ONGLET "GESTION" ---
    $Global:AppControls['ManagementTabItem']       = $mainWindow.FindName('ManagementTabItem')
    $Global:AppControls['ManageScriptsListBox']    = $mainWindow.FindName('ManageScriptsListBox')
    $Global:AppControls['ManageDetailPanel']       = $mainWindow.FindName('ManageDetailPanel')
    $Global:AppControls['ManageSelectPrompt']      = $mainWindow.FindName('ManageSelectPrompt')

    $Global:AppControls['LibraryNewGroupTextBox']  = $mainWindow.FindName('LibraryNewGroupTextBox')
    $Global:AppControls['LibraryAddGroupButton']   = $mainWindow.FindName('LibraryAddGroupButton')
    $Global:AppControls['LibraryGroupsComboBox']   = $mainWindow.FindName('LibraryGroupsComboBox')
    $Global:AppControls['LibraryRemoveGroupButton']= $mainWindow.FindName('LibraryRemoveGroupButton')
    
    $Global:AppControls['ManageSecurityCheckList'] = $mainWindow.FindName('ManageSecurityCheckList')
    $Global:AppControls['ManageEnabledSwitch']     = $mainWindow.FindName('ManageEnabledSwitch')
    $Global:AppControls['ManageMaxRunsTextBox']    = $mainWindow.FindName('ManageMaxRunsTextBox')
    $Global:AppControls['ManageNewGroupTextBox']   = $mainWindow.FindName('ManageNewGroupTextBox')
    $Global:AppControls['ManageAddGroupButton']    = $mainWindow.FindName('ManageAddGroupButton')
    $Global:AppControls['ManageGroupsListBox']     = $mainWindow.FindName('ManageGroupsListBox')
    $Global:AppControls['ManageSaveButton']        = $mainWindow.FindName('ManageSaveButton')

    # --- CONTRÔLES DE L'ONGLET "LOG" ---
    $Global:AppControls['launcherLogRichTextBox']     = $mainWindow.FindName('LauncherLogRichTextBox')
    $Global:AppControls['clearLocksButton']           = $mainWindow.FindName('ClearLocksButton')

    # --- CONTRÔLES DE L'ONGLET "PARAMÈTRES" ---
    $Global:AppControls['settingsTabItem'] = $mainWindow.FindName('SettingsTabItem')

    # Section Générale & UI
    $Global:AppControls['generalSettingsCard']            = $mainWindow.FindName('GeneralSettingsCard')
    $Global:AppControls['settingsCompanyNameTextBox']     = $mainWindow.FindName('SettingsCompanyNameTextBox')
    $Global:AppControls['settingsAppVersionTextBox']      = $mainWindow.FindName('SettingsAppVersionTextBox')
    $Global:AppControls['settingsLanguageComboBox']       = $mainWindow.FindName('SettingsLanguageComboBox')
    $Global:AppControls['settingsVerboseLoggingCheckBox'] = $mainWindow.FindName('SettingsVerboseLoggingCheckBox')
    $Global:AppControls['settingsLauncherWidthTextBox']   = $mainWindow.FindName('SettingsLauncherWidthTextBox')
    $Global:AppControls['settingsLauncherHeightTextBox']  = $mainWindow.FindName('SettingsLauncherHeightTextBox')

    # Section Azure
    $Global:AppControls['azureSettingsCard']            = $mainWindow.FindName('AzureSettingsCard')
    
    # Global
    $Global:AppControls['settingsTenantNameTextBox']    = $mainWindow.FindName('SettingsTenantNameTextBox')
    $Global:AppControls['settingsTenantIdTextBox']      = $mainWindow.FindName('SettingsTenantIdTextBox')
    $Global:AppControls['settingsUserAuthAppIdTextBox'] = $mainWindow.FindName('SettingsUserAuthAppIdTextBox')
    
    # Identité
    $Global:AppControls['settingsAdminGroupTextBox']        = $mainWindow.FindName('SettingsAdminGroupTextBox')
    $Global:AppControls['settingsUserAuthScopesTextBox']    = $mainWindow.FindName('SettingsUserAuthScopesTextBox')
    $Global:AppControls['SettingsUserAuthTestButton']       = $mainWindow.FindName('SettingsUserAuthTestButton')
    
    # Automatisation (Certificat)
    $Global:AppControls['SettingsCertThumbprintTextBox']    = $mainWindow.FindName('SettingsCertThumbprintTextBox')
    $Global:AppControls['SettingsSelectCertButton']         = $mainWindow.FindName('SettingsSelectCertButton')
    $Global:AppControls['SettingsTestCertButton']           = $mainWindow.FindName('SettingsTestCertButton')

    # Section "ACTIVE DIRECTORY" ---
    $Global:AppControls['activeDirectorySettingsCard']       = $mainWindow.FindName('ActiveDirectorySettingsCard')
    $Global:AppControls['settingsADServiceUserTextBox']      = $mainWindow.FindName('SettingsADServiceUserTextBox')
    $Global:AppControls['settingsADServicePasswordBox']      = $mainWindow.FindName('SettingsADServicePasswordBox')
    $Global:AppControls['settingsTestADCredsButton']         = $mainWindow.FindName('SettingsTestADCredsButton')
    $Global:AppControls['settingsADDomainNameTextBox']       = $mainWindow.FindName('SettingsADDomainNameTextBox')
    $Global:AppControls['settingsADPDCNameTextBox']          = $mainWindow.FindName('SettingsADPDCNameTextBox')
    $Global:AppControls['settingsADUserOUPathTextBox']       = $mainWindow.FindName('SettingsADUserOUPathTextBox')
    $Global:AppControls['settingsADTempServerTextBox']       = $mainWindow.FindName('SettingsADTempServerTextBox')
    $Global:AppControls['settingsADConnectServerTextBox']    = $mainWindow.FindName('SettingsADConnectServerTextBox')
    $Global:AppControls['settingsADDomainUserGroupTextBox']  = $mainWindow.FindName('SettingsADDomainUserGroupTextBox')
    $Global:AppControls['settingsADExcludedGroupsTextBox']   = $mainWindow.FindName('SettingsADExcludedGroupsTextBox')
    $Global:AppControls['settingsTestInfraButton']           = $mainWindow.FindName('SettingsTestInfraButton')
    $Global:AppControls['settingsTestADObjectsButton']       = $mainWindow.FindName('SettingsTestADObjectsButton')
    $Global:AppControls['settingsSaveButton']                = $mainWindow.FindName('SettingsSaveButton')

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
# Le timer lent démarre toujours au lancement. Son comportement est aussi déplacé.
$Global:uiTimer.Start()

# =====================================================================
# ÉTAPE FINALE : AFFICHAGE DE LA FENÊTRE
# =====================================================================
$mainWindow.ShowDialog() | Out-Null