# Modules/LauncherUI/Functions/Register-LauncherEvents.ps1

<#
.SYNOPSIS
    Attache tous les gestionnaires d'événements aux contrôles de l'interface du lanceur.
.DESCRIPTION
    Cette fonction est le "cerveau" de l'application. Elle connecte les actions de
    l'utilisateur (clics, sélections) à la logique métier correspondante (lancer un
    script, sauvegarder des paramètres, se connecter, etc.).
.PARAMETER ProjectRoot
    Le chemin racine du projet, nécessaire pour certaines opérations de fichier.
.EXAMPLE
    # Appelé une seule fois au démarrage dans Launcher.ps1
    Register-LauncherEvents -ProjectRoot $projectRoot
.OUTPUTS
    Aucune. Modifie les contrôles de l'interface en y attachant des blocs de script.
#>

function Register-LauncherEvents {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot
    )

    # --- Événement du bouton Exécuter/Arrêter ---
    $Global:AppControls.executeButton.Add_Click({
        $selectedScript = $Global:AppControls.scriptsListBox.SelectedItem
        if (-not $selectedScript) { return }

        if ($selectedScript.IsRunning) {
            Stop-AppScript -SelectedScript $selectedScript
        } else {
            Start-AppScript -SelectedScript $selectedScript -ProjectRoot $ProjectRoot
        }
    })

    # --- Événement de changement de sélection dans la liste ---
    $Global:AppControls.scriptsListBox.Add_SelectionChanged({
        $selectedScript = $Global:AppControls.scriptsListBox.SelectedItem
        if ($selectedScript) {
            $Global:AppControls.defaultDetailText.Visibility = 'Collapsed'
            $Global:AppControls.scriptDetailPanel.Visibility = 'Visible'
            $Global:AppControls.descriptionTextBlock.Text = $selectedScript.description
            $Global:AppControls.versionTextBlock.Text = "Version : $($selectedScript.version)"
            
            if ($selectedScript.IsRunning) {
                $Global:AppControls.executeButton.Content = Get-AppText -Key 'launcher.stop_button'
                $Global:AppControls.executeButton.Style = $Global:AppControls.executeButton.FindResource('RedButtonStyle')
            } else {
                $Global:AppControls.executeButton.Content = Get-AppText -Key 'launcher.execute_button'
                $Global:AppControls.executeButton.Style = $Global:AppControls.executeButton.FindResource('PrimaryButtonStyle')
            }
            $Global:AppControls.executeButton.IsEnabled = $true
        } else {
            $Global:AppControls.defaultDetailText.Visibility = 'Visible'
            $Global:AppControls.scriptDetailPanel.Visibility = 'Collapsed'
            $Global:AppControls.executeButton.Content = Get-AppText -Key 'launcher.execute_button'
            $Global:AppControls.executeButton.Style = $Global:AppControls.executeButton.FindResource('PrimaryButtonStyle')
            $Global:AppControls.executeButton.IsEnabled = $false
        }
    })

    # --- Événement de double-clic sur la liste ---
    $Global:AppControls.scriptsListBox.Add_MouseDoubleClick({
        Start-AppScript -SelectedScript ($Global:AppControls.scriptsListBox.SelectedItem) -ProjectRoot $ProjectRoot
    })

    # --- Événement du bouton de sauvegarde des paramètres ---
    $Global:AppControls.settingsSaveButton.Add_Click({
        try {
            Set-AppSetting -Key 'app.companyName' -Value $Global:AppControls.settingsCompanyNameTextBox.Text
            Set-AppSetting -Key 'app.defaultLanguage' -Value $Global:AppControls.settingsLanguageComboBox.SelectedItem
            Set-AppSetting -Key 'app.enableVerboseLogging' -Value $Global:AppControls.settingsVerboseLoggingCheckBox.IsChecked
            
            # Conversion de type sécurisée
            $width = 0; [int]::TryParse($Global:AppControls.settingsLauncherWidthTextBox.Text, [ref]$width) | Out-Null
            $height = 0; [int]::TryParse($Global:AppControls.settingsLauncherHeightTextBox.Text, [ref]$height) | Out-Null
            Set-AppSetting -Key 'ui.launcherWidth' -Value $width
            Set-AppSetting -Key 'ui.launcherHeight' -Value $height

            # Si l'utilisateur est admin, on sauvegarde aussi les paramètres Azure
            if ($Global:IsAppAdmin) {
                # --- AJOUTER/MODIFIER CES LIGNES ---
                Set-AppSetting -Key 'azure.tenantId' -Value $Global:AppControls.settingsTenantIdTextBox.Text
                
                # Partie Authentification Utilisateur
                Set-AppSetting -Key 'azure.auth.user.appId' -Value $Global:AppControls.settingsUserAuthAppIdTextBox.Text
                $scopesToSave = ($Global:AppControls.settingsUserAuthScopesTextBox.Text -split ',').Trim() -join ','
                Set-AppSetting -Key 'azure.auth.user.scopes' -Value $scopesToSave

                # Partie Authentification Certificat
                Set-AppSetting -Key 'azure.auth.cert.appId' -Value $Global:AppControls.settingsCertAuthAppIdTextBox.Text

                $thumbprintValue = $Global:AppControls.settingsCertAuthThumbprintTextBox.Text.ToUpper() -replace '\s',''
                Set-AppSetting -Key 'azure.auth.cert.thumbprint' -Value $thumbprintValue

                # --- AJOUTER LA SAUVEGARDE DU GROUPE ADMIN ---
                Set-AppSetting -Key 'security.adminGroupName' -Value $Global:AppControls.settingsAdminGroupTextBox.Text
                Set-AppSetting -Key 'security.startupAuthMode' -Value $Global:AppControls.settingsStartupAuthModeComboBox.SelectedItem
            }

            # On met à jour la configuration en mémoire pour une prise en compte immédiate
            $Global:AppConfig = Get-AppConfiguration

            # On met à jour les éléments de l'UI qui dépendent de la configuration
            $Global:AppControls.mainWindow.Title = "$($Global:AppConfig.companyName) - $(Get-AppText 'app.title')"
            $Global:AppControls.mainWindow.Width = $Global:AppConfig.ui.launcherWidth
            $Global:AppControls.mainWindow.Height = $Global:AppConfig.ui.launcherHeight
            $VerbosePreference = if ($Global:AppConfig.enableVerboseLogging) { "Continue" } else { "SilentlyContinue" }

            Write-LauncherLog -Message (Get-AppText 'messages.settings_saved_log') -Level Success

            $successMsg = Get-AppText -Key 'messages.settings_saved_success'
            [System.Windows.MessageBox]::Show($successMsg, (Get-AppText 'confirmation.title'), "OK", "Information")
        
        } catch {
            $errorMsg = Get-AppText -Key 'messages.settings_saved_error'
            [System.Windows.MessageBox]::Show("$errorMsg :`n$($_.Exception.Message)", (Get-AppText 'confirmation.title'), "OK", "Error")
        }
    })

    # --- Événement du bouton "Fermer tout" ---
    $Global:AppControls.globalCloseAppsButton.Add_Click({
        $title = Get-AppText -Key 'confirmation.title'
        $message = Get-AppText -Key 'confirmation.close_all_apps'
        $buttons = [System.Windows.MessageBoxButton]::YesNo
        $icon = [System.Windows.MessageBoxImage]::Warning
        $result = [System.Windows.MessageBox]::Show($message, $title, $buttons, $icon)
        if ($result -ne [System.Windows.MessageBoxResult]::Yes) { return }

        $scriptsToClose = @($Global:AppActiveScripts)
        Write-Verbose "Demande de fermeture de $($scriptsToClose.Count) application(s)."

        foreach ($process in $scriptsToClose) {
            try {
                # --- AJOUT CRUCIAL ICI ---
                # 1. On stocke le PID avant de faire quoi que ce soit
                $pidToClean = $process.Id
                
                # 2. On arrête le processus de force
                Stop-Process -InputObject $process -Force
                Write-Verbose "Processus $pidToClean forcé de s'arrêter."

                # 3. Le lanceur prend la responsabilité de nettoyer le verrou correspondant.
                Unlock-AppScriptLock -OwnerPID $pidToClean
                # ------------------------

            } catch {
                Write-Warning "Impossible d'arrêter le processus $($process.Id)."
            }
        }
    })

    # --- Événement du macaron d'authentification ---
    $Global:AppControls.authStatusButton.Add_Click({
        # On stocke l'état de connexion AVANT toute action.
        $wasConnected = $Global:AppAzureAuth.UserAuth.Connected

        # On exécute la logique de connexion ou de déconnexion.
        if ($wasConnected) {
            Disconnect-AppAzureUser
            $Global:AppAzureAuth.UserAuth = @{ Connected = $false }

            $logMsg = "{0} '{1}'." -f (Get-AppText 'messages.user_disconnected_log'), $userUPN
            Write-LauncherLog -Message $logMsg -Level Info
        } else {
            $authResult = Connect-AppAzureWithUser -Scopes $Global:AppConfig.azure.authentication.userAuth.scopes
            if ($authResult.Success) {
                $Global:AppAzureAuth.UserAuth = $authResult

                $logMsg = "{0} '{1}'." -f (Get-AppText 'messages.user_connected_log'), $authResult.DisplayName
                Write-LauncherLog -Message $logMsg -Level Success
            } else {
                $Global:AppAzureAuth.UserAuth = @{ Connected = $false }
            }
        }
        
        # --- MISE À JOUR CENTRALISÉE DE L'UI ---
        
        # 1. On détermine le statut admin en se basant sur le NOUVEL état de connexion.
        $isAdmin = Test-IsAppAdmin

        # 2. On met à jour l'apparence du macaron lui-même.
        Update-LauncherAuthButton -AuthButton $Global:AppControls.authStatusButton
        
        # 3. On met à jour la visibilité de tous les panneaux admin.
        # On met à jour la visibilité de l'onglet "Paramètres"
        if ($isAdmin) { 
            $Global:AppControls.settingsTabItem.Visibility = 'Visible' 
        } else { 
            $Global:AppControls.settingsTabItem.Visibility = 'Collapsed' 
            $Global:AppControls.ScriptsTabItem.IsSelected = 'Enabled'
        }
        
        # 4. On met à jour l'état du bouton de nettoyage des verrous.
        $Global:AppControls.clearLocksButton.IsEnabled = $isAdmin

        # 5. Si l'état de connexion a réellement changé, on rafraîchit la liste des scripts.
        if ($wasConnected -ne $Global:AppAzureAuth.UserAuth.Connected) {
            $Global:AppAvailableScripts = Get-FilteredAndEnrichedScripts -ProjectRoot $ProjectRoot
            Update-ScriptListBoxUI -scripts $Global:AppAvailableScripts

            $logMsg = "{0} {1} {2}" -f (Get-AppText 'messages.script_list_refreshed_1'), $Global:AppAvailableScripts.Count, (Get-AppText 'messages.script_list_refreshed_2')
            Write-LauncherLog -Message $logMsg -Level Info
        }
    })

    # --- Événement du bouton de nettoyage des verrous ---
    $Global:AppControls.clearLocksButton.Add_Click({
        $title = Get-AppText -Key 'confirmation.clear_locks_title'
        $message = Get-AppText -Key 'confirmation.clear_locks_message'
        if ([System.Windows.MessageBox]::Show($message, $title, 'YesNo', 'Warning') -ne 'Yes') { return }

        if (Clear-AppScriptLock) {
            Write-LauncherLog -Message (Get-AppText 'messages.clear_locks_success_log') -Level Warning
            [System.Windows.MessageBox]::Show((Get-AppText 'messages.clear_locks_success_ui'), (Get-AppText 'confirmation.title'), "OK", "Information")
        } else {
            [System.Windows.MessageBox]::Show((Get-AppText 'messages.clear_locks_error_ui'), (Get-AppText 'confirmation.title'), "OK", "Error")
        }
    })

    # ---  GESTION DE L'ACCORDÉON DES PARAMÈTRES ---
    try {
        # 1. On crée la liste de tous les expanders concernés.
        $settingsExpanders = @(
            $Global:AppControls.generalSettingsCard,
            $Global:AppControls.uiSettingsCard,
            $Global:AppControls.azureSettingsCard,
            $Global:AppControls.securitySettingsCard
        ) | Where-Object { $null -ne $_ }

        # 2. On définit le bloc de logique et on le transforme immédiatement en closure
        #    pour qu'il "capture" la variable $settingsExpanders.
        $accordionLogic = {
            param($sender)

            foreach ($expander in $settingsExpanders) {
                if ($expander -ne $sender) {
                    $expander.IsExpanded = $false
                }
            }
        }.GetNewClosure()

        # 3. On attache notre logique à l'événement "Expanded" de chaque expander.
        foreach ($expander in $settingsExpanders) {
            # On crée une closure pour le gestionnaire d'événement lui-même,
            # afin qu'il "capture" la closure $accordionLogic.
            $eventHandler = {
                & $accordionLogic -sender $this
            }.GetNewClosure()

            $expander.Add_Expanded($eventHandler)
        }
    } catch {
        Write-Warning "Erreur lors de l'initialisation de la logique d'accordéon des paramètres : $($_.Exception.Message)"
    }
}