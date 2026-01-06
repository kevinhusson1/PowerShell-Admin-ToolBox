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

    # --- ÉTAT DE VALIDATION ---
    $ValidationState = @{ IsValid = $false }

    $UpdateSaveState = {
        $hasSite = ($null -ne $Ctrl.CbSites.SelectedItem -and $Ctrl.CbSites.SelectedItem -isnot [string])
        $hasLib = ($null -ne $Ctrl.CbLibs.SelectedItem -and $Ctrl.CbLibs.SelectedItem -isnot [string] -and $Ctrl.CbLibs.SelectedItem -ne "Chargement...")
        $hasTpl = ($null -ne $Ctrl.CbTemplates.SelectedItem) # Wait, si ItemsSource vide, SelectedItem est null ?
        
        # Le bouton Sauvegarder nécessite que tout soit sélectionné ET validé
        $Ctrl.BtnSaveConfig.IsEnabled = ($hasSite -and $hasLib -and $hasTpl -and $ValidationState.IsValid)
    }.GetNewClosure()

    # Invalidation : Si on change quoi que ce soit, on doit re-valider
    $InvalidateState = {
        $ValidationState.IsValid = $false
        $Ctrl.BtnDeploy.IsEnabled = $false
        & $UpdateSaveState # Met à jour BtnSaveConfig
        
        # Feedback visuel optionnel (Log ?)
        # if ($Ctrl.BtnValidate) { $Ctrl.BtnValidate.Content = "⚠️ Vérifier" } # Reset texte ?
    }.GetNewClosure()

    # Initialisation : Désactivé par défaut
    $Ctrl.BtnDeploy.IsEnabled = $false
    $Ctrl.BtnSaveConfig.IsEnabled = $false

    # On attache l'invalidation aux changements de sélection
    if ($Ctrl.CbSites) { $Ctrl.CbSites.Add_SelectionChanged($InvalidateState) }
    if ($Ctrl.CbLibs) { $Ctrl.CbLibs.Add_SelectionChanged($InvalidateState) }
    if ($Ctrl.CbTemplates) { $Ctrl.CbTemplates.Add_SelectionChanged($InvalidateState) }
    
    # --- VALIDATION ---
    if ($Ctrl.BtnValidate) {
        $Ctrl.BtnValidate.Add_Click({
                Write-AppLog -Message "🔍 Démarrage de la vérification du modèle (Niveau 1)..." -Level Info -RichTextBox $Ctrl.LogBox
            
                # Reset avant check
                $Ctrl.BtnDeploy.IsEnabled = $false
                $ValidationState.IsValid = $false
                & $UpdateSaveState
                
                $selTemplate = $Ctrl.CbTemplates.SelectedItem
                if (-not $selTemplate) {
                    Write-AppLog -Message "⚠️ Aucun modèle sélectionné." -Level Warning -RichTextBox $Ctrl.LogBox
                 
                    # Tentative de reload de la dernière chance
                    try {
                        $templates = @(Get-AppSPTemplates)
                        if ($templates.Count -gt 0) {
                            $Ctrl.CbTemplates.ItemsSource = $templates
                            $Ctrl.CbTemplates.DisplayMemberPath = "DisplayName"
                            $Ctrl.CbTemplates.SelectedIndex = 0
                            $selTemplate = $templates[0]
                            Write-AppLog -Message "✅ Modèles rechargés. Utilisation de '$($selTemplate.DisplayName)'." -Level Success -RichTextBox $Ctrl.LogBox
                        }
                    }
                    catch {}

                    if (-not $selTemplate) { return }
                }

                try {
                    $structure = $selTemplate.StructureJson | ConvertFrom-Json
                
                    # S'assurer que la fonction est dispo
                    if (-not (Get-Command "Test-AppSPModel" -ErrorAction SilentlyContinue)) {
                        Import-Module (Join-Path $Global:ProjectRoot "Modules\Toolbox.SharePoint") -Force
                    }

                    # --- PRÉPARATION VALIDATION ---
                    $params = @{ StructureData = $structure }
                
                    # Récupération Connexion (Niveau 2)
                    $conn = $Global:AppSharePointConnection
                
                    # Si pas de connexion active, tentative de connexion à la volée sur le SITE CIBLE
                    if (-not $conn -or $conn.Url -ne $Ctrl.CbSites.SelectedItem.Url) {
                        $tgtSite = $Ctrl.CbSites.SelectedItem
                        if ($tgtSite -and $tgtSite.Url) {
                            try {
                                Write-AppLog -Message "🌍 Connexion PnP au site cible ($($tgtSite.Url))..." -Level Info -RichTextBox $Ctrl.LogBox
                            
                                $clientId = $Global:AppConfig.azure.authentication.userAuth.appId
                                $thumb = $Global:AppConfig.azure.certThumbprint
                                $tenant = $Global:AppConfig.azure.tenantName
                            
                                # Connexion directe au site
                                $conn = Connect-PnPOnline -Url $tgtSite.Url -ClientId $clientId -Thumbprint $thumb -Tenant $tenant -ReturnConnection -ErrorAction Stop
                                $Global:AppSharePointConnection = $conn
                            }
                            catch {
                                Write-AppLog -Message "⚠️ Echec de connexion PnP : $($_.Exception.Message). Repli sur validation statique." -Level Warning -RichTextBox $Ctrl.LogBox
                            }
                        }
                    }

                    # Niveau 2 : Si connecté
                    if ($conn) {
                        Write-AppLog -Message "🌍 Connexion active : Activation validation Niveau 2 (Utilisateurs & Bibliothèque)." -Level Info -RichTextBox $Ctrl.LogBox
                        $params.Connection = $conn
                    
                        if ($Ctrl.CbLibs.SelectedItem -and $Ctrl.CbLibs.SelectedItem -isnot [string]) {
                            $params.TargetLibraryName = $Ctrl.CbLibs.SelectedItem.Title
                        }
                    }
                    else {
                        Write-AppLog -Message "☁️ Pas de connexion active : Validation Statique (Niveau 1) uniquement." -Level Info -RichTextBox $Ctrl.LogBox
                    }    

                    $issues = Test-AppSPModel @params
                
                    if ($issues.Count -eq 0) {
                        Write-AppLog -Message "✅ Validation Réussie : Aucune erreur détectée." -Level Success -RichTextBox $Ctrl.LogBox
                        
                        # SUCCESS : Activation des boutons
                        $ValidationState.IsValid = $true
                        $Ctrl.BtnDeploy.IsEnabled = $true
                        & $UpdateSaveState # Active BtnSaveConfig si tout est OK
                    }
                    else {
                        $errCount = ($issues | Where-Object { $_.Status -eq 'Error' }).Count
                        if ($errCount -gt 0) {
                            Write-AppLog -Message "❌ Validation Échouée ($errCount erreurs) :" -Level Error -RichTextBox $Ctrl.LogBox
                        }
                        else {
                            Write-AppLog -Message "⚠️ Validation Terminée avec Avertissements :" -Level Warning -RichTextBox $Ctrl.LogBox
                            # WARNING : On autorise quand même le déploiement ? 
                            # Politique habituelle : Warning OK, Error KO.
                            $ValidationState.IsValid = $true
                            $Ctrl.BtnDeploy.IsEnabled = $true
                            & $UpdateSaveState
                        }

                        foreach ($issue in $issues) {
                            $icon = switch ($issue.Status) { "Error" { "❌" } "Warning" { "⚠️" } Default { "ℹ️" } }
                            # Mapping niveau de log
                            $logLvl = switch ($issue.Status) { "Error" { "Error" } "Warning" { "Warning" } Default { "Info" } }
                            Write-AppLog -Message "   $icon [$($issue.NodeName)] : $($issue.Message)" -Level $logLvl -RichTextBox $Ctrl.LogBox
                        }
                    }

                }
                catch {
                    Write-AppLog -Message "💥 Erreur technique lors de la validation : $($_.Exception.Message)" -Level Error -RichTextBox $Ctrl.LogBox
                }
            }.GetNewClosure())
    }

    $Ctrl.BtnDeploy.Add_Click({
            $Ctrl.BtnDeploy.IsEnabled = $false
            $Ctrl.ProgressBar.IsIndeterminate = $true
            $Ctrl.TxtStatus.Text = "Déploiement en cours..."
        
            Write-AppLog -Message "Démarrage déploiement..." -Level Info -RichTextBox $Ctrl.LogBox

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
                LibRelUrl     = if ($Global:SelectedTargetFolder) { $Global:SelectedTargetFolder.ServerRelativeUrl } else { $Ctrl.CbLibs.SelectedItem.RootFolder.ServerRelativeUrl }
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
                        -TenantName $ArgsMap.Tenant `
                        -TargetFolderUrl $ArgsMap.LibRelUrl
                }
                catch { throw $_ }
            } -ArgumentList $jobArgs
        
            $timer = New-Object System.Windows.Threading.DispatcherTimer
            $timer.Interval = [TimeSpan]::FromMilliseconds(500)
            
            # État partagé pour capturer le résultat final à travers les ticks
            $SharedState = @{ FinalResult = $null }

            $timerBlock = {
                # 1. UI References
                $fLog = $Window.FindName("LogRichTextBox")
                $fProg = $Window.FindName("MainProgressBar")
                $fStat = $Window.FindName("ProgressStatusText")
                $fBtn = $Window.FindName("DeployButton")
                $fCopy = $Window.FindName("CopyUrlButton")
                $fOpen = $Window.FindName("OpenUrlButton")

                # 2. Consommation en temps réel (Streaming)
                $newItems = Receive-Job -Job $job
                
                foreach ($item in $newItems) {
                    # A. LOG STRUCTURE (Write-AppLog -PassThru)
                    # On détecte la propriété LogType = 'AppLog'
                    if ($item.PSObject.Properties['LogType'] -and $item.LogType -eq 'AppLog') {
                        if ($fLog) { Write-AppLog -Message $item.Message -Level $item.Level -RichTextBox $fLog }
                    }
                    # B. LOG STRING (Legacy "LEVEL|Message")
                    elseif ($item -is [string]) {
                        # Format attendu : "LEVEL|Message"
                        $parts = $item -split '\|', 2
                        $lvl = if ($parts.Count -eq 2) { $parts[0] } else { "INFO" }
                        $msg = if ($parts.Count -eq 2) { $parts[1] } else { $item }

                        # PROTECTION CRASH : Ignorer message vide
                        if (-not [string]::IsNullOrWhiteSpace($msg)) {
                            $color = switch ($lvl) { "DEBUG" { "Debug" } "INFO" { "Info" } "WARNING" { "Warning" } "ERROR" { "Error" } "SUCCESS" { "Success" } Default { "Info" } }
                            if ($fLog) { Write-AppLog -Message $msg -Level $color -RichTextBox $fLog }
                        }
                    }
                    # C. RESULTAT FINAL (PSCustomObject / Hashtable)
                    elseif ($item -is [System.Collections.IDictionary] -or $item -is [PSCustomObject]) {
                        # On s'assure que ce n'est PAS un log
                        if (-not $item.PSObject.Properties['LogType']) {
                            $SharedState.FinalResult = $item
                        }
                    }
                }

                # 3. Fin du Job
                if ($job.State -ne 'Running') {
                    $timer.Stop()
                    $finalRes = $SharedState.FinalResult

                    if ($fProg) { $fProg.IsIndeterminate = $false; $fProg.Value = 100 }

                    if ($job.State -eq 'Failed') {
                        $err = $job.ChildJobs[0].Error
                        if ($fLog) { Write-AppLog -Message "CRASH JOB : $err" -Level Error -RichTextBox $fLog }
                        if ($fStat) { $fStat.Text = "Erreur critique." }
                        if ($fBtn) { $fBtn.IsEnabled = $true }
                    } 
                    else {
                        # Succès ou Echec Logique
                        $success = $false
                        if ($finalRes -and $finalRes.Success) { $success = $true }

                        if ($success) {
                            if ($fStat) { $fStat.Text = "Déploiement réussi !" }
                            
                            # URL Finale
                            $uriSite = [Uri]$jobArgs.TargetUrl
                            $rootHost = "$($uriSite.Scheme)://$($uriSite.Host)"
                            $pathSuffix = if ($jobArgs.FolderName) { "/$($jobArgs.FolderName)" } else { "" }
                            # Attention : LibRelUrl commence déjà par /
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
                
                # 6. Vider le TreeView (Preview) et la Description
                if ($Ctrl.TreeView) { $Ctrl.TreeView.Items.Clear() }
                
                # 7. Vider l'Explorer TreeView (Etape 1) et Reset Selection
                $safeExpTv = $Window.FindName("TargetExplorerTreeView")
                if ($safeExpTv) { 
                    $safeExpTv.Items.Clear() 
                    # Restaurer le placeholder
                    $ph = New-Object System.Windows.Controls.TreeViewItem
                    $ph.Header = "Veuillez sélectionner une bibliothèque..."
                    $ph.SetResourceReference([System.Windows.Controls.Control]::ForegroundProperty, "TextDisabledBrush")
                    $ph.FontStyle = 'Italic'
                    $ph.IsEnabled = $false
                    $ph.SetResourceReference([System.Windows.Controls.TreeViewItem]::StyleProperty, "ModernTreeViewItemStyle")
                    $safeExpTv.Items.Add($ph)
                }
                $Global:SelectedTargetFolder = $null
                $st = $Window.FindName("TargetFolderStatusText")
                if ($st) { $st.Text = "" }

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
        

    # ==========================================================================
    # LOGIQUE DISCRÈTE D'AUTO-EXPANSION (RESTAURATION ARBRE)
    # ==========================================================================
    $AutoExpandState = [PSCustomObject]@{
        Timer       = $null
        TargetUrl   = ""
        CurrentItem = $null # Null = Racine du TreeView
    }

    $AutoExpandLogic = {
        # Sécurité : Si l'interface est fermée ou vide
        $tv = $Window.FindName("TargetExplorerTreeView")
        if (-not $tv) { 
            if ($AutoExpandState.Timer) { $AutoExpandState.Timer.Stop() }
            return 
        }

        # Déterminer la collection à scanner
        $itemsToCheck = if ($AutoExpandState.CurrentItem) { $AutoExpandState.CurrentItem.Items } else { $tv.Items }

        # 1. Vérifier si vide ou chargement
        if ($itemsToCheck.Count -eq 0) { return } # Attendre
        
        $firstChild = $itemsToCheck[0]
        $isDummy = ($firstChild.Tag -eq "DUMMY_TAG" -or $firstChild.Header -eq "Chargement...")
        
        if ($isDummy) { return } # Attendre fin du chargement

        # 2. Chercher la correspondance
        $foundNext = $false
        $target = $AutoExpandState.TargetUrl

        foreach ($item in $itemsToCheck) {
            $data = $item.Tag
            if ($data -and $data.ServerRelativeUrl) {
                $url = $data.ServerRelativeUrl
                
                # A. C'est la cible exacte !
                if ($url -eq $target) {
                    $item.IsSelected = $true
                    $item.BringIntoView()
                    $item.Focus()
                    if ($AutoExpandState.Timer) { $AutoExpandState.Timer.Stop() }
                    # & $Log "Arborescence restaurée." "Success"
                    return
                }

                # B. C'est un parent du chemin cible
                # On ajoute '/' pour éviter les faux amis (ex: /Site/Gen vs /Site/General)
                if ($target.StartsWith("$url/")) {
                    $item.IsExpanded = $true # Déclenche le Lazy Load
                    $AutoExpandState.CurrentItem = $item # On descend d'un niveau
                    $foundNext = $true
                    break # On sort du foreach, on attendra le chargement au prochain tick
                }
            }
        }

        # 3. Si on avait commencé à chercher (CurrentItem n'est pas null) mais qu'on ne trouve rien...
        # C'est que le chemin n'existe plus. On arrête.
        if (-not $foundNext -and $AutoExpandState.CurrentItem) {
            if ($AutoExpandState.Timer) { $AutoExpandState.Timer.Stop() }
            # & $Log "Impossible de restaurer tout le chemin." "Warning"
        }
    }.GetNewClosure()

    $StartAutoExpand = {
        param($Url)
        if ([string]::IsNullOrWhiteSpace($Url)) { return }

        # Stop existant
        if ($AutoExpandState.Timer) { $AutoExpandState.Timer.Stop() }

        # Init
        $AutoExpandState.TargetUrl = $Url
        $AutoExpandState.CurrentItem = $null

        # Timer
        $AutoExpandState.Timer = New-Object System.Windows.Threading.DispatcherTimer
        $AutoExpandState.Timer.Interval = [TimeSpan]::FromMilliseconds(500)
        $AutoExpandState.Timer.Add_Tick($AutoExpandLogic)
        $AutoExpandState.Timer.Start()
    }.GetNewClosure()


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

                # C. NOM & SECURITE (Nouveau Dialogue XAML)
                $dialogPath = Join-Path $Global:ProjectRoot "Templates\Dialogs\SaveConfigDialog.xaml"
                
                # Chargement sécurisé
                try {
                    [xml]$xamlContent = Get-Content $dialogPath
                    $xamlReader = New-Object System.Xml.XmlNodeReader $xamlContent
                    $dialogWin = [System.Windows.Markup.XamlReader]::Load($xamlReader)

                    # INJECTION DES STYLES GLOBAUX (Couleurs, Boutons, Typography...)
                    # Cela permet d'utiliser {DynamicResource PrimaryButtonStyle} dans le dialogue isolé
                    if (Get-Command "Initialize-AppUIComponents" -ErrorAction SilentlyContinue) {
                        Initialize-AppUIComponents -Window $dialogWin -ProjectRoot $Global:ProjectRoot -Components 'Buttons', 'Inputs', 'Layouts', 'Display', 'Typography', 'Colors'
                    }
                }
                catch {
                    [System.Windows.MessageBox]::Show("Impossible de charger le dialogue de sauvegarde.`n$($_.Exception.Message)", "Erreur interne", "OK", "Error")
                    return
                }

                # Références contrôles
                $tName = $dialogWin.FindName("ConfigNameBox")
                $container = $dialogWin.FindName("GroupsContainer")
                $bSave = $dialogWin.FindName("BtnSave")
                
                # Config par défaut
                $defaultName = "Deploy-$($Ctrl.CbSites.SelectedItem.SiteName)-$libName"
                
                # Si on est en train d'éditer une config existante (déjà sélectionnée), on pré-remplit
                if ($Ctrl.CbDeployConfigs.SelectedItem) {
                    $defaultName = $Ctrl.CbDeployConfigs.SelectedItem.ConfigName
                }
                $tName.Text = $defaultName

                # --- CHARGEMENT DYNAMIQUE DES GROUPES ---
                # On récupère les groupes connus en BDD
                $knownGroups = @(Get-AppKnownGroups)
                
                # Si aucun groupe en base, on en met par défaut pour ne pas avoir une UI vide
                if ($knownGroups.Count -eq 0) {
                    $knownGroups = @(
                        [PSCustomObject]@{ GroupName = "M365_APPS_SCRIPTS_ADMIN" },
                        [PSCustomObject]@{ GroupName = "M365_APPS_SCRIPTS_DP" },
                        [PSCustomObject]@{ GroupName = "M365_APPS_SCRIPTS_USER" }
                    )
                }

                # On garde une référence aux CheckBoxes générées
                $checkBoxes = @()

                foreach ($grp in $knownGroups) {
                    # Structure : Border > Grid > (Column 0: CheckBox, Column 1: StackPanel(Texts))
                    
                    # 1. BORDER CONTAINER
                    $border = New-Object System.Windows.Controls.Border
                    $border.BorderThickness = [System.Windows.Thickness]::new(1)
                    $border.CornerRadius = [System.Windows.CornerRadius]::new(6)
                    $border.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
                    $border.Padding = [System.Windows.Thickness]::new(10)
                    
                    # Styles - Fallback manuel si ressource introuvable
                    if ($dialogWin.Resources.Contains("BackgroundLightBrush")) {
                        $border.Background = $dialogWin.Resources["BackgroundLightBrush"]
                    }
                    else {
                        $border.Background = [System.Windows.Media.Brushes]::GhostWhite
                    }
                    if ($dialogWin.Resources.Contains("BorderLightBrush")) {
                        $border.BorderBrush = $dialogWin.Resources["BorderLightBrush"]
                    }
                    else {
                        $border.BorderBrush = [System.Windows.Media.Brushes]::LightGray
                    }

                    # 2. GRID layout
                    $grid = New-Object System.Windows.Controls.Grid
                    $grid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::Auto })) # CheckBox
                    $grid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) })) # Texte

                    # 3. CHECKBOX (Toggle Switch)
                    $chk = New-Object System.Windows.Controls.CheckBox
                    $chk.Tag = $grp.GroupName  # Stockage de la donnée ici
                    # $chk.Content = $grp.GroupName # Optionnel si le style ne l'affiche pas
                    $chk.IsChecked = $true 
                    $chk.Margin = [System.Windows.Thickness]::new(0, 0, 15, 0)
                    $chk.VerticalAlignment = "Center"
                    
                    # Application du Style Global (Switch)
                    if ($dialogWin.Resources.Contains("ToggleSwitchStyle")) {
                        $chk.Style = $dialogWin.Resources["ToggleSwitchStyle"]
                    }

                    [System.Windows.Controls.Grid]::SetColumn($chk, 0)
                    $grid.Children.Add($chk)

                    # 4. TEXTES (Layout type Launcher)
                    $stackText = New-Object System.Windows.Controls.StackPanel
                    $stackText.VerticalAlignment = "Center"
                    [System.Windows.Controls.Grid]::SetColumn($stackText, 1)

                    # Titre (Nom du groupe)
                    $txtName = New-Object System.Windows.Controls.TextBlock
                    $txtName.Text = $grp.GroupName
                    $txtName.FontWeight = "SemiBold"
                    $txtName.FontSize = 12
                    if ($dialogWin.Resources.Contains("TextPrimaryBrush")) { $txtName.Foreground = $dialogWin.Resources["TextPrimaryBrush"] }

                    # Sous-titre
                    $txtSub = New-Object System.Windows.Controls.TextBlock
                    $txtSub.Text = "Groupe Azure AD" 
                    $txtSub.FontSize = 10
                    if ($dialogWin.Resources.Contains("TextSecondaryBrush")) { $txtSub.Foreground = $dialogWin.Resources["TextSecondaryBrush"] }

                    $stackText.Children.Add($txtName)
                    $stackText.Children.Add($txtSub)
                    $grid.Children.Add($stackText)

                    # Assemblage
                    $border.Child = $grid
                    $container.Children.Add($border)
                    
                    # Ajout à la liste pour récupération ultérieure
                    $checkBoxes += $chk
                }

                # --- LOGIQUE DIALOGUE ---
                $dialogWin.Owner = $Window
                $dialogWin.SizeToContent = "Height" # Auto-adjust height
                
                # Event Save
                $bSave.Add_Click({
                        $finalName = $tName.Text

                        # 1. Validation Nom
                        if ([string]::IsNullOrWhiteSpace($finalName)) {
                            [System.Windows.MessageBox]::Show("Le nom est obligatoire.", "Validation", "OK", "Warning")
                            return
                        }

                        # 2. Check Overwrite (Sauf si c'est le même nom qu'avant pour une update)
                        if (Get-Command "Test-AppDeployConfigExists" -ErrorAction SilentlyContinue) {
                            if (Test-AppDeployConfigExists -ConfigName $finalName) {
                                # Si c'est le même nom que la config courante, on suppose que c'est une MAJ normale sans warning
                                $isSame = ($Ctrl.CbDeployConfigs.SelectedItem -and $Ctrl.CbDeployConfigs.SelectedItem.ConfigName -eq $finalName)
                                
                                if (-not $isSame) {
                                    $res = [System.Windows.MessageBox]::Show("La configuration '$finalName' existe déjà.`nVoulez-vous l'écraser ?", "Confirmation", "YesNo", "Warning")
                                    if ($res -ne "Yes") { return }
                                }
                            }
                        }

                        $dialogWin.DialogResult = $true
                        $dialogWin.Close()
                    })

                # Affichage Modal
                if ($dialogWin.ShowDialog() -eq $true) {
                    $confName = $tName.Text

                    # Récupération DYNAMIQUE des Rôles cochés
                    $roles = @()
                    foreach ($c in $checkBoxes) {
                        if ($c.IsChecked) { $roles += $c.Tag } # Utilisation du Tag au lieu du Content
                    }
                    $rolesString = $roles -join ","

                    try {
                        # Capture du dossier cible sélectionné (Step 1)
                        $selPath = if ($Global:SelectedTargetFolder) { $Global:SelectedTargetFolder.ServerRelativeUrl } else { "" }
                        
                        Set-AppDeployConfig -ConfigName $confName `
                            -SiteUrl $siteUrl `
                            -LibraryName $libName `
                            -TargetFolder $targetFolder `
                            -OverwritePermissions $overwrite `
                            -TemplateId $tplId `
                            -TargetFolderPath $selPath `
                            -AuthorizedRoles $rolesString
                        
                        # Refresh UI
                        & $LoadDeployConfigs
                        [System.Windows.MessageBox]::Show("Configuration '$confName' sauvegardée avec succès.", "Succès", "OK", "Information")
                    }
                    catch {
                        [System.Windows.MessageBox]::Show("Erreur sauvegarde : $($_.Exception.Message)", "Erreur", "OK", "Error")
                    }
                }
                # Si Cancel, on ne fait rien.
                return
                
                # Ancien Code (Ignoré)
                # $confName = [Microsoft.VisualBasic.Interaction]::InputBox...
                if ($false) {
                
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

                    # F. Restauration Dossier Cible (Step 1)
                    # On vérifie la propriété dynamiquement au cas où la colonne manque (vieux cache ?)
                    if ($cfg.PSObject.Properties['TargetFolderPath'] -and -not [string]::IsNullOrWhiteSpace($cfg.TargetFolderPath)) {
                        $path = $cfg.TargetFolderPath
                        # On simule l'objet dossier pour le déploiement
                        $Global:SelectedTargetFolder = [PSCustomObject]@{ ServerRelativeUrl = $path }
                         
                        # Mise à jour visuelle (Status Text seulement, car TreeView est async)
                        $st = $Window.FindName("TargetFolderStatusText")
                        if ($st) { $st.Text = $path }
                         
                        & $Log "Cible restaurée : $path" "Info"

                        # Lancement Autopilot Visuel
                        if ($StartAutoExpand) { & $StartAutoExpand $path }
                    }
                    else {
                        # Reset si pas de cible sauvegardée
                        $Global:SelectedTargetFolder = $null
                        $st = $Window.FindName("TargetFolderStatusText")
                        if ($st) { $st.Text = "" }
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