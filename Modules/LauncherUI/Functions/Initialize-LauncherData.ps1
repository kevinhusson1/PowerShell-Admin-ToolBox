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

    # --- On s'assure que le convertisseur pour les styles d'input est disponible ---
    if ($Global:AppControls.mainWindow -and -not $Global:AppControls.mainWindow.Resources.Contains("NullToVisibilityConverter")) {
        $nullToVisibilityConverter = New-Object System.Windows.Controls.BooleanToVisibilityConverter
        $Global:AppControls.mainWindow.Resources.Add("NullToVisibilityConverter", $nullToVisibilityConverter)
    }
    
    # --- AJOUT : LIAISON DES DONNÉES POUR LES NOUVELLES CARTES ---
    $generalCard = $Global:AppControls.mainWindow.FindName("GeneralSettingsCard")
    $azureCard = $Global:AppControls.mainWindow.FindName("AzureSettingsCard")
    $adCard = $Global:AppControls.mainWindow.FindName("ActiveDirectorySettingsCard")

    if ($generalCard) {
        $generalCard.Tag = [PSCustomObject]@{
            Icon                = "🌐"
            Title               = Get-AppText 'settings.section_general'
            Subtitle            = "Configuration de base de l'application"
            IconBackgroundColor = "#3b82f6"
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
    if ($adCard) {
        $adCard.Tag = [PSCustomObject]@{
            Icon                = "🗄️"
            Title               = Get-AppText 'settings.section_ad'
            Subtitle            = "Configuration pour l'interaction avec l'annuaire local"
            IconBackgroundColor = "#787A7D" # Un gris neutre
        }
    }

    # --- 1. PEUPLEMENT DES PARAMÈTRES ---
    # Général
    $Global:AppControls.settingsCompanyNameTextBox.Text = $Global:AppConfig.companyName
    $Global:AppControls.settingsAppVersionTextBox.Text = $Global:AppConfig.applicationVersion
    $Global:AppControls.settingsLanguageComboBox.ItemsSource = @("fr-FR", "en-US")
    $Global:AppControls.settingsLanguageComboBox.SelectedItem = $Global:AppConfig.defaultLanguage
    $Global:AppControls.settingsVerboseLoggingCheckBox.IsChecked = $Global:AppConfig.enableVerboseLogging
    $Global:AppControls.settingsLauncherWidthTextBox.Text = $Global:AppConfig.ui.launcherWidth
    $Global:AppControls.settingsLauncherHeightTextBox.Text = $Global:AppConfig.ui.launcherHeight

    # --- 2. GESTION DES SECTIONS ADMINISTRATEUR ---
    if ($Global:IsAppAdmin) {
        $Global:AppControls.settingsTabItem.Visibility = 'Visible'
        $Global:AppControls.GovernanceTabItem.Visibility = 'Visible' # NOUVEAU : Onglet Gouvernance visible pour admin

        # Azure & Sécurité
        $Global:AppControls.settingsTenantNameTextBox.Text = $Global:AppConfig.azure.tenantName
        $Global:AppControls.settingsTenantIdTextBox.Text = $Global:AppConfig.azure.tenantId
        $Global:AppControls.settingsUserAuthAppIdTextBox.Text = $Global:AppConfig.azure.authentication.userAuth.appId
        $Global:AppControls.settingsAdminGroupTextBox.Text = $Global:AppConfig.security.adminGroupName
        $Global:AppControls.settingsUserAuthScopesTextBox.Text = $Global:AppConfig.azure.authentication.userAuth.scopes -join ", "

        # Certificat
        if ($Global:AppControls.ContainsKey('SettingsCertThumbprintTextBox')) {
            $Global:AppControls.SettingsCertThumbprintTextBox.Text = $Global:AppConfig.azure.certThumbprint
        }
        
        # Peuplement de la section Active Directory ---
        $Global:AppControls.settingsADServiceUserTextBox.Text = $Global:AppConfig.ad.serviceUser
        if (-not [string]::IsNullOrEmpty($Global:AppConfig.ad.servicePassword)) {
            $Global:AppControls.settingsADServicePasswordBox.Password = "●●●●●●●●"
        }
        # On réinitialise le drapeau à chaque chargement
        $Global:ADPasswordManuallyChanged = $false
        $Global:AppControls.settingsADTempServerTextBox.Text = $Global:AppConfig.ad.tempServer
        $Global:AppControls.settingsADConnectServerTextBox.Text = $Global:AppConfig.ad.connectServer
        $Global:AppControls.settingsADDomainNameTextBox.Text = $Global:AppConfig.ad.domainName
        $Global:AppControls.settingsADUserOUPathTextBox.Text = $Global:AppConfig.ad.userOUPath
        $Global:AppControls.settingsADPDCNameTextBox.Text = $Global:AppConfig.ad.pdcName
        $Global:AppControls.settingsADDomainUserGroupTextBox.Text = $Global:AppConfig.ad.domainUserGroup
        $Global:AppControls.settingsADExcludedGroupsTextBox.Text = $Global:AppConfig.ad.excludedGroups -join ",`n"

        # On utilise la liste globale qui contient déjà les infos de la BDD (Enabled/MaxRuns)
        Update-ManagementScriptList

    } else {
        Write-Verbose (Get-AppText -Key 'modules.launcherui.non_admin_mode_detected')
        $Global:AppControls.settingsTabItem.Visibility = 'Collapsed'
        $Global:AppControls.GovernanceTabItem.Visibility = 'Collapsed'
    }

    # --- 3. INITIALISATION DES AUTRES COMPOSANTS DE L'UI ---
    $Global:AppControls.clearLocksButton.IsEnabled = $Global:IsAppAdmin
    Update-LauncherAuthButton -AuthButton $Global:AppControls.authStatusButton
    Update-ScriptListBoxUI -scripts $Global:AppAvailableScripts

    # --- GESTION ÉTAT INITIAL DES BOUTONS AZURE ---
    
    # 1. Désactivation du bouton de connexion principal si pas d'AppID
    $authButton = $Global:AppControls.authStatusButton
    $userAppId = $Global:AppConfig.azure.authentication.userAuth.appId
    
    if ([string]::IsNullOrWhiteSpace($userAppId)) {
        $authButton.IsEnabled = $false
        $authButton.ToolTip = (Get-AppText 'settings.azure_authbutton_disabled_tooltip')
    } else {
        $authButton.IsEnabled = $true
        # Le tooltip normal est géré par Update-LauncherAuthButton
    }

    # 2. Gestion du bouton "Tester la connexion" (User)
    # On vérifie que le contrôle existe bien avant d'y toucher (sécurité)
    if ($Global:AppControls.ContainsKey('SettingsUserAuthTestButton') -and $null -ne $Global:AppControls['SettingsUserAuthTestButton']) {
        $Global:AppControls.SettingsUserAuthTestButton.IsEnabled = $Global:AppAzureAuth.UserAuth.Connected
    }
    
    # NOTE : Le code concernant SettingsCertAuthTestButton a été SUPPRIMÉ ici pour éviter le crash.
}