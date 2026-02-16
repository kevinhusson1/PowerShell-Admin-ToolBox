# Scripts/SharePoint/SharePointBuilder/Functions/Logic/Register-SiteEvents.ps1

<#
.SYNOPSIS
    Gère le chargement et la sélection des Sites et Bibliothèques SharePoint.

.DESCRIPTION
    Pilote la récupération asynchrone (via Start-Job) de la liste des sites disponibles.
    Gère le mode Autopilot (sélection automatique si contexte fourni) et le mode Manuel (liste déroulante).
    Au changement de site, déclenche le chargement asynchrone des bibliothèques associées.

.PARAMETER Ctrl
    La Hashtable des contrôles UI.

.PARAMETER PreviewLogic
    ScriptBlock de validation pour mettre à jour l'état du formulaire.

.PARAMETER Window
    La fenêtre WPF principale.

.PARAMETER Context
    Hashtable contextuel (Autopilot, etc.).
#>
function Register-SiteEvents {
    param(
        [hashtable]$Ctrl,
        [scriptblock]$PreviewLogic,
        [System.Windows.Window]$Window,
        [hashtable]$Context
    )

    # Capture Locale pour Closure (Correction)
    $GetLoc = Get-Command Get-AppLocalizedString -ErrorAction SilentlyContinue

    # Helper Pagination : Rendu par lot
    $RenderBatchBlock = {
        param($ParentNode)
        
        $tag = $ParentNode.Tag
        # Vérification si le Tag a les propriétés de cache (via PSObject member check)
        if (-not $tag.PSObject.Properties['CachedChildren']) { return }

        $children = $tag.CachedChildren
        $count = $children.Count
        $offset = $tag.RenderedCount 
        $pageSize = 10
        
        # Calculer la fin du lot
        $endIndex = [Math]::Min($offset + $pageSize, $count)
        
        # 1. Retirer le bouton "Load More" s'il existe (c'est toujours le dernier visuellement)
        if ($ParentNode.Items.Count -gt 0) {
            $last = $ParentNode.Items[$ParentNode.Items.Count - 1]
            if ($last -is [System.Windows.Controls.TreeViewItem] -and $last.Tag -eq "ACTION_LOAD_MORE") {
                $ParentNode.Items.Remove($last)
            }
        }

        # 2. Rendu des items
        for ($i = $offset; $i -lt $endIndex; $i++) {
            $folder = $children[$i]
            if ($folder.Name -eq "Forms") { continue } # Filtre système

            $newItem = New-Object System.Windows.Controls.TreeViewItem
            $newItem.SetResourceReference([System.Windows.Controls.TreeViewItem]::StyleProperty, "ModernTreeViewItemStyle")
            
            # Header
            $stack = New-Object System.Windows.Controls.StackPanel
            $stack.Orientation = "Horizontal"
            
            $txtIcon = New-Object System.Windows.Controls.TextBlock
            $txtIcon.Text = "📁"
            $txtIcon.SetResourceReference([System.Windows.Controls.TextBlock]::StyleProperty, "TreeItemIconStyle") 
            $stack.Children.Add($txtIcon)

            $txt = New-Object System.Windows.Controls.TextBlock
            $txt.Text = $folder.Name
            $stack.Children.Add($txt)
            
            $newItem.Header = $stack
            $newItem.Tag = $folder # Data brute
            
            # Dummy pour Lazy Loading
            $dummy = New-Object System.Windows.Controls.TreeViewItem
            $dummy.Header = "Chargement..."
            $dummy.FontStyle = "Italic"
            $dummy.Foreground = [System.Windows.Media.Brushes]::Gray
            $dummy.IsEnabled = $false
            $dummy.Tag = "DUMMY_TAG"
            $newItem.Items.Add($dummy)
            
            $ParentNode.Items.Add($newItem)
        }

        # 3. Mise à jour Offset
        $tag.RenderedCount = $endIndex

        # 4. Ajouter "Load More" si reste
        if ($endIndex -lt $count) {
            $remaining = $count - $endIndex
            $moreItem = New-Object System.Windows.Controls.TreeViewItem
            $moreItem.Header = "Charger la suite (+ $remaining) ..."
            $moreItem.Tag = "ACTION_LOAD_MORE"
            $moreItem.Foreground = [System.Windows.Media.Brushes]::DodgerBlue
            $moreItem.FontWeight = "SemiBold"
            $moreItem.Cursor = "Hand"
            $ParentNode.Items.Add($moreItem)
        }
    }.GetNewClosure()

    $Global:AllSharePointSites = @()
    
    # Paramètres de base pour traverser la frontière du Job
    $baseArgs = @{
        ModPath  = Join-Path $Global:ProjectRoot "Modules\Toolbox.SharePoint"
        Thumb    = $Global:AppConfig.azure.certThumbprint
        ClientId = $Global:AppConfig.azure.authentication.userAuth.appId
        Tenant   = $Global:AppConfig.azure.tenantName
    }

    # ==========================================================================
    # BRANCHE 1 : MODE AUTOPILOT (inchangé car fonctionnel)
    # ==========================================================================
    if (-not [string]::IsNullOrWhiteSpace($Context.AutoSiteUrl)) {
        
        $Ctrl.CbSites.IsEnabled = $false
        $Ctrl.CbLibs.IsEnabled = $false
        Write-AppLog -Message "Autopilot : Vérification..." -Level Info -RichTextBox $Ctrl.LogBox

        $autoArgs = $baseArgs.Clone()
        $autoArgs.TargetSiteUrl = $Context.AutoSiteUrl
        $autoArgs.TargetLibName = $Context.AutoLibraryName

        $jobAuto = Start-Job -ScriptBlock {
            param($ArgsMap)
            Import-Module $ArgsMap.ModPath -Force
            try {
                $conn = Connect-AppSharePoint -ClientId $ArgsMap.ClientId -Thumbprint $ArgsMap.Thumb -TenantName $ArgsMap.Tenant -SiteUrl $ArgsMap.TargetSiteUrl
                if (-not $conn) { throw "Impossible de se connecter au site." }

                $web = Get-PnPWeb -Connection $conn
                $siteObj = [PSCustomObject]@{ Title = $web.Title; Url = $web.Url; Id = $web.Id }

                $libObj = $null
                if ($ArgsMap.TargetLibName) {
                    $lib = Get-PnPList -Identity $ArgsMap.TargetLibName -Connection $conn -ErrorAction Stop
                    if ($lib) {
                        $libObj = [PSCustomObject]@{ Title = $lib.Title; Id = $lib.Id; RootFolder = $lib.RootFolder }
                    }
                }
                return [PSCustomObject]@{ Site = $siteObj; Lib = $libObj }
            }
            catch { throw $_ }
        } -ArgumentList $autoArgs

        $autoJobId = $jobAuto.Id

        $timerAuto = New-Object System.Windows.Threading.DispatcherTimer
        $timerAuto.Interval = [TimeSpan]::FromMilliseconds(500)
        
        $timerAutoBlock = {
            $j = Get-Job -Id $autoJobId -ErrorAction SilentlyContinue
            if ($j -and $j.State -ne 'Running') {
                $timerAuto.Stop()
                
                $safeCbSites = $Window.FindName("SiteComboBox")
                $safeCbLibs = $Window.FindName("LibraryComboBox")
                $safeLog = $Window.FindName("LogRichTextBox")
                if ($null -eq $safeCbSites) { return }

                $res = Receive-Job $j -Wait -AutoRemoveJob
                
                if ($j.State -eq 'Failed') {
                    $err = $j.ChildJobs[0].Error
                    Write-AppLog -Message "Erreur Autopilot : $err" -Level Error -RichTextBox $safeLog
                    $safeCbSites.ItemsSource = @("Echec Autopilot")
                } 
                else {
                    $site = $res.Site
                    $safeCbSites.ItemsSource = @($site)
                    $safeCbSites.DisplayMemberPath = "Title"
                    $safeCbSites.SelectedItem = $site
                    Write-AppLog -Message "Site validé : '$($site.Title)'" -Level Success -RichTextBox $safeLog

                    if ($res.Lib) {
                        $lib = $res.Lib
                        $safeCbLibs.ItemsSource = @($lib)
                        $safeCbLibs.DisplayMemberPath = "Title"
                        $safeCbLibs.SelectedItem = $lib
                        $libUrl = "$($site.Url)$($lib.RootFolder.ServerRelativeUrl)"
                        Write-AppLog -Message "Bibliothèque validée : '$($lib.Title)'" -Level Success -RichTextBox $safeLog
                    }
                    else {
                        Write-AppLog -Message "Bibliothèque introuvable : $($Context.AutoLibraryName)" -Level Warning -RichTextBox $safeLog
                    }

                    if ($null -ne $PreviewLogic) { & $PreviewLogic }
                }
            }
        }.GetNewClosure()

        $timerAuto.Add_Tick($timerAutoBlock)
        $timerAuto.Start()

    } 
    # ==========================================================================
    # BRANCHE 2 : MODE MANUEL (Correction et Debug)
    # ==========================================================================
    else {
        $Ctrl.CbSites.ItemsSource = @("Chargement des sites en cours...")
        Write-AppLog -Message "Démarrage : Récupération de la liste des sites..." -Level Info -RichTextBox $Ctrl.LogBox
        
        # Show Loader
        $siteLoader = $Window.FindName("SiteLoadingBar")
        if ($siteLoader) { $siteLoader.Visibility = "Visible" }

        # LOG 1 : Vérification des paramètres avant envoi
        Write-Verbose "[DEBUG] Params envoyés au Job : ClientId=$($baseArgs.ClientId), Tenant=$($baseArgs.Tenant), Thumb=$($baseArgs.Thumb)"

        $jobSites = Start-Job -ScriptBlock {
            param($ArgsMap)
            
            # LOG 2 : Intérieur du Job (Début)
            Write-Output "JOB_LOG: Démarrage du Job. Import du module depuis $($ArgsMap.ModPath)..."
            
            try {
                Import-Module $ArgsMap.ModPath -Force
                Write-Output "JOB_LOG: Module importé. Tentative de connexion (Get-AppSPSites)..."
                
                # Exécution
                $result = Get-AppSPSites -ClientId $ArgsMap.ClientId -Thumbprint $ArgsMap.Thumb -TenantName $ArgsMap.Tenant
                
                $count = if ($result) { $result.Count } else { 0 }
                Write-Output "JOB_LOG: Commande terminée. $count sites trouvés."
                
                return $result
            }
            catch {
                # LOG 3 : Erreur fatale dans le Job
                Write-Output "JOB_ERROR: $($_.Exception.Message)"
                throw $_
            }
        } -ArgumentList $baseArgs

        $siteJobId = $jobSites.Id
        Write-Verbose "[DEBUG] Job lancé avec ID: $siteJobId"

        $timerSites = New-Object System.Windows.Threading.DispatcherTimer
        $timerSites.Interval = [TimeSpan]::FromMilliseconds(500)
        
        $timerSitesBlock = {
            $j = Get-Job -Id $siteJobId -ErrorAction SilentlyContinue
            
            # LOG 4 : État du Job à chaque tick
            if ($j) { Write-Verbose "[TimerTick] Job State: $($j.State)" }
            else { Write-Verbose "[TimerTick] Job introuvable !" }

            if ($j -and $j.State -ne 'Running') {
                $timerSites.Stop()
                
                $safeCb = $Window.FindName("SiteComboBox")
                $safeLog = $Window.FindName("LogRichTextBox")
                $siteLoader = $Window.FindName("SiteLoadingBar")
                if ($siteLoader) { $siteLoader.Visibility = "Collapsed" }

                if ($null -eq $safeCb) { return }

                # Récupération de TOUT (Logs + Objets)
                $rawResults = Receive-Job $j -Wait -AutoRemoveJob
                
                # Séparation Logs vs Données
                $debugLogs = $rawResults | Where-Object { $_ -is [string] -and ($_ -like "JOB_*") }
                $realData = $rawResults | Where-Object { $_ -isnot [string] -or ($_ -notlike "JOB_*") }

                # Affichage des logs internes du Job dans la console Verbose
                foreach ($line in $debugLogs) { 
                    Write-Verbose ">> $line" 
                    # Optionnel : Afficher aussi les erreurs internes dans la RichTextBox
                    if ($line -like "JOB_ERROR*") {
                        Write-AppLog -Message $line -Level Error -RichTextBox $safeLog
                    }
                }

                if ($j.State -eq 'Failed') {
                    $err = $j.ChildJobs[0].Error
                    $safeCb.ItemsSource = @("Erreur de chargement")
                    Write-AppLog -Message "JOB FAILED : $err" -Level Error -RichTextBox $safeLog
                }
                else {
                    $sitesArray = @($realData)
                    $Global:AllSharePointSites = $sitesArray
                    
                    if ($sitesArray.Count -gt 0) {
                        $safeCb.ItemsSource = $sitesArray
                        $safeCb.DisplayMemberPath = "Title"
                        $safeCb.IsEnabled = $true
                        Write-AppLog -Message "$($sitesArray.Count) sites chargés." -Level Success -RichTextBox $safeLog
                        
                        # UPDATE ETAT BOUTON LOAD CONFIG
                        # Si une config était déjà sélectionnée pendant le chargement, on active le bouton maintenant
                        $btnLoad = $Window.FindName("LoadConfigButton")
                        $cbConfig = $Window.FindName("DeployConfigComboBox")
                        if ($btnLoad -and $cbConfig -and $cbConfig.SelectedItem) {
                            $btnLoad.IsEnabled = $true
                        }
                    }
                    else {
                        $safeCb.ItemsSource = @("Aucun site trouvé")
                        Write-AppLog -Message "Résultat vide (0 sites)." -Level Warning -RichTextBox $safeLog
                    }
                }
            }
        }.GetNewClosure() # Capture $siteJobId

        $timerSites.Add_Tick($timerSitesBlock)
        $timerSites.Start()

        # --- RESTE DU FICHIER (Events manuels KeyUp, SelectionChanged...) ---
        # Je remets le code de filtrage et chargement lib ici pour que ce soit complet
        
        # B. FILTRAGE AVEC DEBOUNCE (Anti-Freeze)
        $searchTimer = New-Object System.Windows.Threading.DispatcherTimer
        $searchTimer.Interval = [TimeSpan]::FromMilliseconds(500)
        $searchTimer.Tag = "SEARCH_TIMER" # Marker
        
        $searchAction = {
            $searchTimer.Stop()
            $cb = $Ctrl.CbSites
            $filterText = $cb.Text
            
            # Run filtering in background/idle to not block? 
            # Actually filtering an array is fast, it's the UI update that might lag if too frequent.
            
            if ($Global:AllSharePointSites) {
                if ([string]::IsNullOrWhiteSpace($filterText)) {
                    $cb.ItemsSource = $Global:AllSharePointSites
                }
                else {
                    $filtered = $Global:AllSharePointSites | Where-Object { $_.Title -like "*$filterText*" }
                    $cb.ItemsSource = @($filtered)
                }
                $cb.IsDropDownOpen = $true
            }
        }.GetNewClosure()

        $searchTimer.Add_Tick($searchAction)

        $Ctrl.CbSites.Add_KeyUp({
                param($sender, $e)
                if ($e.Key -in 'Up', 'Down', 'Enter', 'Tab', 'Left', 'Right') { return }
                
                # Restart Timer
                $searchTimer.Stop()
                $searchTimer.Start()
            }.GetNewClosure())

        # --- C. SÉLECTION SITE -> CHARGEMENT LIBS ---
        $Ctrl.CbSites.Add_SelectionChanged({
                $site = $this.SelectedItem
                if ($site -is [System.Management.Automation.PSCustomObject]) {
                
                    $uiLog = $Window.FindName("LogRichTextBox")
                    if ($uiLog) {
                        Write-AppLog -Message "Site sélectionné : '$($site.Title)'" -Level Info -RichTextBox $uiLog
                        Write-AppLog -Message "URL : $($site.Url)" -Level Info -RichTextBox $uiLog
                    }

                    $safeLibCb = $Window.FindName("LibraryComboBox")
                    $libLoader = $Window.FindName("LibLoadingBar")
                    if ($safeLibCb) {
                        $safeLibCb.ItemsSource = @("Chargement...")
                        $safeLibCb.IsEnabled = $false
                    }
                    if ($libLoader) { $libLoader.Visibility = "Visible" }

                    # RESET TREEVIEW & SELECTION
                    $safeTv = $Window.FindName("TargetExplorerTreeView")
                    if ($safeTv) {
                        $safeTv.Items.Clear()
                        # Restauration Placeholder
                        $ph = New-Object System.Windows.Controls.TreeViewItem
                        $ph.Header = "Veuillez sélectionner une bibliothèque..."
                        $ph.SetResourceReference([System.Windows.Controls.Control]::ForegroundProperty, "TextDisabledBrush")
                        $ph.FontStyle = "Italic"
                        $ph.IsEnabled = $false
                        $ph.SetResourceReference([System.Windows.Controls.TreeViewItem]::StyleProperty, "ModernTreeViewItemStyle") # Cohérence
                        $safeTv.Items.Add($ph)
                    }
                    $Global:SelectedTargetFolder = $null
                    $st = $Window.FindName("TargetFolderStatusText")
                    if ($st) { $st.Text = "" }

                    # CLONAGE ARGUMENTS
                    $libArgs = $baseArgs.Clone()
                    $libArgs.SiteUrl = $site.Url

                    $jobLibs = Start-Job -ScriptBlock {
                        param($ArgsMap)
                        Import-Module $ArgsMap.ModPath -Force
                        try {
                            $conn = Connect-AppSharePoint -ClientId $ArgsMap.ClientId -Thumbprint $ArgsMap.Thumb -TenantName $ArgsMap.Tenant -SiteUrl $ArgsMap.SiteUrl
                            return Get-AppSPLibraries -Connection $conn
                        }
                        catch { throw $_ }
                    } -ArgumentList $libArgs

                    $libJobId = $jobLibs.Id

                    $timerLibs = New-Object System.Windows.Threading.DispatcherTimer
                    $timerLibs.Interval = [TimeSpan]::FromMilliseconds(200)
                
                    $timerLibsBlock = {
                        $j = Get-Job -Id $libJobId -ErrorAction SilentlyContinue

                        if ($j -and $j.State -ne 'Running') {
                            $timerLibs.Stop()
                        
                            $finalLibCb = $Window.FindName("LibraryComboBox")
                            $finalLog = $Window.FindName("LogRichTextBox")
                            $libLoader = $Window.FindName("LibLoadingBar")
                            if ($libLoader) { $libLoader.Visibility = "Collapsed" }
                            if ($null -eq $finalLibCb) { return }

                            $libs = Receive-Job $j -Wait -AutoRemoveJob
                        
                            if ($j.State -eq 'Failed') {
                                $errLib = $j.ChildJobs[0].Error
                                $finalLibCb.ItemsSource = @("Erreur")
                                if ($finalLog) { Write-AppLog -Message "Erreur Libs : $errLib" -Level Error -RichTextBox $finalLog }
                            }
                            elseif ($libs) {
                                $libArray = @($libs)
                                $finalLibCb.ItemsSource = $libArray
                                $finalLibCb.DisplayMemberPath = "Title"
                                $finalLibCb.IsEnabled = $true
                                if ($finalLog) { Write-AppLog -Message "Bibliothèques chargées." -Level Success -RichTextBox $finalLog }
                            }
                            else {
                                $finalLibCb.ItemsSource = @("Aucune bibliothèque")
                                if ($finalLog) { Write-AppLog -Message "Aucune bibliothèque trouvée." -Level Warning -RichTextBox $finalLog }
                            }
                        
                            if ($null -ne $PreviewLogic) { & $PreviewLogic } 
                        }
                    }.GetNewClosure()

                    $timerLibs.Add_Tick($timerLibsBlock)
                    $timerLibs.Start()
                }
            }.GetNewClosure())
    }

    # --- D. LOGIQUE EXPLORATEUR (Version Inline & Rapide) ---
    
    # 1. Helper Population Synchrone
    $PopulateNodeSync = {
        param($ParentNode, $FolderRelativeUrl, $Conn)
        
        $overlay = $Window.FindName("ExplorerLoadingOverlay")
        if ($overlay) { 
            $overlay.Visibility = "Visible" 
            # Force UI Refresh pour afficher le loader (car on est sur le thread UI)
            [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([Action] {}, [System.Windows.Threading.DispatcherPriority]::Render)
        }

        try {
            $ParentNode.Items.Clear() # Remove Dummy

            $subFolders = @()
            try {
                # Get-PnPFolder (Rapide via Connexion persistante)
                $pFolder = Get-PnPFolder -Url $FolderRelativeUrl -Connection $Conn -Includes Folders -ErrorAction Stop
                $subFolders = $pFolder.Folders | Where-Object { -not $_.Name.StartsWith("_") -and $_.Name -ne "Forms" }
            }
            catch {
                $err = $_
                # Log Error Visible (via Dispatcher si besoin, mais on est déjà sur UI thread)
                $log = $Window.FindName("LogRichTextBox")
                if ($log) { 
                    Write-AppLog -Message "Erreur lecture dossier '$FolderRelativeUrl': $err" -Level Warning -RichTextBox $log 
                }
            }

            foreach ($sub in $subFolders) {
                $newItem = New-Object System.Windows.Controls.TreeViewItem
                $newItem.SetResourceReference([System.Windows.Controls.TreeViewItem]::StyleProperty, "ModernTreeViewItemStyle")
                
                # Header
                $stack = New-Object System.Windows.Controls.StackPanel
                $stack.Orientation = "Horizontal"
                $txtIcon = New-Object System.Windows.Controls.TextBlock
                $txtIcon.Text = "📁"
                $txtIcon.SetResourceReference([System.Windows.Controls.TextBlock]::StyleProperty, "TreeItemIconStyle") 
                $stack.Children.Add($txtIcon)
                $txt = New-Object System.Windows.Controls.TextBlock
                $txt.Text = $sub.Name
                $stack.Children.Add($txt)
                
                $newItem.Header = $stack
                
                # Tag Data
                $newItem.Tag = [PSCustomObject]@{
                    Name              = $sub.Name
                    ServerRelativeUrl = $sub.ServerRelativeUrl
                }
                
                # Dummy for Lazy Load
                $dummy = New-Object System.Windows.Controls.TreeViewItem
                $dummy.Header = "Chargement..."
                $dummy.FontStyle = "Italic"
                $dummy.Tag = "DUMMY_TAG"
                $newItem.Items.Add($dummy)
                
                $ParentNode.Items.Add($newItem)
            }
        }
        catch {
            $critical = $_
            $log = $Window.FindName("LogRichTextBox")
            if ($log) { 
                Write-AppLog -Message "Crash PopulateNodeSync: $critical" -Level Error -RichTextBox $log 
            }
        }
        finally {
            if ($overlay) { 
                $overlay.Visibility = "Collapsed" 
                [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([Action] {}, [System.Windows.Threading.DispatcherPriority]::Render)
            }
        }
    }

    # Capture Ref pour Closure
    $RefPopulate = $PopulateNodeSync

    # 2. Event SÉLECTION BIBLIOTHÈQUE -> Connexion & Init Racine
    $Ctrl.CbLibs.Add_SelectionChanged({
            $lib = $this.SelectedItem
            $safeLog = $Window.FindName("LogRichTextBox")
            $safeSiteCb = $Window.FindName("SiteComboBox")
            $tv = $Window.FindName("TargetExplorerTreeView")
            $loader = $Window.FindName("LibLoadingBar")
            
            if ($lib -is [System.Management.Automation.PSCustomObject] -and $safeSiteCb.SelectedItem) {
                
                if ($safeLog) {
                    Write-AppLog -Message "Sélection Bibliothèque : '$($lib.Title)'" -Level Info -RichTextBox $safeLog
                }

                if ($tv) {
                    $tv.Items.Clear()
                    if ($loader) { $loader.Visibility = "Visible"; [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([Action] {}, [System.Windows.Threading.DispatcherPriority]::Render) }

                    $Window.Cursor = [System.Windows.Input.Cursors]::Wait
                    try {
                        $clientId = $Global:AppConfig.azure.authentication.userAuth.appId
                        $thumb = $Global:AppConfig.azure.certThumbprint
                        $tenant = $Global:AppConfig.azure.tenantName
                        $siteUrl = $safeSiteCb.SelectedItem.Url
                        
                        Write-AppLog -Message "Connexion PnP au site..." -Level Info -RichTextBox $safeLog
                        
                        # Connexion rapide
                        $Global:ExplorerConnection = Connect-AppSharePoint -ClientId $clientId -Thumbprint $thumb -TenantName $tenant -SiteUrl $siteUrl
                        
                        if ($Global:ExplorerConnection) {
                            # 2.2 Init Racine
                            $rootItem = New-Object System.Windows.Controls.TreeViewItem
                            $rootItem.SetResourceReference([System.Windows.Controls.TreeViewItem]::StyleProperty, "ModernTreeViewItemStyle")
                            $rootItem.Header = $lib.Title
                            $rootItem.IsExpanded = $true # Auto Expand Root
                            $rootItem.Tag = [PSCustomObject]@{
                                Name              = "Racine"
                                ServerRelativeUrl = $lib.RootFolder.ServerRelativeUrl
                            }
                            
                            $tv.Items.Add($rootItem)

                            # Populate Racine (Direct)
                            if ($RefPopulate) {
                                & $RefPopulate -ParentNode $rootItem -FolderRelativeUrl $lib.RootFolder.ServerRelativeUrl -Conn $Global:ExplorerConnection
                            }
                            
                            Write-AppLog -Message "Explorateur initialisé." -Level Success -RichTextBox $safeLog
                        }
                        else {
                            Write-AppLog -Message "Echec Connexion PnP (Resultat Null)." -Level Error -RichTextBox $safeLog
                        }
                    }
                    catch {
                        Write-AppLog -Message "Erreur Connexion Explorer : $_" -Level Error -RichTextBox $safeLog
                    }
                    finally {
                        $Window.Cursor = [System.Windows.Input.Cursors]::Arrow
                        if ($loader) { $loader.Visibility = "Collapsed" }
                    }
                }
            }
        }.GetNewClosure())

    # 3. Event GLOBAL : Expansion (Synchronous)
    $exTV = $Window.FindName("TargetExplorerTreeView")
    if ($exTV) {
        
        $ActionExpandSync = {
            param($sender, $e)
            $item = $e.OriginalSource 
            
            if ($item -is [System.Windows.Controls.TreeViewItem]) {
                # Check Dummy
                if ($item.Items.Count -eq 1) {
                    $firstChild = $item.Items[0]
                    $isDummy = $false
                    if ($firstChild -is [System.Windows.Controls.TreeViewItem] -and $firstChild.Tag -eq "DUMMY_TAG") { $isDummy = $true }

                    if ($isDummy) {
                        $folderData = $item.Tag
                        if ($folderData -and $Global:ExplorerConnection -and $RefPopulate) {
                            & $RefPopulate -ParentNode $item -FolderRelativeUrl $folderData.ServerRelativeUrl -Conn $Global:ExplorerConnection
                        }
                    }
                }
            }
        }.GetNewClosure()

        # Remove old handlers to avoid duplicates if re-registering? (Hard to do without ref, assuming single register)
        try {
            $exTV.AddHandler([System.Windows.Controls.TreeViewItem]::ExpandedEvent, [System.Windows.RoutedEventHandler]$ActionExpandSync)
        }
        catch {}

        # 4. Selection Dossier
        $exTV.Add_SelectedItemChanged({
                param($sender, $e)
                $item = $sender.SelectedItem
                if ($item -and $item.Tag.ServerRelativeUrl) {
                    $folderData = $item.Tag
                    $Global:SelectedTargetFolder = $folderData
                    
                    $safeLog = $Window.FindName("LogRichTextBox")
                    if ($safeLog) {
                        Write-AppLog -Message "Dossier cible : $($folderData.ServerRelativeUrl)" -Level Info -RichTextBox $safeLog
                    }
                    
                    # Update Visual Status
                    $st = $Window.FindName("TargetFolderStatusText")
                    if ($st) { $st.Text = $folderData.ServerRelativeUrl }
                }
            }.GetNewClosure())
    }
}
