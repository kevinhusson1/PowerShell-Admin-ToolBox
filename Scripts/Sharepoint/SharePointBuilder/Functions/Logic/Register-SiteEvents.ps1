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
        
        # B. FILTRAGE
        $Ctrl.CbSites.Add_KeyUp({
                param($sender, $e)
                if ($e.Key -in 'Up', 'Down', 'Enter', 'Tab') { return }
                $filterText = $sender.Text
                if ($Global:AllSharePointSites) {
                    if ([string]::IsNullOrWhiteSpace($filterText)) {
                        $sender.ItemsSource = $Global:AllSharePointSites
                    }
                    else {
                        $filtered = $Global:AllSharePointSites | Where-Object { $_.Title -like "*$filterText*" }
                        $sender.ItemsSource = @($filtered)
                    }
                    $sender.IsDropDownOpen = $true
                }
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
                    if ($safeLibCb) {
                        $safeLibCb.ItemsSource = @("Chargement...")
                        $safeLibCb.IsEnabled = $false
                    }

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

    # --- D. LOGIQUE EXPLORATEUR (Version Simplifiée & Sécurisée) ---
    
    # 1. Helper pour peupler un noeud du TreeView
    # Défini comme ScriptBlock local pour capture propre des variables
    $PopulateNodeBlock = {
        param($ParentNode, $FolderRelativeUrl, $SiteUrl)
        
        Write-Host "DEBUG: [PopulateNode] Demande reçue. URL Dossier='$FolderRelativeUrl' | Site='$SiteUrl'"
        
        # UI Feedback
        $overlay = $Window.FindName("ExplorerLoadingOverlay")
        if ($overlay) { $overlay.Visibility = "Visible" }

        # Paramètres pour le Job
        $expArgs = $baseArgs.Clone()
        $expArgs.StartUrl = $SiteUrl
        $expArgs.FolderUrl = $FolderRelativeUrl
        
        # JOB PnP
        $jobExp = Start-Job -ScriptBlock {
            param($M)
            # Log interne au Job (sera reçu dans $results si non séparé, ou via Output)
            Write-Output "DEBUG_JOB: Démarrage Job. ModulePath='$($M.ModPath)'"
            
            try {
                if (Test-Path $M.ModPath) {
                    Import-Module $M.ModPath -Force
                }
                else {
                    throw "Module introuvable au chemin : $($M.ModPath)"
                }
                
                $c = Connect-AppSharePoint -ClientId $M.ClientId -Thumbprint $M.Thumb -TenantName $M.Tenant -SiteUrl $M.StartUrl
                if (-not $c) { throw "Connexion PnP échouée (Connect-AppSharePoint a renvoyé null)" }
                
                # Correction URL Relative : Get-PnPFolderItem attend une URL relative au SITE, pas au Serveur.
                # On calcule la différence.
                $web = Get-PnPWeb -Connection $c
                $webUrl = $web.ServerRelativeUrl
                $inputUrl = $M.FolderUrl
                
                $siteRelativeUrl = $inputUrl
                if ($inputUrl.StartsWith($webUrl, [System.StringComparison]::InvariantCultureIgnoreCase)) {
                    $siteRelativeUrl = $inputUrl.Substring($webUrl.Length)
                }
                
                # Gérer le cas racine (si vide ou just /)
                if ([string]::IsNullOrWhiteSpace($siteRelativeUrl)) { $siteRelativeUrl = "/" }

                Write-Output "DEBUG_JOB: Transformation URL. Input='$inputUrl' | Web='$webUrl' => SiteRelative='$siteRelativeUrl'"
                Write-Output "DEBUG_JOB: Connexion OK. Récupération dossiers..."
                
                $folders = Get-PnPFolderItem -FolderSiteRelativeUrl $siteRelativeUrl -ItemType Folder -Connection $c -ErrorAction Stop
                Write-Output "DEBUG_JOB: Objets trouvés : $($folders.Count)"
                
                $res = @()
                foreach ($f in $folders) {
                    $res += [PSCustomObject]@{
                        Name              = $f.Name
                        ServerRelativeUrl = $f.ServerRelativeUrl
                        ItemCount         = $f.ItemCount
                        Type              = "FolderData" # Marqueur pour filtrer les logs
                    }
                }
                return $res
            }
            catch { 
                Write-Output "DEBUG_JOB_ERROR: $_"
                throw $_ 
            }
        } -ArgumentList $expArgs

        $jId = $jobExp.Id
        Write-Host "DEBUG: [PopulateNode] Job lancé (ID=$jId). Attente..."
        
        # TIMER UI
        $tim = New-Object System.Windows.Threading.DispatcherTimer
        $tim.Interval = [TimeSpan]::FromMilliseconds(200)
        
        # Action du Timer encapsulée dans un Try/Catch global pour éviter le crash ShowDialog
        $timAction = {
            try {
                $j = Get-Job -Id $jId -ErrorAction SilentlyContinue
                if ($j -and $j.State -ne 'Running') {
                    $tim.Stop()
                    $safeOverlay = $Window.FindName("ExplorerLoadingOverlay")
                    if ($safeOverlay) { $safeOverlay.Visibility = "Collapsed" }
                    
                    Write-Host "DEBUG: [Timer] Job terminé (State=$($j.State)). Récupération resultats..."
                    $results = Receive-Job $j -Wait -AutoRemoveJob
                    
                    # Traitement des erreurs fatales du Job
                    if ($j.State -eq 'Failed') {
                        $err = $j.ChildJobs[0].Error
                        Write-Host "DEBUG: [Timer] ERROR JOB: $err"
                        $safeLog = $Window.FindName("LogRichTextBox")
                        if ($safeLog) { Write-AppLog -Message "Erreur Explorateur : $err" -Level Error -RichTextBox $safeLog }
                    } 
                    else {
                        # Filtrer les logs vs les données
                        $realFolders = @()
                        foreach ($item in $results) {
                            if ($item -is [string]) {
                                Write-Host "   >> JOB LOG: $item"
                            }
                            elseif ($item.Type -eq "FolderData") {
                                $realFolders += $item
                            }
                            else {
                                # Cas d'objets non marqués (au cas où)
                                if ($item.Name -and $item.ServerRelativeUrl) {
                                    $realFolders += $item
                                }
                            }
                        }
                        
                        Write-Host "DEBUG: [Timer] Dossiers valides extraits : $($realFolders.Count)"

                        # UPDATE UI
                        if ($ParentNode) {
                            $ParentNode.Items.Clear() # Nettoyage du Dummy
                            
                            foreach ($folder in $realFolders) {
                                if ($folder.Name -eq "Forms") { continue } # Masquer dossier système

                                Write-Host "   -> Ajout TreeView: $($folder.Name) ($($folder.ServerRelativeUrl))"

                                $newItem = New-Object System.Windows.Controls.TreeViewItem
                                
                                # Header (Style Modifié : Goldenrod)
                                $stack = New-Object System.Windows.Controls.StackPanel
                                $stack.Orientation = "Horizontal"
                                $txtIcon = New-Object System.Windows.Controls.TextBlock
                                $txtIcon.Text = "📁"
                                $txtIcon.Margin = "0,0,5,0"
                                $txtIcon.Foreground = [System.Windows.Media.Brushes]::Goldenrod # UPDATE STYLE
                                
                                $txt = New-Object System.Windows.Controls.TextBlock
                                $txt.Text = $folder.Name
                                $stack.Children.Add($txtIcon)
                                $stack.Children.Add($txt)
                                
                                $newItem.Header = $stack
                                $newItem.Tag = $folder 
                                
                                # Dummy pour Lazy Loading (Style amélioré)
                                $dummy = New-Object System.Windows.Controls.TreeViewItem
                                $dummy.Header = "Chargement..."
                                $dummy.FontStyle = "Italic"
                                $dummy.Foreground = [System.Windows.Media.Brushes]::Gray
                                $dummy.IsEnabled = $false
                                $dummy.Tag = "DUMMY_TAG" # Marqueur technique
                                
                                $newItem.Items.Add($dummy)
                                
                                $ParentNode.Items.Add($newItem)
                            }
                        }
                        else {
                            Write-Host "DEBUG: [Timer] ERREUR : ParentNode est null !"
                        }
                    }
                }
            }
            catch {
                Write-Host "CRITICAL TIMER ERROR: $_"
                # On évite de propager l'erreur pour ne pas tuer ShowDialog
            }
        }.GetNewClosure() 
        
        $tim.Add_Tick($timAction)
        $tim.Start()
    }.GetNewClosure()

    # 2. Event : Sélection Bibliothèque (Init Racine)
    
    # Capture explite du ScriptBlock pour le Closure
    $LocalPopulateBlock = $PopulateNodeBlock

    $Ctrl.CbLibs.Add_SelectionChanged({
            try {
                $lib = $this.SelectedItem
                $safeLog = $Window.FindName("LogRichTextBox")
                $safeSiteCb = $Window.FindName("SiteComboBox")
                $tv = $Window.FindName("TargetExplorerTreeView")

                if ($lib -is [System.Management.Automation.PSCustomObject] -and $safeSiteCb.SelectedItem) {
                    if ($safeLog) {
                        try {
                            if (-not $Context.AutoLibraryName) {
                                Write-AppLog -Message "Bibliothèque : '$($lib.Title)'" -Level Info -RichTextBox $safeLog
                            }
                        }
                        catch {}
                    }

                    if ($tv) {
                        $tv.Items.Clear()
                        
                        $st = $Window.FindName("TargetFolderStatusText")
                        if ($st) { $st.Text = "/" }
                        
                        $Global:SelectedTargetFolder = [PSCustomObject]@{ 
                            Name              = "Racine"
                            ServerRelativeUrl = $lib.RootFolder.ServerRelativeUrl 
                        }

                        # Appel du Helper si disponible
                        if ($LocalPopulateBlock) {
                            & $LocalPopulateBlock -ParentNode $tv -FolderRelativeUrl $lib.RootFolder.ServerRelativeUrl -SiteUrl $safeSiteCb.SelectedItem.Url
                        }
                        else {
                            Write-Host "Erreur CRITIQUE : PopulateNodeBlock est null dans SelectionChanged."
                        }
                    }
                }
                if ($null -ne $PreviewLogic) { & $PreviewLogic } 
            }
            catch { Write-Host "Erreur SelectionChanged: $_" }
        }.GetNewClosure())

    # 3. Event GLOBAL : Expansion d'un noeud (Lazy Loading)
    # On attache l'événement au TreeView principal (Bubble Event) pour éviter la récursion complexe
    $exTV = $Window.FindName("TargetExplorerTreeView")
    if ($exTV) {
        
        # ScriptBlock pour l'expansion - Doit être converti en RoutedEventHandler pour AddHandler
        # En PowerShell, un ScriptBlock simple peut often être casté, mais pour RoutedEventHandler c'est specifique.
        
        $GlobalExpandHandler = { } # Placeholder pour garder la structure logique si nécessaire, mais on utilise ActionExpand direct.

        # On a besoin que le Handler accède à $PopulateNodeBlock.
        # Le moyen le plus sûr est de redéfinir le bloc d'expansion APRES avoir défini $PopulateNodeBlock et d'utiliser GetNewClosure().
        
        $ActionExpand = {
            param($sender, $e)
            try {
                $item = $e.OriginalSource 
                if ($item -is [System.Windows.Controls.TreeViewItem]) {
                    # Vérifier si c'est un noeud "Dummy" non chargé via Tag
                    $firstChild = $item.Items[0]
                    $isDummy = $false
                    
                    if ($firstChild -is [System.Windows.Controls.TreeViewItem]) {
                        if ($firstChild.Tag -eq "DUMMY_TAG") { $isDummy = $true }
                    }
                    # Fallback old check
                    elseif ($firstChild.Header -eq "DUMMY") { $isDummy = $true }

                    if ($isDummy) {
                        $folderData = $item.Tag
                        $safeSiteCb = $Window.FindName("SiteComboBox")
                        
                        # Utilisation de la variable capturée
                        if ($folderData -and $safeSiteCb.SelectedItem -and $LocalPopulateBlock) {
                            & $LocalPopulateBlock -ParentNode $item -FolderRelativeUrl $folderData.ServerRelativeUrl -SiteUrl $safeSiteCb.SelectedItem.Url
                        }
                    }
                }
            }
            catch { Write-Host "Erreur OnExpanded interne : $_" }
        }.GetNewClosure()

        # Attachement CORRECT de l'événement Bubbled
        try {
            # On doit utiliser AddHandler car l'événement est défini sur TreeViewItem, pas TreeView
            $exTV.AddHandler([System.Windows.Controls.TreeViewItem]::ExpandedEvent, [System.Windows.RoutedEventHandler]$ActionExpand)
        }
        catch {
            Write-Host "Warning: Echec AddHandler Expanded: $_"
        }

        # 4. Event : Sélection Dossier
        $exTV.Add_SelectedItemChanged({
                param($sender, $e)
                $item = $sender.SelectedItem
                if ($item -and $item.Tag) {
                    $folderData = $item.Tag
                    $Global:SelectedTargetFolder = $folderData
                    $st = $Window.FindName("TargetFolderStatusText")
                    if ($st) { $st.Text = $folderData.ServerRelativeUrl }
                }
            }.GetNewClosure())
    }
}
