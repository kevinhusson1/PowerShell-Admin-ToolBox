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

    # --- Fonction pour mettre à jour l'état des boutons de test Azure ---
    $updateAzureTestButtonsState = {
        if ($Global:AppControls.ContainsKey('SettingsUserAuthTestButton') -and $Global:AppControls.SettingsUserAuthTestButton) {
            $Global:AppControls.SettingsUserAuthTestButton.IsEnabled = $Global:AppAzureAuth.UserAuth.Connected
        }
    }.GetNewClosure()

    # --- Événement du bouton Mettre au premier plan ---
    $Global:AppControls.bringToFrontButton.Add_Click({
            $selectedScriptOnClick = $Global:AppControls.scriptsListBox.SelectedItem
            if (-not ($selectedScriptOnClick -and $selectedScriptOnClick.IsRunning)) { return }

            try {
                $process = Get-Process -Id $selectedScriptOnClick.pid -ErrorAction Stop
                $mainWindowHandle = $process.MainWindowHandle

                if ($mainWindowHandle -ne [System.IntPtr]::Zero) {
                    # Étape 1 : Si la fenêtre est minimisée, on la restaure
                    if ([App.WindowUtils]::IsIconic($mainWindowHandle)) {
                        [App.WindowUtils]::ShowWindow($mainWindowHandle, $showWindowAsyncConstants.SW_RESTORE) | Out-Null
                    }
                    # Étape 2 : On la met au premier plan
                    [App.WindowUtils]::SetForegroundWindow($mainWindowHandle) | Out-Null
                }
                else {
                    $message = (Get-AppText -Key 'bringToFrontButtonFail1') + " '$($selectedScriptOnClick.name)' " + (Get-AppText -Key 'bringToFrontButtonFail2')
                    Write-LauncherLog -Message $message -Level Warning
                }
            }
            catch {
                $message = (Get-AppText -Key 'bringToFrontButtonError') + " '$($selectedScriptOnClick.name)'."
                Write-LauncherLog -Message $message -Level Error
            }
        })

    # --- Événement du bouton Exécuter/Arrêter ---
    $Global:AppControls.executeButton.Add_Click({
            $selectedScript = $Global:AppControls.scriptsListBox.SelectedItem
            if (-not $selectedScript) { return }

            if ($selectedScript.IsRunning) {
                Stop-AppScript -SelectedScript $selectedScript
            }
            else {
                Start-AppScript -SelectedScript $selectedScript -ProjectRoot $ProjectRoot
            }
        })

    # --- Événement de changement de sélection dans la liste ---
    $Global:AppControls.scriptsListBox.Add_SelectionChanged({
            $selectedScript = $Global:AppControls.scriptsListBox.SelectedItem
            if ($selectedScript) {
                $Global:AppControls.defaultDetailText.Visibility = 'Collapsed'
            
                if ($selectedScript.IsLoading) {
                    # Afficher le panneau de chargement
                    $Global:AppControls.scriptDetailPanel.Visibility = 'Collapsed'
                    $Global:AppControls.scriptLoadingPanel.Visibility = 'Visible'
                
                    # Mettre à jour les données du panneau de chargement
                    $Global:AppControls.loadingStatusText.Text = $selectedScript.LoadingStatus
                    $Global:AppControls.loadingProgressBar.Value = $selectedScript.LoadingProgress
                    $Global:AppControls.loadingProgressText.Text = "$($selectedScript.LoadingProgress)%"
                }
                else {
                    # Afficher le panneau de détails standard
                    $Global:AppControls.scriptLoadingPanel.Visibility = 'Collapsed'
                    $Global:AppControls.scriptDetailPanel.Visibility = 'Visible'
                
                    # Mettre à jour les données du panneau standard
                    $Global:AppControls.descriptionTextBlock.Text = $selectedScript.description
                    $Global:AppControls.versionTextBlock.Text = "Version : $($selectedScript.version)"
                }

                if ($selectedScript.IsRunning) {
                    $Global:AppControls.executeButton.Content = Get-AppText -Key 'launcher.stop_button'
                    $Global:AppControls.executeButton.Style = $Global:AppControls.executeButton.FindResource('RedButtonStyle')
                    $Global:AppControls.bringToFrontButton.Visibility = 'Visible'
                }
                else {
                    $Global:AppControls.executeButton.Content = Get-AppText -Key 'launcher.execute_button'
                    $Global:AppControls.executeButton.Style = $Global:AppControls.executeButton.FindResource('PrimaryButtonStyle')
                    $Global:AppControls.bringToFrontButton.Visibility = 'Collapsed'
                }
                $Global:AppControls.executeButton.IsEnabled = $true
            }
            else {
                $Global:AppControls.defaultDetailText.Visibility = 'Visible'
                $Global:AppControls.scriptDetailPanel.Visibility = 'Collapsed'
                $Global:AppControls.executeButton.Content = Get-AppText -Key 'launcher.execute_button'
                $Global:AppControls.executeButton.Style = $Global:AppControls.executeButton.FindResource('PrimaryButtonStyle')
                $Global:AppControls.executeButton.IsEnabled = $false
                $Global:AppControls.bringToFrontButton.Visibility = 'Collapsed'
            }
        })

    # --- Événement de double-clic sur la liste ---
    $Global:AppControls.scriptsListBox.Add_MouseDoubleClick({
            Start-AppScript -SelectedScript ($Global:AppControls.scriptsListBox.SelectedItem) -ProjectRoot $ProjectRoot
        })

    # --- Événement du bouton de sauvegarde des paramètres ---
    if ($Global:AppControls.settingsSaveButton) {
        $Global:AppControls.settingsSaveButton.Add_Click({
                try {
                    # 1. Paramètres Généraux
                    Set-AppSetting -Key 'app.companyName' -Value $Global:AppControls.settingsCompanyNameTextBox.Text
                    Set-AppSetting -Key 'app.defaultLanguage' -Value $Global:AppControls.settingsLanguageComboBox.SelectedItem
                    Set-AppSetting -Key 'app.enableVerboseLogging' -Value $Global:AppControls.settingsVerboseLoggingCheckBox.IsChecked
                
                    # 2. Paramètres Interface (UI)
                    # Conversion de type sécurisée
                    $width = 0; [int]::TryParse($Global:AppControls.settingsLauncherWidthTextBox.Text, [ref]$width) | Out-Null
                    $height = 0; [int]::TryParse($Global:AppControls.settingsLauncherHeightTextBox.Text, [ref]$height) | Out-Null
                    Set-AppSetting -Key 'ui.launcherWidth' -Value $width
                    Set-AppSetting -Key 'ui.launcherHeight' -Value $height

                    # 3. Paramètres Administrateur (Azure, Sécurité, AD)
                    if ($Global:IsAppAdmin) {
                    
                        # --- AZURE ---
                        Set-AppSetting -Key 'azure.tenantName' -Value $Global:AppControls.settingsTenantNameTextBox.Text
                        Set-AppSetting -Key 'azure.tenantId' -Value $Global:AppControls.settingsTenantIdTextBox.Text
                        Set-AppSetting -Key 'azure.auth.user.appId' -Value $Global:AppControls.settingsUserAuthAppIdTextBox.Text

                        # Authentification Utilisateur
                        $scopesToSave = ($Global:AppControls.settingsUserAuthScopesTextBox.Text -split ',').Trim() -join ','
                        Set-AppSetting -Key 'azure.auth.user.scopes' -Value $scopesToSave
                        Set-AppSetting -Key 'security.adminGroupName' -Value $Global:AppControls.settingsAdminGroupTextBox.Text

                        # --- CERTIFICAT ---
                        Set-AppSetting -Key 'azure.cert.thumbprint' -Value $Global:AppControls.SettingsCertThumbprintTextBox.Text
                    
                        # --- ACTIVE DIRECTORY ---
                        Set-AppSetting -Key 'ad.serviceUser' -Value $Global:AppControls.settingsADServiceUserTextBox.Text
                    
                        # Chiffrement et sauvegarde du mot de passe
                        if ($Global:ADPasswordManuallyChanged) {
                            $securePassword = $Global:AppControls.settingsADServicePasswordBox.SecurePassword
                            if ($securePassword.Length -eq 0) {
                                Set-AppSetting -Key 'ad.servicePassword' -Value ""
                            }
                            else {
                                $ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
                                try {
                                    $unmanagedString = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
                                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($unmanagedString)
                                    $encryptedBytes = [System.Security.Cryptography.ProtectedData]::Protect($bytes, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
                                    $encryptedString = [System.Convert]::ToBase64String($encryptedBytes)
                                    Set-AppSetting -Key 'ad.servicePassword' -Value $encryptedString
                                }
                                finally {
                                    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
                                }
                            }
                        }
                    
                        Set-AppSetting -Key 'ad.tempServer' -Value $Global:AppControls.settingsADTempServerTextBox.Text
                        Set-AppSetting -Key 'ad.connectServer' -Value $Global:AppControls.settingsADConnectServerTextBox.Text
                        Set-AppSetting -Key 'ad.domainName' -Value $Global:AppControls.settingsADDomainNameTextBox.Text
                        Set-AppSetting -Key 'ad.userOUPath' -Value $Global:AppControls.settingsADUserOUPathTextBox.Text
                        Set-AppSetting -Key 'ad.pdcName' -Value $Global:AppControls.settingsADPDCNameTextBox.Text
                        Set-AppSetting -Key 'ad.domainUserGroup' -Value $Global:AppControls.settingsADDomainUserGroupTextBox.Text
                        $excludedGroupsToSave = ($Global:AppControls.settingsADExcludedGroupsTextBox.Text -split ',').Trim() -join ','
                        Set-AppSetting -Key 'ad.excludedGroups' -Value $excludedGroupsToSave
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
            
                }
                catch {
                    $errorMsg = Get-AppText -Key 'messages.settings_saved_error'
                    [System.Windows.MessageBox]::Show("$errorMsg :`n$($_.Exception.Message)", (Get-AppText 'confirmation.title'), "OK", "Error")
                }
            }.GetNewClosure())
    }

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

                }
                catch {
                    Write-Warning "Impossible d'arrêter le processus $($process.Id)."
                }
            }
        })

    # --- LOGIQUE D'AUTHENTIFICATION CENTRALISÉE (Closure) ---
    $authLogic = {
        # On stocke l'état de connexion AVANT toute action.
        $wasConnected = $Global:AppAzureAuth.UserAuth.Connected

        # 1. LOGIQUE DE DÉCONNEXION
        if ($wasConnected) {
            $confirm = [System.Windows.MessageBox]::Show(
                (Get-AppText 'modules.launcherui.dialog_logout_message'), # Message
                (Get-AppText 'modules.launcherui.dialog_logout_title'),   # Titre
                [System.Windows.MessageBoxButton]::YesNo, 
                [System.Windows.MessageBoxImage]::Question
            )
            if ($confirm -ne [System.Windows.MessageBoxResult]::Yes) { return }

            # CORRECTION LOG : On sauvegarde le nom AVANT de déconnecter
            $userDisplayName = $Global:AppAzureAuth.UserAuth.DisplayName

            Disconnect-AppAzureUser
            $Global:AppAzureAuth.UserAuth = @{ Connected = $false }
            $Global:CurrentUserGroups = $null # <--- VIDAGE DU CACHE

            # --- CORRECTION : Nettoyage de l'interface ---
            $Global:AppAvailableScripts = @()  # On vide la variable globale
            Update-ScriptListBoxUI -scripts @() # On vide la liste visuelle

            # On cache les panneaux de détails
            $Global:AppControls.DetailsPanelBorder.Visibility = 'Collapsed'
            $Global:AppControls.StatusBarBorder.Visibility = 'Collapsed'

            # Utilisation du nom sauvegardé
            $logMsg = "{0} '{1}'." -f (Get-AppText 'messages.user_disconnected_log'), $userDisplayName
            Write-LauncherLog -Message $logMsg -Level Info
        } 
        # 2. LOGIQUE DE CONNEXION
        else {
            $Global:AppControls.mainWindow.Cursor = [System.Windows.Input.Cursors]::Wait
            try {
                $authResult = Connect-AppAzureWithUser `
                    -AppId $Global:AppConfig.azure.authentication.userAuth.appId `
                    -TenantId $Global:AppConfig.azure.tenantId `
                    -Scopes $Global:AppConfig.azure.authentication.userAuth.scopes
                
                if ($authResult.Success) {
                    $Global:AppAzureAuth.UserAuth = $authResult
                    
                    # --- CACHE CRITIQUE : On récupère les groupes ICI et une seule fois ---
                    Write-LauncherLog -Message "Récupération des droits..." -Level Info
                    $Global:CurrentUserGroups = Get-AppUserAzureGroups
                    # -------------------------------------------------------------------

                    Write-LauncherLog -Message "{0} '{1}'." -f (Get-AppText 'messages.user_connected_log'), $authResult.DisplayName -Level Success
                }
                else {
                    $Global:AppAzureAuth.UserAuth = @{ Connected = $false }
                }
            }
            finally {
                $Global:AppControls.mainWindow.Cursor = [System.Windows.Input.Cursors]::Arrow
            }
        }
        
        # 3. MISE À JOUR UI
        [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([Action] {}, [System.Windows.Threading.DispatcherPriority]::Background)

        # ... (Bloc redimensionnement fenêtre inchangé) ...
        $isAdmin = Test-IsAppAdmin
        $Global:IsAppAdmin = $isAdmin
        
        if ($isAdmin) {
            $Global:AppControls.mainWindow.Width = $Global:AppConfig.ui.launcherWidth
            $Global:AppControls.mainWindow.Height = $Global:AppConfig.ui.launcherHeight
        }
        else {
            $Global:AppControls.mainWindow.Width = 560
            $Global:AppControls.mainWindow.Height = 750
        }
        # ...

        if ($Global:AppAzureAuth.UserAuth.Connected) {
            # ... (Visibilité panneaux inchangée) ...
            $Global:AppControls.ConnectPromptPanel.Visibility = 'Collapsed'
            $Global:AppControls.ScriptsListBox.Visibility = 'Visible'
            $Global:AppControls.DetailsPanelBorder.Visibility = 'Visible'
            $Global:AppControls.StatusBarBorder.Visibility = 'Visible'
            
            Write-LauncherLog -Message "Chargement des scripts et de la configuration..." -Level Info
            
            if ($Global:uiTimer.IsEnabled) { $Global:uiTimer.Stop() }

            try {
                # === CORRECTION : On passe les groupes explicitement ===
                $groupsToPass = if ($Global:CurrentUserGroups) { $Global:CurrentUserGroups } else { @() }
                
                $Global:AppAvailableScripts = Get-FilteredAndEnrichedScripts `
                    -ProjectRoot $ProjectRoot `
                    -UserGroups $groupsToPass  # <--- PASSAGE PAR PARAMÈTRE
                # ======================================================
            }
            finally {
                $Global:uiTimer.Start()
            }
            
            Update-ScriptListBoxUI -scripts $Global:AppAvailableScripts
        }
        else {
            # ... (Cas déconnecté inchangé) ...
            $Global:AppControls.ConnectPromptPanel.Visibility = 'Visible'
            $Global:AppControls.ScriptsListBox.Visibility = 'Collapsed'
            $Global:AppControls.DetailsPanelBorder.Visibility = 'Collapsed'
            $Global:AppControls.StatusBarBorder.Visibility = 'Collapsed'
            Update-ScriptListBoxUI -scripts @()
        }

        # C. Onglets & Bouton Auth
        Update-LauncherAuthButton -AuthButton $Global:AppControls.authStatusButton
        
        if ($isAdmin) { 
            $Global:AppControls.settingsTabItem.Visibility = 'Visible' 
            $Global:AppControls.GovernanceTabItem.Visibility = 'Visible'
            $Global:AppControls.ManagementTabItem.Visibility = 'Visible' # <--- NOUVEAU
            Initialize-LauncherData 
        }
        else { 
            $Global:AppControls.settingsTabItem.Visibility = 'Collapsed' 
            $Global:AppControls.GovernanceTabItem.Visibility = 'Collapsed'
            $Global:AppControls.ManagementTabItem.Visibility = 'Collapsed' # <--- NOUVEAU
            $Global:AppControls.ScriptsTabItem.IsSelected = $true
        }
        
        $Global:AppControls.clearLocksButton.IsEnabled = $isAdmin
        & $updateAzureTestButtonsState

    }.GetNewClosure()

    # --- ATTACHEMENT DES ÉVÉNEMENTS ---
    # Le bouton macaron ET le bouton texte déclenchent la même logique
    $Global:AppControls.authStatusButton.Add_Click($authLogic)
    
    if ($Global:AppControls.AuthTextButton) {
        $Global:AppControls.AuthTextButton.Add_Click($authLogic)
    }

    # --- Événement du bouton de nettoyage des verrous ---
    $Global:AppControls.clearLocksButton.Add_Click({
            $title = Get-AppText -Key 'confirmation.clear_locks_title'
            $message = Get-AppText -Key 'confirmation.clear_locks_message'
            if ([System.Windows.MessageBox]::Show($message, $title, 'YesNo', 'Warning') -ne 'Yes') { return }

            if (Clear-AppScriptLock) {
                Write-LauncherLog -Message (Get-AppText 'messages.clear_locks_success_log') -Level Warning
                [System.Windows.MessageBox]::Show((Get-AppText 'messages.clear_locks_success_ui'), (Get-AppText 'confirmation.title'), "OK", "Information")
            }
            else {
                [System.Windows.MessageBox]::Show((Get-AppText 'messages.clear_locks_error_ui'), (Get-AppText 'confirmation.title'), "OK", "Error")
            }
        })
    
    # --- CONFIGURATION CENTRALE DES TIMERS ---
    # On définit ici le comportement de nos timers globaux.

    # 1. Comportement du Timer Lent (sécurité et nettoyage)
    $Global:uiTimer.Interval = [TimeSpan]::FromSeconds(2)
    try { $Global:uiTimer.remove_Tick($Global:uiTimerTickHandler) } catch {}
    $Global:uiTimerTickHandler = {
        if (-not $Global:AppControls.ContainsKey('scriptsListBox')) { return }

        # --- 1. GESTION DES PROCESSUS (Nettoyage) ---
        $scriptsToRemove = @($Global:AppActiveScripts | Where-Object { $_.HasExited })
        if ($scriptsToRemove.Count -gt 0) {
            foreach ($process in $scriptsToRemove) {
                $finishedScript = $Global:AppAvailableScripts | Where-Object { $_.pid -eq $process.Id }
                if ($finishedScript) {
                    $message = (Get-AppText 'messages.timerPIDclose1') + "'" + $($finishedScript.name) + "'" + "(PID: " + $($finishedScript.pid) + ")" + (Get-AppText 'messages.timerPIDclose2')
                    Write-LauncherLog -Message $message -Level Info
                    $finishedScript.IsRunning = $false
                    $finishedScript.IsLoading = $false
                    $finishedScript.pid = $null
                    
                    # Mise à jour bouton
                    if ($Global:AppControls.scriptsListBox.SelectedItem -eq $finishedScript) {
                        $Global:AppControls.executeButton.Content = Get-AppText -Key 'launcher.execute_button'
                        $Global:AppControls.executeButton.Style = $Global:AppControls.executeButton.FindResource('PrimaryButtonStyle')
                        $Global:AppControls.bringToFrontButton.Visibility = 'Collapsed'
                    }
                }
                $Global:AppActiveScripts.Remove($process)
                if ($Global:PIDsToMonitor.Contains($process.Id)) { $Global:PIDsToMonitor.Remove($process.Id) }
                Unlock-AppScriptLock -OwnerPID $process.Id
                Remove-AppScriptProgress -OwnerPID $process.Id
            }
            $Global:AppControls.scriptsListBox.Items.Refresh()
        }

        # --- 2. MISE À JOUR UI GLOBALE ---
        $Global:AppControls.globalCloseAppsButton.Visibility = if ($Global:AppActiveScripts.Count -gt 0) { 'Visible' } else { 'Collapsed' }
        
        # --- 3. CALCUL DES COMPTEURS (MÉTHODE ROBUSTE) ---
        $activeScriptsCount = $Global:AppActiveScripts.Count
        
        # On compte manuellement pour éviter les ambiguïtés de type dans le Timer
        $visibleCount = 0
        if ($Global:AppAvailableScripts) {
            foreach ($s in $Global:AppAvailableScripts) {
                # On force la conversion en booléen pour être sûr (1 = true, 0 = false)
                if ([bool]$s.enabled) {
                    $visibleCount++
                }
            }
        }

        $statusText = "$(Get-AppText 'launcher.status_available') : $visibleCount  •  $(Get-AppText 'launcher.status_active') : $activeScriptsCount"
        
        # On met à jour le texte seulement s'il a changé pour éviter de faire scintiller l'UI inutilement
        if ($Global:AppControls.statusTextBlock.Text -ne $statusText) {
            $Global:AppControls.statusTextBlock.Text = $statusText
        }
    }
    $Global:uiTimer.Add_Tick($Global:uiTimerTickHandler)

    # 2. Comportement du Timer Rapide (progression)
    $Global:progressTimer.Interval = [TimeSpan]::FromMilliseconds(200)
    try { $Global:progressTimer.remove_Tick($Global:progressTimerTickHandler) } catch {}
    $Global:progressTimerTickHandler = {
        # Condition d'arrêt : si la liste de surveillance est vide, on s'arrête.
        if ($Global:PIDsToMonitor.Count -eq 0) {
            $Global:progressTimer.Stop()
            Write-Verbose $(Get-AppText 'messages.timerProgressStop')
            
            # Nettoyage final de l'UI au cas où un script serait resté "bloqué" visuellement
            $scriptsToFinalize = $Global:AppAvailableScripts | Where-Object { $_.IsLoading }
            if ($scriptsToFinalize) {
                foreach ($script in $scriptsToFinalize) {
                    $script.IsLoading = $false
                }
            }
            $Global:AppControls.scriptsListBox.Items.Refresh()
            return
        }

        $progressUpdates = Get-AppScriptProgress
        if (-not $progressUpdates) { return } # S'il n'y a pas encore de mise à jour dans la DB, on attend le prochain tick

        $pidsToFinalize = [System.Collections.Generic.List[int]]::new()
        foreach ($update in $progressUpdates) {
            $scriptInProgress = $Global:AppAvailableScripts | Where-Object { $_.pid -eq $update.OwnerPID }
            if ($scriptInProgress) {
                if (-not $scriptInProgress.IsLoading) {
                    $scriptInProgress.IsLoading = $true
                    $needsRefresh = $true
                }

                $scriptInProgress.LoadingProgress = $update.ProgressPercentage
                $scriptInProgress.LoadingStatus = $update.StatusMessage
                $needsRefresh = $true

                if ($Global:AppControls.scriptsListBox.SelectedItem -eq $scriptInProgress) {
                    $Global:AppControls.loadingProgressBar.Value = $scriptInProgress.LoadingProgress
                    $Global:AppControls.loadingProgressText.Text = "$($scriptInProgress.LoadingProgress)%"
                    $Global:AppControls.loadingStatusText.Text = $scriptInProgress.LoadingStatus
                }
            
                if ($update.ProgressPercentage -ge 100) {
                    $pidsToFinalize.Add($update.OwnerPID)
                }
            }
        }

        if ($needsRefresh) {
            $Global:AppControls.scriptsListBox.Items.Refresh()
        }
        
        if ($pidsToFinalize.Count -gt 0) {
            foreach ($pidSelect in $pidsToFinalize) {
                $scriptFinishedLoading = $Global:AppAvailableScripts | Where-Object { $_.pid -eq $pidSelect }
                if ($scriptFinishedLoading) {
                    $scriptFinishedLoading.IsLoading = $false
                    if ($Global:AppControls.scriptsListBox.SelectedItem -eq $scriptFinishedLoading) {
                        $Global:AppControls.scriptLoadingPanel.Visibility = 'Collapsed'
                        $Global:AppControls.scriptDetailPanel.Visibility = 'Visible'
                    }
                }
                Remove-AppScriptProgress -OwnerPID $pidSelect
                
                # On retire le PID de la liste de surveillance
                if ($Global:PIDsToMonitor.Contains($pidSelect)) {
                    $Global:PIDsToMonitor.Remove($pidSelect)
                }
            }
        }
        
        $Global:AppControls.scriptsListBox.Items.Refresh()
    }
    $Global:progressTimer.Add_Tick($Global:progressTimerTickHandler)

    # ---  GESTION DE L'ACCORDÉON DES PARAMÈTRES ---
    try {
        # 1. On crée la liste de tous les expanders concernés.
        $settingsExpanders = @(
            $Global:AppControls.generalSettingsCard,
            $Global:AppControls.azureSettingsCard,
            $Global:AppControls.activeDirectorySettingsCard
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
    }
    catch {
        Write-Warning "Erreur lors de l'initialisation de la logique d'accordéon des paramètres : $($_.Exception.Message)"
    }

    # --- NOUVEAU : Événement pour détecter le changement du mot de passe ---
    $Global:AppControls.settingsADServicePasswordBox.Add_GotFocus({
            # Si le mot de passe a déjà été changé manuellement, on ne fait rien.
            # Cela permet à l'utilisateur de cliquer à nouveau dans le champ sans l'effacer.
            if ($Global:ADPasswordManuallyChanged) { return }

            # On lève le drapeau pour indiquer une intention de modification.
            $Global:ADPasswordManuallyChanged = $true

            # On vide le champ pour que l'utilisateur puisse taper un nouveau mot de passe.
            $this.Clear()

        }.GetNewClosure())

    # --- Fonction d'aide pour le test d'authentification AD ---
    # ===============================================================
    # ÉVÉNEMENT DU BOUTON DE TEST - VERSION FINALE ET COMPLÈTE
    # ===============================================================
    $Global:AppControls.settingsTestADCredsButton.Add_Click({
        
            # ===================================================================
            # SECTION 1 : Initialisation et Préparation
            # ===================================================================
        
            $controls = @{
                User   = $Global:AppControls.settingsADServiceUserTextBox
                Pass   = $Global:AppControls.settingsADServicePasswordBox
                Domain = $Global:AppControls.settingsADDomainNameTextBox
                PDC    = $Global:AppControls.settingsADPDCNameTextBox
                Button = $Global:AppControls.settingsTestADCredsButton
            }
            $originalButtonText = $controls.Button.Content
        
            try {
                # Mettre l'interface en état de "test en cours"
                $controls.Button.IsEnabled = $false
                $controls.Button.Content = (Get-AppText -Key 'settings.test_button_inprogress')
                $controls.Values | ForEach-Object { if ($_.GetType().Name -ne 'Button') { $_.Tag = $null } }
                Write-LauncherLog -Message (Get-AppText -Key 'settings_validation.auth_start') -Level Info

                # ===================================================================
                # SECTION 2 : Appel à la logique métier (Module)
                # ===================================================================
            
                # Étape 2.1 : Obtenir les credentials (peut lever une exception si les champs sont vides)
                $securePassword = Get-ADServiceCredential -UsernameControl $controls.User -PasswordControl $controls.Pass -DomainControl $controls.Domain
            
                # Étape 2.2 : Lancer la validation séquentielle
                $testResult = Test-ADConnection -Server $controls.PDC.Text -Domain $controls.Domain.Text -Username $controls.User.Text -SecurePassword $securePassword

                # ===================================================================
                # SECTION 3 : Interprétation du Résultat
                # ===================================================================

                if ($testResult.Success) {
                    # C'est un succès complet
                    Write-LauncherLog -Message $testResult.Message -Level Success
                    # Mettre tous les champs en vert
                    $controls.Values | ForEach-Object { if ($_.GetType().Name -ne 'Button') { $_.Tag = 'Success' } }
                    [System.Windows.MessageBox]::Show($testResult.Message, (Get-AppText -Key 'settings_validation.auth_success_box_title'), "OK", "Information")
            
                }
                else {
                    # C'est un échec contrôlé par le module (ex: Ping échoué, mauvais mot de passe)
                    Write-LauncherLog -Message $testResult.Message -Level Error
                    # Mettre le bon champ en rouge
                    switch ($testResult.Target) {
                        "PDC" { $controls.PDC.Tag = 'Error' }
                        "Domain" { $controls.Domain.Tag = 'Error' }
                        "UserPass" { $controls.User.Tag = 'Error'; $controls.Pass.Tag = 'Error' }
                    }
                    [System.Windows.MessageBox]::Show("Échec de la validation.`n`n$($testResult.Message)", (Get-AppText -Key 'settings_validation.auth_failure_box_title'), "OK", "Error")
                }

            }
            catch {
                # ===================================================================
                # SECTION 4 : GESTION DE TOUTES LES EXCEPTIONS
                # ===================================================================
                # Ce bloc attrape les erreurs de validation (champs vides) levées par Get-ADServiceCredential
                # ou toute autre erreur inattendue.
                $errorMessage = $_.Exception.Message
                Write-LauncherLog -Message "Erreur de validation : $errorMessage" -Level Error
                [System.Windows.MessageBox]::Show("Échec de la validation.`n`nErreur : $errorMessage", (Get-AppText -Key 'settings_validation.auth_failure_box_title'), "OK", "Error")
        
            }
            finally {
                # ===================================================================
                # SECTION 5 : Restauration de l'Interface
                # ===================================================================
                $controls.Button.IsEnabled = $true
                $controls.Button.Content = $originalButtonText
            }
        }.GetNewClosure())

    # ===============================================================
    # ÉVÉNEMENT DU BOUTON DE TEST D'INFRASTRUCTURE
    # ===============================================================
    $Global:AppControls.settingsTestInfraButton.Add_Click({
            # --- 1. Initialisation et Préparation ---
            $controls = @{
                ADConnect = $Global:AppControls.settingsADConnectServerTextBox
                Temp      = $Global:AppControls.settingsADTempServerTextBox
                Button    = $Global:AppControls.settingsTestInfraButton
                # On a besoin des champs d'authentification pour construire les credentials
                User      = $Global:AppControls.settingsADServiceUserTextBox
                Pass      = $Global:AppControls.settingsADServicePasswordBox
                Domain    = $Global:AppControls.settingsADDomainNameTextBox
            }
            $originalButtonText = $controls.Button.Content

            try {
                # Mettre l'interface en état de "test en cours"
                $controls.Button.IsEnabled = $false
                $controls.Button.Content = (Get-AppText -Key 'settings.test_button_inprogress')
                # On réinitialise les états de tous les champs concernés
                @($controls.ADConnect, $controls.Temp, $controls.User, $controls.Pass, $controls.Domain) | ForEach-Object { $_.Tag = $null }
                Write-LauncherLog -Message (Get-AppText -Key 'settings_validation.infra_test_start') -Level Info

                # --- 2. Appel à la logique métier ---

                # Étape 2.1 : Obtenir les credentials (peut lever une exception si les champs sont vides)
                $securePassword = Get-ADServiceCredential -UsernameControl $controls.User -PasswordControl $controls.Pass -DomainControl $controls.Domain
                $upn = if ($controls.User.Text -like "*@*") { $controls.User.Text } else { "$($controls.User.Text)@$($controls.Domain.Text)" }
                $credential = New-Object System.Management.Automation.PSCredential($upn, $securePassword)

                # Étape 2.2 : Lancer le test d'infrastructure avec les credentials
                $testResult = Test-ADInfrastructure -ADConnectServer $controls.ADConnect.Text -TempServer $controls.Temp.Text -Credential $credential

                # --- 3. Interprétation du Résultat ---
                if ($testResult.Success) {
                    Write-LauncherLog -Message $testResult.Message -Level Success
                    # On met les champs de l'infra en vert
                    @($controls.ADConnect, $controls.Temp) | ForEach-Object { $_.Tag = 'Success' }
                    [System.Windows.MessageBox]::Show($testResult.Message, (Get-AppText -Key 'settings_validation.infra_success_box_title'), "OK", "Information")
                }
                else {
                    Write-LauncherLog -Message $testResult.Message -Level Error
                    # CORRECTION : On met le bon champ en rouge
                    switch ($testResult.Target) {
                        "ADConnect" { $controls.ADConnect.Tag = 'Error' }
                        "TempServer" { $controls.Temp.Tag = 'Error' }
                    }
                    [System.Windows.MessageBox]::Show($testResult.Message, (Get-AppText -Key 'settings_validation.infra_failure_box_title'), "OK", "Error")
                }

            }
            catch {
                # --- 4. Gestion de TOUTES les Exceptions ---
                # (Attrape les erreurs de champs vides de Get-ADServiceCredential et les erreurs inattendues)
                $errorMessage = $_.Exception.Message
                Write-LauncherLog -Message "Erreur de validation : $errorMessage" -Level Error
                [System.Windows.MessageBox]::Show($errorMessage, (Get-AppText -Key 'settings_validation.infra_failure_box_title'), "OK", "Error")
        
            }
            finally {
                # --- 5. Restauration de l'Interface ---
                $controls.Button.IsEnabled = $true
                $controls.Button.Content = $originalButtonText
            }
        }.GetNewClosure())

    # ===============================================================
    # ÉVÉNEMENT DU BOUTON DE TEST DES OBJETS AD
    # ===============================================================
    $Global:AppControls.settingsTestADObjectsButton.Add_Click({
            # --- 1. Initialisation et Préparation ---
            $controls = @{
                OUPath          = $Global:AppControls.settingsADUserOUPathTextBox
                ExcludedGroups  = $Global:AppControls.settingsADExcludedGroupsTextBox
                DomainUserGroup = $Global:AppControls.settingsADDomainUserGroupTextBox
                Button          = $Global:AppControls.settingsTestADObjectsButton
                # Dépendances pour l'authentification
                User            = $Global:AppControls.settingsADServiceUserTextBox
                Pass            = $Global:AppControls.settingsADServicePasswordBox
                Domain          = $Global:AppControls.settingsADDomainNameTextBox
            }
            $originalButtonText = $controls.Button.Content

            try {
                # Mettre l'interface en état de "test en cours"
                $controls.Button.IsEnabled = $false
                $controls.Button.Content = (Get-AppText -Key 'settings.test_button_inprogress')
                @($controls.OUPath, $controls.ExcludedGroups, $controls.DomainUserGroup) | ForEach-Object { $_.Tag = $null }
            
                # CORRECTION : On force le thread UI à se mettre à jour AVANT la tâche longue
                [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([Action] {}, [System.Windows.Threading.DispatcherPriority]::Background)

                Write-LauncherLog -Message (Get-AppText -Key 'settings_validation.adobjects_test_start') -Level Info

                # --- 2. Appel à la logique métier (cette partie peut être longue) ---
                $securePassword = Get-ADServiceCredential -UsernameControl $controls.User -PasswordControl $controls.Pass -DomainControl $controls.Domain
                $upn = if ($controls.User.Text -like "*@*") { $controls.User.Text } else { "$($controls.User.Text)@$($controls.Domain.Text)" }
                $credential = New-Object System.Management.Automation.PSCredential($upn, $securePassword)

                $testResult = Test-ADDirectoryObjects -OUPath $controls.OUPath.Text -ExcludedGroups $controls.ExcludedGroups.Text -DomainUserGroupSamAccountName $controls.DomainUserGroup.Text -Credential $credential

                # --- 3. Interprétation du Résultat ---
                if ($testResult.Success) {
                    Write-LauncherLog -Message $testResult.Message -Level Success
                    @($controls.OUPath, $controls.ExcludedGroups, $controls.DomainUserGroup) | ForEach-Object { $_.Tag = 'Success' }
                    [System.Windows.MessageBox]::Show($testResult.Message, (Get-AppText -Key 'settings_validation.adobjects_success_box_title'), "OK", "Information")
                }
                else {
                    Write-LauncherLog -Message $testResult.Message -Level Error
                    switch ($testResult.Target) {
                        "OUPath" { $controls.OUPath.Tag = 'Error' }
                        "DomainUserGroup" { $controls.DomainUserGroup.Tag = 'Error' }
                        "ExcludedGroups" { $controls.ExcludedGroups.Tag = 'Error' }
                    }
                    [System.Windows.MessageBox]::Show($testResult.Message, (Get-AppText -Key 'settings_validation.adobjects_failure_box_title'), "OK", "Error")
                }

            }
            catch {
                # --- 4. Gestion des Exceptions ---
                $errorMessage = $_.Exception.Message
                Write-LauncherLog -Message "Erreur de validation : $errorMessage" -Level Error
                [System.Windows.MessageBox]::Show($errorMessage, (Get-AppText -Key 'settings_validation.adobjects_failure_box_title'), "OK", "Error")
        
            }
            finally {
                # --- 5. Restauration de l'Interface ---
                $controls.Button.IsEnabled = $true
                $controls.Button.Content = $originalButtonText
            }
        }.GetNewClosure())

    # ===============================================================
    # NOUVEAUX ÉVÉNEMENTS POUR LES TESTS DE CONNEXION AZURE
    # ===============================================================

    if ($Global:AppControls.SettingsUserAuthTestButton) {
        $Global:AppControls.SettingsUserAuthTestButton.Add_Click({
                # On récupère les valeurs saisies dans les champs (pas celles en config, celles à tester)
                $appId = $Global:AppControls.settingsUserAuthAppIdTextBox.Text
                $tenantId = $Global:AppControls.settingsTenantIdTextBox.Text # AJOUT
                $scopes = ($Global:AppControls.settingsUserAuthScopesTextBox.Text -split ',').Trim()
            
                # On désactive le bouton pendant le test pour éviter le double-clic
                $this.IsEnabled = $false
                $originalContent = $this.Content
                $this.Content = "Test..."
            
                # On force le rafraîchissement visuel
                [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([Action] {}, [System.Windows.Threading.DispatcherPriority]::Background)

                try {
                    # Appel avec le nouveau paramètre TenantId
                    $result = Test-AppAzureUserConnection -AppId $appId -TenantId $tenantId -Scopes $scopes
                
                    if ($result.Success) {
                        [System.Windows.MessageBox]::Show($result.Message, (Get-AppText 'settings_validation.azure_test_success_title'), "OK", "Information")
                    }
                    else {
                        [System.Windows.MessageBox]::Show($result.Message, (Get-AppText 'settings_validation.azure_test_failure_title'), "OK", "Error")
                    }
                }
                finally {
                    # Restauration du bouton (état connecté)
                    $this.Content = $originalContent
                    $this.IsEnabled = $true
                }
            }.GetNewClosure())
    }
    else {
        Write-Warning "Le bouton 'SettingsUserAuthTestButton' n'a pas été trouvé dans l'interface. L'événement n'a pas été attaché."
    }

    # ===============================================================
    # ÉVÉNEMENTS DE L'ONGLET GOUVERNANCE
    # ===============================================================

    if ($Global:AppControls.SyncAzureButton) {
        $Global:AppControls.SyncAzureButton.Add_Click({
                if (-not $Global:AppAzureAuth.UserAuth.Connected) {
                    [System.Windows.MessageBox]::Show((Get-AppText 'modules.launcherui.dialog_sync_required'), (Get-AppText 'modules.launcherui.dialog_sync_title'), "OK", "Warning")
                    return
                }

                # 1. UX : On verrouille l'interface
                $btn = $Global:AppControls.SyncAzureButton
                $originalText = $btn.Content
            
                $btn.IsEnabled = $false
                $btn.Content = "⏳  Synchro en cours..."
                $Global:AppControls.mainWindow.Cursor = [System.Windows.Input.Cursors]::Wait

                # Astuce pour forcer le rafraîchissement visuel immédiat du bouton
                [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([Action] {}, [System.Windows.Threading.DispatcherPriority]::Background)

                try {
                    # 2. Appel de la fonction lourde
                    Update-GovernanceTab
                    Write-LauncherLog -Message "Données de gouvernance synchronisées." -Level Success
                }
                catch {
                    Write-LauncherLog -Message "Erreur lors de la synchronisation : $($_.Exception.Message)" -Level Error
                }
                finally {
                    # 3. UX : On déverrouille
                    $btn.Content = $originalText
                    $btn.IsEnabled = $true
                    $Global:AppControls.mainWindow.Cursor = [System.Windows.Input.Cursors]::Arrow
                }
            }.GetNewClosure())
    }

    # GESTION DES DEMANDES (Approuver / Refuser)
    $Global:AppControls.PermissionRequestsListBox.AddHandler(
        [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent,
        [System.Windows.RoutedEventHandler] {
            $button = $this.OriginalSource
            # On vérifie que c'est bien un bouton
            if ($button -isnot [System.Windows.Controls.Button]) { return }
            
            # On récupère le contexte (l'item de la ligne)
            $request = $button.DataContext # DataContext est l'objet de la ligne (DataRow)

            if ($null -ne $button.CommandParameter) {
                # --- CAS REFUS (On a passé RequestID dans CommandParameter) ---
                $id = $button.CommandParameter
                if ([System.Windows.MessageBox]::Show("Rejeter cette demande ?", "Confirmation", "YesNo", "Warning") -eq 'Yes') {
                    # Mettre à jour le statut en BDD (Rejected)
                    $query = "UPDATE permission_requests SET Status = 'Rejected', ResolutionDate = '$(Get-Date -Format 'o')' WHERE RequestID = $id"
                    Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $query
                    Update-GovernanceTab
                }
            }
            elseif ($null -ne $button.Tag) {
                # --- CAS APPROBATION (On a passé tout l'objet dans Tag) ---
                $scope = $request.RequestedScope
                $appId = $Global:AppConfig.azure.authentication.userAuth.appId

                if ([System.Windows.MessageBox]::Show("Approuver la permission '$scope' pour l'application ?`nCela l'ajoutera à Azure AD.", "Confirmation", "YesNo", "Question") -eq 'Yes') {
                    $Global:AppControls.mainWindow.Cursor = [System.Windows.Input.Cursors]::Wait
                    try {
                        # 1. Ajouter dans Azure
                        Add-AppGraphPermission -AppId $appId -ScopeName $scope
                        
                        # 2. Mettre à jour BDD (Approved)
                        $id = $request.RequestID
                        $query = "UPDATE permission_requests SET Status = 'Approved', ResolutionDate = '$(Get-Date -Format 'o')' WHERE RequestID = $id"
                        Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $query

                        Write-LauncherLog -Message "Permission '$scope' approuvée." -Level Success
                        
                        # 3. Rafraîchir
                        Update-GovernanceTab
                        [System.Windows.MessageBox]::Show("Permission ajoutée.`nN'oubliez pas de valider le Consentement Admin.", "Succès", "OK", "Information")

                    }
                    catch {
                        [System.Windows.MessageBox]::Show("Erreur : $($_.Exception.Message)", "Erreur", "OK", "Error")
                    }
                    finally {
                        $Global:AppControls.mainWindow.Cursor = [System.Windows.Input.Cursors]::Arrow
                    }
                }
            }
        }
    )

    # Bouton "Ajouter manuellement"
    if ($Global:AppControls.AddPermissionButton) {
        $Global:AppControls.AddPermissionButton.Add_Click({
                if (-not $Global:AppAzureAuth.UserAuth.Connected) { return }

                # 1. Demander le nom de la permission
                Add-Type -AssemblyName Microsoft.VisualBasic
                $scopeName = [Microsoft.VisualBasic.Interaction]::InputBox(
                    "Entrez le nom exact de la permission Microsoft Graph à ajouter (ex: Mail.Read, Sites.Manage.All) :", 
                    "Ajouter une permission", 
                    ""
                )

                if ([string]::IsNullOrWhiteSpace($scopeName)) { return }

                # 2. Exécution
                $Global:AppControls.mainWindow.Cursor = [System.Windows.Input.Cursors]::Wait
                try {
                    $appId = $Global:AppConfig.azure.authentication.userAuth.appId
                
                    # Appel de la nouvelle fonction
                    Add-AppGraphPermission -AppId $appId -ScopeName $scopeName
                
                    # Succès
                    Write-LauncherLog -Message "Permission '$scopeName' ajoutée à l'application Azure." -Level Success
                    [System.Windows.MessageBox]::Show("La permission '$scopeName' a été ajoutée à la configuration de l'application.`n`nIMPORTANT : Vous (ou un admin) devez maintenant accorder le 'Consentement Administrateur' dans le portail Azure ou lors de la prochaine connexion.", "Succès", "OK", "Information")
                
                    # Rafraîchissement
                    Update-GovernanceTab

                }
                catch {
                    [System.Windows.MessageBox]::Show("Erreur : $($_.Exception.Message)", "Erreur", "OK", "Error")
                    Write-LauncherLog -Message "Echec ajout permission : $($_.Exception.Message)" -Level Error
                }
                finally {
                    $Global:AppControls.mainWindow.Cursor = [System.Windows.Input.Cursors]::Arrow
                }
            }.GetNewClosure())
    }

    if ($Global:AppControls.GrantConsentButton) {
        $Global:AppControls.GrantConsentButton.Add_Click({
                $tenantId = $Global:AppConfig.azure.tenantId
                $appId = $Global:AppConfig.azure.authentication.userAuth.appId
            
                if ([string]::IsNullOrWhiteSpace($tenantId) -or [string]::IsNullOrWhiteSpace($appId)) { return }

                # URL Standard de Consentement Admin Microsoft
                $consentUrl = "https://login.microsoftonline.com/$tenantId/adminconsent?client_id=$appId&redirect_uri=http://localhost"
            
                [System.Windows.MessageBox]::Show("Une page web va s'ouvrir.`nConnectez-vous avec un compte Administrateur Global et acceptez les permissions demandées.", "Consentement Requis", "OK", "Information")
            
                Start-Process $consentUrl

            }.GetNewClosure())
    }

    # ===============================================================
    # ÉVÉNEMENTS DE L'ONGLET "GESTION DES SCRIPTS"
    # ===============================================================

    # A. GESTION DE LA BIBLIOTHÈQUE
    # -----------------------------
    $Global:AppControls.LibraryAddGroupButton.Add_Click({
            $groupName = $Global:AppControls.LibraryNewGroupTextBox.Text.Trim()
            if ([string]::IsNullOrWhiteSpace($groupName)) { return }

            # Vérification dans Azure AD
            $Global:AppControls.mainWindow.Cursor = [System.Windows.Input.Cursors]::Wait
            try {
                # On cherche le groupe
                $group = Get-MgGroup -Filter "displayName eq '$groupName'" -ErrorAction SilentlyContinue | Select-Object -First 1
            
                if ($group) {
                    # Groupe trouvé -> On l'ajoute à la bibliothèque
                    if (Add-AppKnownGroup -GroupName $group.DisplayName -Description $group.Description) {
                        $Global:AppControls.LibraryNewGroupTextBox.Text = ""
                        Update-ManagementScriptList # Rafraîchir la liste
                        Write-LauncherLog -Message ((Get-AppText 'modules.launcherui.man_group_added') -f $groupName) -Level Success
                    }
                }
                else {
                    [System.Windows.MessageBox]::Show(((Get-AppText 'modules.launcherui.man_group_not_found') -f $groupName), (Get-AppText 'modules.launcherui.man_group_not_found_title'), "OK", "Warning")
                }
            }
            catch {
                Write-LauncherLog -Message "Erreur vérification groupe : $($_.Exception.Message)" -Level Error
            }
            finally {
                $Global:AppControls.mainWindow.Cursor = [System.Windows.Input.Cursors]::Arrow
            }
        }.GetNewClosure())

    # Suppression d'un groupe de la bibliothèque (Double Clic)
    $Global:AppControls.LibraryRemoveGroupButton.Add_Click({
            # On récupère l'élément sélectionné dans la ComboBox
            $selectedItem = $Global:AppControls.LibraryGroupsComboBox.SelectedItem 
        
            if ($selectedItem) {
                $gName = $selectedItem.GroupName
                if ([System.Windows.MessageBox]::Show(((Get-AppText 'modules.launcherui.man_confirm_delete') -f $gName), (Get-AppText 'modules.launcherui.man_confirm_delete_title'), "YesNo", "Warning") -eq 'Yes') {
                    Remove-AppKnownGroup -GroupName $gName
                    Update-ManagementScriptList
                
                    # On rafraîchit aussi la liste des checkbox à droite si un script est sélectionné
                    # (Pour faire disparaître visuellement le groupe supprimé)
                    $selectedScript = $Global:AppControls.ManageScriptsListBox.SelectedItem
                    if ($selectedScript) {
                        # Astuce : on recharge la sélection pour rafraîchir la liste de droite
                        $Global:AppControls.ManageScriptsListBox.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.ListBox]::SelectionChangedEvent))
                    }
                }
            }
            else {
                [System.Windows.MessageBox]::Show("Veuillez sélectionner un groupe dans la liste déroulante à supprimer.", "Info", "OK", "Information")
            }
        }.GetNewClosure())

    # ===================================================================
    # GESTION DES MODIFICATIONS NON SAUVEGARDÉES (DIRTY STATE)
    # ===================================================================
    
    $ViewState = @{
        UnsavedChanges    = $false
        IsLoading         = $false
        OriginalSelection = $null
    }

    # Fonction locale pour marquer comme "Modifié"
    $markAsDirty = {
        if ($ViewState.IsLoading) { return }

        if (-not $ViewState.UnsavedChanges) {
            $ViewState.UnsavedChanges = $true
            $Global:AppControls.ManageSaveButton.Content = "💾   Enregistrer les modifications *"
            $Global:AppControls.ManageSaveButton.Background = $Global:AppControls.mainWindow.FindResource('WarningBrush')
            $Global:AppControls.ManageSaveButton.BorderBrush = $Global:AppControls.mainWindow.FindResource('WarningBrush')
        }
    }.GetNewClosure()

    # Fonction locale pour marquer comme "Propre"
    $markAsClean = {
        $ViewState.UnsavedChanges = $false
        $Global:AppControls.ManageSaveButton.Content = "💾   " + (Get-AppText 'management.btn_save')
        $Global:AppControls.ManageSaveButton.Background = $Global:AppControls.mainWindow.FindResource('GreenBrush')
        $Global:AppControls.ManageSaveButton.BorderBrush = $Global:AppControls.mainWindow.FindResource('GreenBrush')
    }.GetNewClosure()

    # Fonction pour ANNULER les changements en mémoire (Rollback COMPLET)
    $rollbackChanges = {
        param($scriptObject)
        if (-not $scriptObject) { return }
        
        # 1. Rollback des paramètres simples (Gauche)
        $dbSettings = Get-AppScriptSettingsMap
        if ($dbSettings.ContainsKey($scriptObject.id)) {
            $scriptObject.enabled = [bool]$dbSettings[$scriptObject.id].IsEnabled
            $scriptObject.maxConcurrentRuns = [int]$dbSettings[$scriptObject.id].MaxConcurrentRuns
        }

        # 2. Rollback de la sécurité (Droite) - NOUVEAU
        # On doit recharger la liste visuelle pour qu'elle recoche les bonnes cases
        $securityMap = Get-AppScriptSecurity
        $authorizedGroups = $securityMap[$scriptObject.id]
        if (-not $authorizedGroups) { $authorizedGroups = @() }
        
        # On parcourt la liste actuelle liée à l'UI et on remet les valeurs d'origine
        $currentList = $Global:AppControls.ManageSecurityCheckList.ItemsSource
        if ($currentList) {
            foreach ($item in $currentList) {
                # On remet IsSelected à la valeur BDD sans déclencher d'événement (car on est dans le flux logique)
                $item.IsSelected = $authorizedGroups -contains $item.GroupName
            }
            $Global:AppControls.ManageSecurityCheckList.Items.Refresh()
        }

        $Global:AppControls.ManageScriptsListBox.Items.Refresh()
    }.GetNewClosure()

    # --- 1. Détection des changements (Inputs) ---
    
    $Global:AppControls.ManageEnabledSwitch.Add_Click({ & $markAsDirty }.GetNewClosure())
    
    $Global:AppControls.ManageMaxRunsTextBox.Add_TextChanged({ 
            if ($this.IsKeyboardFocusWithin) { & $markAsDirty } 
        }.GetNewClosure())

    $Global:AppControls.ManageSecurityCheckList.Add_PreviewMouseLeftButtonUp({
            # On regarde sur quoi l'utilisateur a cliqué physiquement
            $element = $this.InputHitTest($_.GetPosition($this))
        
            # On remonte l'arbre visuel pour voir si on a cliqué sur une CheckBox (ou ses composants internes comme la Border/Ellipse)
            while ($element -and $element -isnot [System.Windows.Controls.CheckBox]) {
                $element = [System.Windows.Media.VisualTreeHelper]::GetParent($element)
            }

            # Si on a trouvé une CheckBox dans la lignée du clic
            if ($element) {
                # On marque comme modifié
                & $markAsDirty
            
                # PETITE ASTUCE : Comme c'est un événement "Preview", le changement de valeur n'a pas encore eu lieu.
                # WPF va traiter le clic juste après. C'est parfait pour nous.
            }
        }.GetNewClosure())


    # --- 2. Protection de la Navigation (Changement de script) ---
    
    $Global:AppControls.ManageScriptsListBox.Add_SelectionChanged({
            $newSelection = $Global:AppControls.ManageScriptsListBox.SelectedItem
        
            if ($ViewState.UnsavedChanges) {
                $result = [System.Windows.MessageBox]::Show(
                    "Des modifications n'ont pas été enregistrées sur le script précédent.`nVoulez-vous les ignorer ?", 
                    "Modifications en cours", 
                    [System.Windows.MessageBoxButton]::YesNo, 
                    [System.Windows.MessageBoxImage]::Warning
                )

                if ($result -eq 'No') {
                    if ($ViewState.OriginalSelection -and $ViewState.OriginalSelection -ne $newSelection) {
                        $ViewState.IsLoading = $true
                        $Global:AppControls.ManageScriptsListBox.SelectedItem = $ViewState.OriginalSelection
                        $Global:AppControls.mainWindow.Dispatcher.Invoke([Action] { $ViewState.IsLoading = $false }, [System.Windows.Threading.DispatcherPriority]::Input)
                    }
                    return
                }
                else {
                    # OUI : On ignore les changements -> ROLLBACK COMPLET
                    & $rollbackChanges -scriptObject $ViewState.OriginalSelection
                    & $markAsClean
                }
            }

            $ViewState.IsLoading = $true
            $ViewState.OriginalSelection = $newSelection
        
            & $markAsClean

            if ($newSelection) {
                $Global:AppControls.ManageSelectPrompt.Visibility = 'Collapsed'
                $Global:AppControls.ManageDetailPanel.Visibility = 'Visible'
                $Global:AppControls.ManageDetailPanel.DataContext = $newSelection
            
                $allGroups = Get-AppKnownGroups
                $securityMap = Get-AppScriptSecurity
                $authorizedGroups = $securityMap[$newSelection.id]
                if (-not $authorizedGroups) { $authorizedGroups = @() }

                $checkBoxList = @()
                foreach ($g in $allGroups) {
                    $checkBoxList += [PSCustomObject]@{
                        GroupName  = $g.GroupName
                        IsSelected = $authorizedGroups -contains $g.GroupName
                    }
                }
                $Global:AppControls.ManageSecurityCheckList.ItemsSource = $checkBoxList
            }
            else {
                $Global:AppControls.ManageDetailPanel.Visibility = 'Collapsed'
                $Global:AppControls.ManageSelectPrompt.Visibility = 'Visible'
            }

            $Global:AppControls.mainWindow.Dispatcher.Invoke([Action] { 
                    $ViewState.IsLoading = $false 
                }, [System.Windows.Threading.DispatcherPriority]::Input)

        }.GetNewClosure())

    # 4. BOUTON ENREGISTRER
    $Global:AppControls.ManageSaveButton.Add_Click({
            $selectedScript = $Global:AppControls.ManageScriptsListBox.SelectedItem
            if (-not $selectedScript) { return }

            $maxRuns = 1
            if (-not [int]::TryParse($selectedScript.maxConcurrentRuns, [ref]$maxRuns)) {
                [System.Windows.MessageBox]::Show((Get-AppText 'modules.launcherui.man_save_error_int'), (Get-AppText 'modules.launcherui.man_save_error_title'), "OK", "Error")
                return
            }

            if (-not (Set-AppScriptSettings -ScriptId $selectedScript.id -IsEnabled $selectedScript.enabled -MaxConcurrentRuns $maxRuns)) {
                [System.Windows.MessageBox]::Show("Erreur lors de la sauvegarde des paramètres.", "Erreur", "OK", "Error")
                return
            }

            $groupsList = $Global:AppControls.ManageSecurityCheckList.ItemsSource
            foreach ($item in $groupsList) {
                if ($item.IsSelected) {
                    Add-AppScriptSecurityGroup -ScriptId $selectedScript.id -ADGroup $item.GroupName | Out-Null
                }
                else {
                    Remove-AppScriptSecurityGroup -ScriptId $selectedScript.id -ADGroup $item.GroupName | Out-Null
                }
            }

            $Global:AppControls.ManageScriptsListBox.Items.Refresh()
            $Global:AppAvailableScripts = Get-FilteredAndEnrichedScripts -ProjectRoot $ProjectRoot
            Update-ScriptListBoxUI -scripts $Global:AppAvailableScripts
            
            Write-LauncherLog -Message "Configuration du script '$($selectedScript.name)' enregistrée." -Level Success
            [System.Windows.MessageBox]::Show((Get-AppText 'modules.launcherui.man_save_success'), (Get-AppText 'modules.launcherui.man_save_success_title'), "OK", "Information")

            & $markAsClean

        }.GetNewClosure())

    # --- BOUTON TESTER CERTIFICAT ---
    if ($Global:AppControls.SettingsTestCertButton) {
        $Global:AppControls.SettingsTestCertButton.Add_Click({
            
                # 1. Récupération des valeurs
                $tenantId = $Global:AppControls.SettingsTenantIdTextBox.Text # On utilise l'ID pour Graph
                $clientId = $Global:AppControls.SettingsUserAuthAppIdTextBox.Text
                $thumb = $Global:AppControls.SettingsCertThumbprintTextBox.Text

                if ([string]::IsNullOrWhiteSpace($tenantId) -or [string]::IsNullOrWhiteSpace($clientId) -or [string]::IsNullOrWhiteSpace($thumb)) {
                    [System.Windows.MessageBox]::Show("Veuillez remplir le Tenant ID, l'App ID et le Thumbprint.", "Données manquantes", "OK", "Warning")
                    return
                }

                # 2. UI En cours
                $btn = $Global:AppControls.SettingsTestCertButton
                $oldContent = $btn.Content
                $btn.Content = "Test Graph..."
                $btn.IsEnabled = $false
                $Global:AppControls.mainWindow.Cursor = [System.Windows.Input.Cursors]::Wait
                $Global:AppControls.mainWindow.Dispatcher.Invoke([Action] {}, [System.Windows.Threading.DispatcherPriority]::Render)

                # 3. Test de Connexion via le module AZURE (Graph)
                try {
                    # Plus besoin d'importer Toolbox.SharePoint ici !
                    $result = Test-AppAzureCertConnection -TenantId $tenantId -ClientId $clientId -Thumbprint $thumb
                
                    if ($result.Success) {
                        [System.Windows.MessageBox]::Show("Connexion RÉUSSIE (Graph API) !`n`nLe certificat est valide pour l'application Azure.", "Succès", "OK", "Information")
                    }
                    else {
                        [System.Windows.MessageBox]::Show("Échec de la connexion :`n$($result.Message)", "Échec", "OK", "Error")
                    }
                }
                catch {
                    [System.Windows.MessageBox]::Show("Erreur technique : $($_.Exception.Message)", "Erreur", "OK", "Error")
                }
                finally {
                    # 4. Restauration UI
                    $btn.Content = $oldContent
                    $btn.IsEnabled = $true
                    $Global:AppControls.mainWindow.Cursor = [System.Windows.Input.Cursors]::Arrow
                }

            }.GetNewClosure())
    }
}