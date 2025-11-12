# Modules/LauncherUI/Functions/Initialize-LauncherData.ps1

<#
.SYNOPSIS
    Initialise l'état visuel de tous les contrôles du lanceur au démarrage.
.DESCRIPTION
    Cette fonction est appelée une seule fois au démarrage de l'application.
    Elle peuple tous les champs de l'onglet "Paramètres" avec les valeurs
    lues depuis la base de données, gère la visibilité des sections administrateur,
    et initialise l'état des autres composants de l'interface comme le macaron
    d'authentification et la liste des scripts.
.EXAMPLE
    # Appelé depuis Launcher.ps1
    Initialize-LauncherData
.OUTPUTS
    Aucune. Modifie directement les contrôles de l'interface via $Global:AppControls.
#>
function Initialize-LauncherData {
    [CmdletBinding()]
    param()

    # --- AJOUT : Instanciation du convertisseur pour les styles d'input ---
    if (-not $Global:AppControls.mainWindow.Resources.Contains("NullToVisibilityConverter")) {
        $nullToVisibilityConverter = New-Object System.Windows.Controls.BooleanToVisibilityConverter
        $Global:AppControls.mainWindow.Resources.Add("NullToVisibilityConverter", $nullToVisibilityConverter)
    }
    
    # --- AJOUT : LIAISON DES DONNÉES POUR LES NOUVELLES CARTES ---
    $generalCard = $Global:AppControls.mainWindow.FindName("GeneralSettingsCard")
    $uiCard = $Global:AppControls.mainWindow.FindName("UiSettingsCard")
    $azureCard = $Global:AppControls.mainWindow.FindName("AzureSettingsCard")
    $securityCard = $Global:AppControls.mainWindow.FindName("SecuritySettingsCard")

    if ($generalCard) {
        $generalCard.Tag = [PSCustomObject]@{
            Icon                = "🌐"
            Title               = Get-AppText 'settings.section_general'
            Subtitle            = "Configuration de base de l'application"
            IconBackgroundColor = "#3b82f6"
        }
    }
    if ($uiCard) {
        $uiCard.Tag = [PSCustomObject]@{
            Icon                = "🖼️"
            Title               = Get-AppText 'settings.section_ui'
            Subtitle            = "Ajustement des dimensions du lanceur"
            IconBackgroundColor = "#8b5cf6"
        }
    }
    if ($azureCard) {
        $azureCard.Tag = [PSCustomObject]@{
            Icon                = "☁️"
            Title               = Get-AppText 'settings.section_azure'
            Subtitle            = "Paramètres de connexion à Microsoft 365"
            IconBackgroundColor = "#06b6d4"
        }
    }
    if ($securityCard) {
        $securityCard.Tag = [PSCustomObject]@{
            Icon                = "🔒"
            Title               = Get-AppText 'settings.section_security'
            Subtitle            = "Gestion des accès et des droits"
            IconBackgroundColor = "#f97316"
        }
    }
    # ----------------------------------------------------
    
    # --- 1. PEUPLEMENT DES PARAMÈTRES PUBLICS ---
    # Section Générale
    $Global:AppControls.settingsCompanyNameTextBox.Text = Get-AppSetting -Key 'app.companyName' -DefaultValue "Mon Entreprise"
    $Global:AppControls.settingsAppVersionTextBox.Text = Get-AppSetting -Key 'app.version' -DefaultValue "1.0.0"
    $Global:AppControls.settingsLanguageComboBox.ItemsSource = @("fr-FR", "en-US")
    $Global:AppControls.settingsLanguageComboBox.SelectedItem = Get-AppSetting -Key 'app.defaultLanguage' -DefaultValue "fr-FR"
    $Global:AppControls.settingsVerboseLoggingCheckBox.IsChecked = Get-AppSetting -Key 'app.enableVerboseLogging' -DefaultValue $false

    # Section Interface Utilisateur
    $Global:AppControls.settingsLauncherWidthTextBox.Text = Get-AppSetting -Key 'ui.launcherWidth' -DefaultValue 800
    $Global:AppControls.settingsLauncherHeightTextBox.Text = Get-AppSetting -Key 'ui.launcherHeight' -DefaultValue 700

    # --- 2. GESTION DES SECTIONS ADMINISTRATEUR ---
    if ($Global:IsAppAdmin) {
        Write-Verbose (Get-AppText -Key 'modules.launcherui.admin_mode_detected')
        
        # On affiche l'onglet et on peuple ses champs
        $Global:AppControls.settingsTabItem.Visibility = 'Visible'

        # Section Azure
        $Global:AppControls.settingsTenantIdTextBox.Text = Get-AppSetting -Key 'azure.tenantId' -DefaultValue ""
        $Global:AppControls.settingsUserAuthAppIdTextBox.Text = Get-AppSetting -Key 'azure.auth.user.appId' -DefaultValue ""
        $Global:AppControls.settingsUserAuthScopesTextBox.Text = (Get-AppSetting -Key 'azure.auth.user.scopes' -DefaultValue "User.Read") -join ", "
        $Global:AppControls.settingsCertAuthAppIdTextBox.Text = Get-AppSetting -Key 'azure.auth.cert.appId' -DefaultValue ""
        $Global:AppControls.settingsCertAuthThumbprintTextBox.Text = Get-AppSetting -Key 'azure.auth.cert.thumbprint' -DefaultValue ""
        
        # Section Sécurité
        $Global:AppControls.settingsAdminGroupTextBox.Text = Get-AppSetting -Key 'security.adminGroupName' -DefaultValue ""
        $Global:AppControls.settingsStartupAuthModeComboBox.ItemsSource = @('System', 'User')
        $Global:AppControls.settingsStartupAuthModeComboBox.SelectedItem = Get-AppSetting -Key 'security.startupAuthMode' -DefaultValue 'System'

    } else {
        Write-Verbose (Get-AppText -Key 'modules.launcherui.non_admin_mode_detected')
        # On cache l'onglet "Paramètres" pour les utilisateurs non-administrateurs
        $Global:AppControls.settingsTabItem.Visibility = 'Collapsed'
    }

    # --- 3. INITIALISATION DES AUTRES COMPOSANTS DE L'UI ---
    # On active/désactive le bouton de nettoyage des verrous en fonction des droits
    $Global:AppControls.clearLocksButton.IsEnabled = $Global:IsAppAdmin
    
    # On met à jour l'apparence du macaron d'authentification
    Update-LauncherAuthButton -AuthButton $Global:AppControls.authStatusButton

    # On peuple la liste des scripts et la barre de statut
    Update-ScriptListBoxUI -scripts $Global:AppAvailableScripts
}