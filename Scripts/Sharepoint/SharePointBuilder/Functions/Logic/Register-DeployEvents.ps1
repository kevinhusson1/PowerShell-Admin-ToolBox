# Scripts/SharePoint/SharePointBuilder/Functions/Logic/Register-DeployEvents.ps1

<#
.SYNOPSIS
    Enregistre les événements liés au déploiement et à la gestion des configurations.

.DESCRIPTION
    Configure les actions pour les boutons "Déployer", "Sauvegarder", "Charger", "Supprimer" et "Réinitialiser".
    Gère la logique d'exécution du Job de déploiement (avec barre de progression et logs),
    la persistance des configurations dans la base de données, et la validation des actions.

.PARAMETER Ctrl
    La Hashtable des contrôles UI.

.PARAMETER Window
    La fenêtre WPF principale.
#>
function Register-DeployEvents {
    param(
        [hashtable]$Ctrl,
        [System.Windows.Window]$Window
    )

    # Helper de log interne pour cette fonction
    $Log = { param($msg, $lvl = "Info") Write-AppLog -Message $msg -Level $lvl -RichTextBox $Ctrl.LogBox }.GetNewClosure()

    $Ctrl.BtnDeploy.Add_Click({
            $Ctrl.BtnDeploy.IsEnabled = $false
            $Ctrl.ProgressBar.IsIndeterminate = $true
            $Ctrl.TxtStatus.Text = "Déploiement en cours..."
            $Ctrl.LogBox.Document.Blocks.Clear()
        
            $cbLevel = $Window.FindName("LogLevelComboBox")
            $logLevel = "Normal"
            if ($cbLevel.SelectedItem) { $logLevel = $cbLevel.SelectedItem.Tag }
        
            Write-AppLog -Message "Démarrage déploiement (Niveau: $logLevel)..." -Level Info -RichTextBox $Ctrl.LogBox

            # --- LOGIQUE CRITIQUE ---
            # Si on ne crée pas de dossier, on passe une chaîne vide pour le nom du dossier
            $folderNameParam = if ($Ctrl.ChkCreateFolder.IsChecked) { $Ctrl.TxtPreview.Text } else { "" }

            $jobArgs = @{
                ModPath       = Join-Path $Global:ProjectRoot "Modules\Toolbox.SharePoint"
                Thumb         = $Global:AppConfig.azure.certThumbprint
                ClientId      = $Global:AppConfig.azure.authentication.userAuth.appId
                Tenant        = $Global:AppConfig.azure.tenantName
                TargetUrl     = $Ctrl.CbSites.SelectedItem.Url
                LibName       = $Ctrl.CbLibs.SelectedItem.Title
                LibRelUrl     = $Ctrl.CbLibs.SelectedItem.RootFolder.ServerRelativeUrl
                FolderName    = $folderNameParam 
                StructureJson = ($Ctrl.CbTemplates.SelectedItem.StructureJson)
            }

            $job = Start-Job -ScriptBlock {
                param($ArgsMap)
                Import-Module $ArgsMap.ModPath -Force
                try {
                    New-AppSPStructure `
                        -TargetSiteUrl $ArgsMap.TargetUrl `
                        -TargetLibraryName $ArgsMap.LibName `
                        -RootFolderName $ArgsMap.FolderName `
                        -StructureJson $ArgsMap.StructureJson `
                        -ClientId $ArgsMap.ClientId `
                        -Thumbprint $ArgsMap.Thumb `
                        -TenantName $ArgsMap.Tenant
                }
                catch { throw $_ }
            } -ArgumentList $jobArgs
        
            $timer = New-Object System.Windows.Threading.DispatcherTimer
            $timer.Interval = [TimeSpan]::FromMilliseconds(500)
        
            $timerBlock = {
                if ($job.State -ne 'Running') {
                    $timer.Stop()
                
                    $fLog = $Window.FindName("LogRichTextBox")
                    $fProg = $Window.FindName("MainProgressBar")
                    $fStat = $Window.FindName("ProgressStatusText")
                    $fBtn = $Window.FindName("DeployButton")
                    $fCopy = $Window.FindName("CopyUrlButton")
                    $fOpen = $Window.FindName("OpenUrlButton")

                    $result = Receive-Job $job -Wait -AutoRemoveJob
                
                    if ($fProg) { $fProg.IsIndeterminate = $false; $fProg.Value = 100 }

                    if ($job.State -eq 'Failed') {
                        $err = $job.ChildJobs[0].Error
                        if ($fLog) { Write-AppLog -Message "CRASH JOB : $err" -Level Error -RichTextBox $fLog }
                        if ($fStat) { $fStat.Text = "Erreur critique." }
                        if ($fBtn) { $fBtn.IsEnabled = $true }
                    } 
                    else {
                        if ($result.Success) {
                            if ($fStat) { $fStat.Text = "Déploiement réussi !" }
                            if ($fLog) { Write-AppLog -Message "Terminé avec succès." -Level Success -RichTextBox $fLog }
                        
                            # URL Finale
                            $uriSite = [Uri]$jobArgs.TargetUrl
                            $rootHost = "$($uriSite.Scheme)://$($uriSite.Host)"
                            # Si dossier vide, URL = Lib, sinon URL = Lib/Dossier
                            $pathSuffix = if ($jobArgs.FolderName) { "/$($jobArgs.FolderName)" } else { "" }
                            $finalUrl = "$rootHost$($jobArgs.LibRelUrl)$pathSuffix"
                        
                            if ($fCopy) { 
                                $fCopy.IsEnabled = $true 
                                $fCopy.Tag = $finalUrl
                            }
                            if ($fOpen) { $fOpen.IsEnabled = $true }
                            if ($fBtn) { $fBtn.IsEnabled = $false }
                        } 
                        else {
                            if ($fStat) { $fStat.Text = "Terminé avec erreurs." }
                            if ($fBtn) { $fBtn.IsEnabled = $true }
                        }

                        if ($result.Logs) {
                            foreach ($line in $result.Logs) {
                                $parts = $line -split '\|', 2
                                $lvl = if ($parts.Count -eq 2) { $parts[0] } else { "INFO" }
                                $msg = if ($parts.Count -eq 2) { $parts[1] } else { $line }

                                $show = $false
                                switch ($logLevel) {
                                    "Light" { if ($lvl -in "SUCCESS", "ERROR", "WARNING") { $show = $true } }
                                    "Normal" { if ($lvl -in "SUCCESS", "ERROR", "WARNING", "INFO") { $show = $true } }
                                    "Hard" { $show = $true }
                                }

                                if ($show -and $fLog) {
                                    $color = switch ($lvl) { "DEBUG" { "Debug" } "INFO" { "Info" } "WARNING" { "Warning" } "ERROR" { "Error" } "SUCCESS" { "Success" } Default { "Info" } }
                                    Write-AppLog -Message $msg -Level $color -RichTextBox $fLog
                                }
                            }
                        }
                    }
                }
            }.GetNewClosure()

            $timer.Add_Tick($timerBlock)
            $timer.Start()

        }.GetNewClosure())
    
    $Ctrl.BtnCopyUrl.Add_Click({
            if ($this.Tag) { Set-Clipboard -Value $this.Tag; Write-AppLog -Message "URL copiée : $($this.Tag)" -Level Info -RichTextBox $Ctrl.LogBox }
        }.GetNewClosure())

    $Ctrl.BtnOpenUrl.Add_Click({
            $copyBtn = $Window.FindName("CopyUrlButton")
            if ($copyBtn -and $copyBtn.Tag) { Start-Process $copyBtn.Tag }
        }.GetNewClosure())

    # ==========================================================================
    # BOUTON RESET
    # ==========================================================================
    if ($Ctrl.BtnReset) {
        $Ctrl.BtnReset.Add_Click({
                # 1. Libérer la cible (Site & Lib)
                $Ctrl.CbSites.SelectedIndex = -1
                $Ctrl.CbLibs.SelectedIndex = -1
                $Ctrl.CbLibs.ItemsSource = @()
                $Ctrl.CbLibs.IsEnabled = $false

                # 2. Libérer le modèle
                $Ctrl.CbTemplates.SelectedIndex = -1

                # 3. Décocher création dossier & Reset Règle
                $Ctrl.ChkCreateFolder.IsChecked = $false
                # On remet la sélection par défaut pour la règle si possible, ou rien
                if ($Ctrl.CbFolderTemplates -and $Ctrl.CbFolderTemplates.Items.Count -gt 0) {
                    $Ctrl.CbFolderTemplates.SelectedIndex = -1 
                }
                # Vider le formulaire généré
                if ($Ctrl.PanelForm) { $Ctrl.PanelForm.Children.Clear() }

                # 4. Décocher Overwrite
                $Ctrl.ChkOverwrite.IsChecked = $false

                # 5. Deselection Config si active
                if ($Ctrl.CbDeployConfigs) { $Ctrl.CbDeployConfigs.SelectedIndex = -1 }
                
                # 6. Vider le TreeView et la Description
                if ($Ctrl.TreeView) { $Ctrl.TreeView.Items.Clear() }
                if ($Ctrl.TxtDesc) { $Ctrl.TxtDesc.Text = "" }
                if ($Ctrl.TxtPreview) { $Ctrl.TxtPreview.Text = "Aperçu du nom..." }
                
                # Feedback
                & $Log "Interface réinitialisée." "Info"
                
                # Validation update (via event propagation or explicit call)
                # Les changements de sélection déclenchent déjà les events, mais on force un DoEvents si besoin
                [System.Windows.Forms.Application]::DoEvents()

            }.GetNewClosure())
    }

    # ==========================================================================
    # GESTION DES CONFIGURATIONS
    # ==========================================================================
        
    # 1. Helper : Charger la liste des configs
    $LoadDeployConfigs = {
        try {
            # & $Log "Chargement des configurations..." "Info" # Trop verbeux au survol
            $configs = @(Get-AppDeployConfigs)
            
            # Force refresh by nulling first
            $Ctrl.CbDeployConfigs.ItemsSource = $null
            $Ctrl.CbDeployConfigs.ItemsSource = $configs
            $Ctrl.CbDeployConfigs.DisplayMemberPath = "ConfigName"

            # if ($configs.Count -gt 0) { & $Log "$($configs.Count) configurations disponibles." "Info" }
        }
        catch {
            & $Log "Erreur chargement configurations : $($_.Exception.Message)" "Error"
        }
    }.GetNewClosure()

    # Appel initial différé (Au chargement du contrôle)
    # Cela garantit que le contrôle est prêt et que le contexte est stable
    $Ctrl.CbDeployConfigs.Add_Loaded({
            & $LoadDeployConfigs
        }.GetNewClosure())

    # --- GESTION ETAT BOUTON SAUVEGARDER ---
    # Le bouton ne doit être actif que si l'étape 1 (Site/Lib) et 2 (Modèle) sont OK.
    
    $UpdateSaveState = {
        $hasSite = ($null -ne $Ctrl.CbSites.SelectedItem -and $Ctrl.CbSites.SelectedItem -isnot [string])
        $hasLib = ($null -ne $Ctrl.CbLibs.SelectedItem -and $Ctrl.CbLibs.SelectedItem -isnot [string] -and $Ctrl.CbLibs.SelectedItem -ne "Chargement...")
        $hasTpl = ($null -ne $Ctrl.CbTemplates.SelectedItem)
        
        $Ctrl.BtnSaveConfig.IsEnabled = ($hasSite -and $hasLib -and $hasTpl)
    }.GetNewClosure()

    # Initialisation : Désactivé par défaut
    $Ctrl.BtnSaveConfig.IsEnabled = $false

    # On attache la vérification aux changements de sélection
    # Note : On utilise 'Add_SelectionChanged' ici. Si d'autres handlers existent ailleurs (Register-SiteEvents), 
    # c'est OK car WPF supporte le multicast délégué (plusieurs abonnés).
    if ($Ctrl.CbSites) { $Ctrl.CbSites.Add_SelectionChanged($UpdateSaveState) }
    if ($Ctrl.CbLibs) { $Ctrl.CbLibs.Add_SelectionChanged($UpdateSaveState) }
    if ($Ctrl.CbTemplates) { $Ctrl.CbTemplates.Add_SelectionChanged($UpdateSaveState) }


    # --- SAVE CONFIGURATION ---
    if ($Ctrl.BtnSaveConfig) {
        $Ctrl.BtnSaveConfig.Add_Click({
                # A. VALIDATION STRICTE
                # A. VALIDATION STRICTE
                if (-not $Ctrl.BtnSaveConfig.IsEnabled) { return }
            
                # B. RECUP DONNEES
                $siteUrl = $Ctrl.CbSites.SelectedItem.Url
                $libName = $Ctrl.CbLibs.SelectedItem.Title
                $tplId = $Ctrl.CbTemplates.SelectedItem.TemplateId
                $overwrite = $Ctrl.ChkOverwrite.IsChecked
            
                $targetFolder = ""
                if ($Ctrl.ChkCreateFolder.IsChecked) {
                    if ($Ctrl.CbFolderTemplates.SelectedItem) {
                        $targetFolder = $Ctrl.CbFolderTemplates.SelectedItem.RuleId
                    }
                    else {
                        [System.Windows.MessageBox]::Show("Aucune règle de nommage sélectionnée.", "Erreur", "OK", "Warning"); return
                    }
                }

                # C. NOM
                Add-Type -AssemblyName Microsoft.VisualBasic
                $confName = [Microsoft.VisualBasic.Interaction]::InputBox("Nom de la configuration :", "Sauvegarder", "Deploy-$($Ctrl.CbSites.SelectedItem.SiteName)-$libName")
                if ([string]::IsNullOrWhiteSpace($confName)) { return }

                try {
                    Set-AppDeployConfig -ConfigName $confName -SiteUrl $siteUrl -LibraryName $libName -TargetFolder $targetFolder -OverwritePermissions $overwrite -TemplateId $tplId
                
                    & $Log "Configuration '$confName' sauvegardée." "Success"
                    [System.Windows.MessageBox]::Show("Configuration sauvegardée.", "Succès", "OK", "Information")
                
                    & $LoadDeployConfigs
                }
                catch {
                    [System.Windows.MessageBox]::Show("Erreur sauvegarde : $($_.Exception.Message)", "Erreur", "OK", "Error")
                }
            }.GetNewClosure())
    }
    
    # Gestion Etat Boutons (Load / Delete)
    if ($Ctrl.CbDeployConfigs) {
        $Ctrl.CbDeployConfigs.Add_SelectionChanged({
                $curr = $Ctrl.CbDeployConfigs.SelectedItem
                $hasSel = ($null -ne $curr)
                
                # Vérification de l'état des sites (Loaded & Valid)
                $areSitesReady = ($Ctrl.CbSites.Items.Count -gt 0 -and ($Ctrl.CbSites.Items[0] -isnot [string]))

                # Bouton Charger actif SI config sélectionnée ET sites prêts
                $Ctrl.BtnLoadConfig.IsEnabled = ($hasSel -and $areSitesReady)
            
                # Bouton Supprimer actif UNIQUEMENT si sélectionné
                $Ctrl.BtnDeleteConfig.IsEnabled = $hasSel
            }.GetNewClosure())
    }

    # 2. CHARGER UNE CONFIGURATION
    if ($Ctrl.BtnLoadConfig) {
        $Ctrl.BtnLoadConfig.Add_Click({
                $cfg = $Ctrl.CbDeployConfigs.SelectedItem
                if (-not $cfg) { return }

                # Vérification : Sites sont-ils chargés ?
                if ($Ctrl.CbSites.Items.Count -eq 0) {
                    [System.Windows.MessageBox]::Show("Veuillez attendre le chargement complet des sites SharePoint.", "Attente", "OK", "Warning")
                    return
                }

                try {
                    & $Log "Chargement configuration '$($cfg.ConfigName)'..." "Info"

                    # A. Site
                    $site = $Ctrl.CbSites.Items | Where-Object { $_.Url -eq $cfg.SiteUrl } | Select-Object -First 1
                    if ($site) { 
                        $Ctrl.CbSites.SelectedItem = $site 
                        # FORCE UI REFRESH
                        [System.Windows.Forms.Application]::DoEvents()
                        Start-Sleep -Milliseconds 200
                        [System.Windows.Forms.Application]::DoEvents()
                    }
                    else {
                        & $Log "Site introuvable : $($cfg.SiteUrl)" "Warning"
                    }

                    # B. Bibliothèque (WAIT LOOP)
                    # On attend que la Combo Libs soit active ET contienne autre chose que "Chargement..."
                    # Le Handler SITES met "Chargement..." et IsEnabled=False
                    $maxRetries = 50 # 5 secondes
                    
                    # Logique d'attente :
                    # Tant que (EstDésactivé) OU (Vide) OU (Contient "Chargement...")
                    while ($maxRetries -gt 0) {
                        $isLoadingItem = ($Ctrl.CbLibs.Items.Count -eq 1 -and $Ctrl.CbLibs.Items[0] -eq "Chargement...")
                        $isEmpty = ($Ctrl.CbLibs.Items.Count -eq 0)
                        $isDisabled = (-not $Ctrl.CbLibs.IsEnabled) 

                        if (-not $isDisabled -and -not $isLoadingItem -and -not $isEmpty) {
                            break 
                        }

                        Start-Sleep -Milliseconds 100
                        [System.Windows.Forms.Application]::DoEvents()
                        $maxRetries--
                    }

                    $lib = $Ctrl.CbLibs.Items | Where-Object { $_.Title -eq $cfg.LibraryName } | Select-Object -First 1
                    if ($lib) { $Ctrl.CbLibs.SelectedItem = $lib }
                    else { & $Log "Bibliothèque introuvable ou non chargée : $($cfg.LibraryName)" "Warning" }

                    # C. Permissions
                    $Ctrl.ChkOverwrite.IsChecked = ($cfg.OverwritePermissions -eq 1)

                    # D. Modèle
                    $tpl = $Ctrl.CbTemplates.Items | Where-Object { $_.TemplateId -eq $cfg.TemplateId } | Select-Object -First 1
                    if ($tpl) { $Ctrl.CbTemplates.SelectedItem = $tpl }

                    # E. Dossier Cible / Règle
                    if (-not [string]::IsNullOrWhiteSpace($cfg.TargetFolder)) {
                        $Ctrl.ChkCreateFolder.IsChecked = $true
                        $rule = $Ctrl.CbFolderTemplates.Items | Where-Object { $_.RuleId -eq $cfg.TargetFolder } | Select-Object -First 1
                        if ($rule) { $Ctrl.CbFolderTemplates.SelectedItem = $rule }
                    }
                    else {
                        $Ctrl.ChkCreateFolder.IsChecked = $false
                    }

                    & $Log "Configuration chargée." "Success"
                }
                catch {
                    [System.Windows.MessageBox]::Show("Erreur chargement : $($_.Exception.Message)", "Erreur", "OK", "Error")
                }
            }.GetNewClosure())
    }

    # 3. SUPPRIMER UNE CONFIGURATION
    if ($Ctrl.BtnDeleteConfig) {
        $Ctrl.BtnDeleteConfig.Add_Click({
                $cfg = $Ctrl.CbDeployConfigs.SelectedItem
                if (-not $cfg) { return }

                if ([System.Windows.MessageBox]::Show("Supprimer la configuration '$($cfg.ConfigName)' ?", "Confirmer", "YesNo", "Warning") -eq 'Yes') {
                    try {
                        Remove-AppDeployConfig -ConfigName $cfg.ConfigName
                    
                        # Log
                        & $Log "Configuration '$($cfg.ConfigName)' supprimée." "Info"
                    
                        # Reset UI partiel
                        $Ctrl.CbDeployConfigs.SelectedItem = $null

                        # Force UI update (fix for refresh issue)
                        [System.Windows.Forms.Application]::DoEvents()
                    
                        & $LoadDeployConfigs
                    
                        # Reset Interface global
                        $Ctrl.CbSites.SelectedIndex = -1
                        $Ctrl.CbLibs.SelectedIndex = -1
                        $Ctrl.CbTemplates.SelectedIndex = -1
                        $Ctrl.ChkOverwrite.IsChecked = $false
                        $Ctrl.ChkCreateFolder.IsChecked = $false

                        [System.Windows.MessageBox]::Show("Configuration supprimée.", "Succès", "OK", "Information")
                    }
                    catch {
                        [System.Windows.MessageBox]::Show("Erreur suppression : $($_.Exception.Message)", "Erreur", "OK", "Error")
                    }
                }
            }.GetNewClosure())
    }
}