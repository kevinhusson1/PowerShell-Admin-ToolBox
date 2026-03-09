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

    # 🆕 v3.6 : Connexion Globale pour le Thread UI (Indispensable pour PopulateNodeSync)
    try {
        if ($Global:AppConfig.azure.certThumbprint) {
            Write-Verbose "[Register-SiteEvents] Connexion Graph Globale (Thread UI)..."
            Connect-AppAzureCert -TenantId $Global:AppConfig.azure.tenantId -ClientId $Global:AppConfig.azure.authentication.userAuth.appId -Thumbprint $Global:AppConfig.azure.certThumbprint | Out-Null
        }
    }
    catch { Write-Warning "[Register-SiteEvents] Échec connexion Graph UI : $_" }

    # --- Logique Pagination (v4.17) : Déportée dans Invoke-AppSPRenderBatch (Global) ---
    Write-Verbose "[v4.17] Register-SiteEvents Initialisation..."

    $Global:AllSharePointSites = @()
    
    # Paramètres de base pour traverser la frontière du Job (Azure V2)
    $baseArgs = @{
        Thumb      = $Global:AppConfig.azure.certThumbprint
        ClientId   = $Global:AppConfig.azure.authentication.userAuth.appId
        Tenant     = $Global:AppConfig.azure.tenantName
        ModulePath = "$($Global:ProjectRoot)\Modules"
    }

    # ==========================================================================
    # BRANCHE 1 : MODE AUTOPILOT (Graph V2)
    # ==========================================================================
    if (-not [string]::IsNullOrWhiteSpace($Context.AutoSiteUrl)) {
        
        $Ctrl.CbSites.IsEnabled = $false
        $Ctrl.CbLibs.IsEnabled = $false
        Write-AppLog -Message "Autopilot : Vérification via Graph..." -Level Info -RichTextBox $Ctrl.LogBox

        $autoArgs = $baseArgs.Clone()
        $autoArgs.TargetSiteUrl = $Context.AutoSiteUrl
        $autoArgs.TargetLibName = $Context.AutoLibraryName

        $jobAuto = Start-Job -ScriptBlock {
            param($ArgsMap)
            if ($ArgsMap.ModulePath) { $env:PSModulePath = "$($ArgsMap.ModulePath);$($env:PSModulePath)" }
            Import-Module Azure -Force
            try {
                Connect-AppAzureCert -TenantId $ArgsMap.Tenant -ClientId $ArgsMap.ClientId -Thumbprint $ArgsMap.Thumb | Out-Null
                
                $siteId = Get-AppGraphSiteId -SiteUrl $ArgsMap.TargetSiteUrl
                if (-not $siteId) { throw "Impossible de résoudre l'ID du site cible." }

                $siteGraph = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId"
                $siteObj = [PSCustomObject]@{ Title = $siteGraph.displayName; Url = $siteGraph.webUrl; Id = $siteId }

                $libObj = $null
                if ($ArgsMap.TargetLibName) {
                    $listAndDrive = Get-AppGraphListDriveId -SiteId $siteId -ListDisplayName $ArgsMap.TargetLibName
                    $listGraph = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/lists/$($listAndDrive.ListId)"
                    $relUrl = [System.Uri]::new($listGraph.list.webUrl).AbsolutePath
                    $libObj = [PSCustomObject]@{ Title = $listGraph.displayName; Id = $listAndDrive.ListId; DriveId = $listAndDrive.DriveId; RootFolder = [PSCustomObject]@{ ServerRelativeUrl = $relUrl } }
                }
                return [PSCustomObject]@{ Site = $siteObj; Lib = $libObj }
            }
            catch { throw $_ }
        } -ArgumentList $autoArgs

        $autoJobId = $jobAuto.Id

        $timerAuto = New-Object System.Windows.Threading.DispatcherTimer
        $timerAuto.Interval = [TimeSpan]::FromMilliseconds(500)
        
        $timerAuto.Tag = @{
            JobId           = $autoJobId
            Window          = $Window
            PreviewLogic    = $PreviewLogic
            AutoLibraryName = $AutoLibraryName
            CbSites         = $Ctrl.CbSites
            CbLibs          = $Ctrl.CbLibs
            LogBox          = $Ctrl.LogBox
        }

        $timerAutoBlock = {
            param($sender, $e)
            try {
                $ctx = $sender.Tag
                $j = Get-Job -Id $ctx.JobId -ErrorAction SilentlyContinue
                if ($j -and $j.State -ne 'Running') {
                    if ($sender) { $sender.Stop() }
                    
                    $safeCbSites = $ctx.CbSites
                    $safeCbLibs = $ctx.CbLibs
                    $safeLog = $ctx.LogBox
                    if ($null -eq $safeCbSites) { return }

                    $res = Receive-Job $j -Wait
                    if ($j) { Remove-Job $j -ErrorAction SilentlyContinue }
                    
                    if (-not $res) {
                        Write-AppLog -Message "Autopilot : Aucun résultat reçu du Job." -Level Warning -RichTextBox $safeLog
                        return
                    }

                    if ($j.State -eq 'Failed' -or ($res -is [string] -and $res -like "JOB_ERROR*")) {
                        $err = if ($j.ChildJobs) { $j.ChildJobs[0].Error } else { $res }
                        if ($safeLog) { Write-AppLog -Message "Erreur Autopilot : $err" -Level Error -RichTextBox $safeLog }
                        $safeCbSites.ItemsSource = @("Echec Autopilot")
                    } 
                    else {
                        $site = if ($res.Site) { $res.Site } else { $res } # En cas d'objet direct
                        $safeCbSites.ItemsSource = @($site)
                        $safeCbSites.DisplayMemberPath = "Title"
                        $safeCbSites.SelectedItem = $site
                        if ($safeLog) { Write-AppLog -Message "Site sélectionné (Autopilot) : '$($site.Title)'" -Level Success -RichTextBox $safeLog }

                        if ($res.Lib) {
                            $lib = $res.Lib
                            $safeCbLibs.ItemsSource = @($lib)
                            $safeCbLibs.DisplayMemberPath = "Title"
                            $safeCbLibs.SelectedItem = $lib
                            if ($safeLog) { Write-AppLog -Message "Bibliothèque sélectionnée (Autopilot) : '$($lib.Title)'" -Level Success -RichTextBox $safeLog }
                        }

                        if ($null -ne $ctx.PreviewLogic) { & $ctx.PreviewLogic }
                    }
                }
            }
            catch {
                if ($sender) { 
                    $sender.Stop() 
                    $ctx = $sender.Tag
                    if ($ctx -and $ctx.Window) {
                        Write-Warning "CRASH DANS timerAutoBlock: $($_.Exception.Message)"
                        $logErr = $ctx.Window.FindName("LogRichTextBox")
                        if ($logErr) { Write-AppLog -Message "CRASH DANS timerAutoBlock: $($_.Exception.Message)" -Level Error -RichTextBox $logErr }
                    }
                }
            }
        } # Plus de Capture Closure !

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
        if ($Ctrl.SiteLoadingBar) { $Ctrl.SiteLoadingBar.Visibility = [System.Windows.Visibility]::Visible }

        # LOG 1 : Vérification des paramètres avant envoi
        Write-Verbose "[DEBUG] Params envoyés au Job : ClientId=$($baseArgs.ClientId), Tenant=$($baseArgs.Tenant), Thumb=$($baseArgs.Thumb)"

        $jobSites = Start-Job -ScriptBlock {
            param($ArgsMap)
            if ($ArgsMap.ModulePath) { $env:PSModulePath = "$($ArgsMap.ModulePath);$($env:PSModulePath)" }
            Write-Output "JOB_LOG: Démarrage du Job. Import du module Azure..."
            try {
                Import-Module Azure -Force
                Write-Output "JOB_LOG: Connexion Graph App-Only..."
                Connect-AppAzureCert -TenantId $ArgsMap.Tenant -ClientId $ArgsMap.ClientId -Thumbprint $ArgsMap.Thumb | Out-Null
                
                Write-Output "JOB_LOG: Récupération des sites via Graph..."
                # L'endpoint /sites/getAllSites est la méthode canonique Graph V1 pour lister les sites
                $uri = "https://graph.microsoft.com/v1.0/sites/getAllSites?`$select=id,displayName,webUrl"
                $result = New-Object System.Collections.Generic.List[object]
                
                do {
                    $sitesRes = Invoke-MgGraphRequest -Method GET -Uri $uri
                    foreach ($s in $sitesRes.value) {
                        # Exclusion des espaces personnels (OneDrive) et sites sans nom
                        if ($s.webUrl -notmatch "/personal/" -and -not [string]::IsNullOrWhiteSpace($s.displayName)) {
                            $result.Add([PSCustomObject]@{ Title = $s.displayName; Url = $s.webUrl; Id = $s.id })
                        }
                    }
                    $uri = $sitesRes.'@odata.nextLink'
                } while ($null -ne $uri)
                
                # Tri par titre
                $result = $result | Sort-Object Title
                
                $count = $result.Count
                Write-Output "JOB_LOG: Commande terminée. $count sites trouvés."
                
                return $result
            }
            catch {
                Write-Output "JOB_ERROR: $($_.Exception.Message)"
                throw $_
            }
        } -ArgumentList $baseArgs

        $siteJobId = $jobSites.Id
        Write-Verbose "[DEBUG] Job lancé avec ID: $siteJobId"

        $timerSites = New-Object System.Windows.Threading.DispatcherTimer
        $timerSites.Interval = [TimeSpan]::FromMilliseconds(500)
        
        $timerSites.Tag = @{
            JobId   = $siteJobId
            Window  = $Window
            Ctrl    = $Ctrl # CRITIQUE : Défini ici pour accès dans le bloc Tick
            CbSites = $Ctrl.CbSites
            LogBox  = $Ctrl.LogBox
        }

        $timerSitesBlock = {
            param($sender, $e)
            try {
                $ctx = $sender.Tag
                $j = Get-Job -Id $ctx.JobId -ErrorAction SilentlyContinue
                
                # LOG 4 : État du Job à chaque tick
                if ($j) { Write-Verbose "[TimerTick] Job State: $($j.State)" }
                else { Write-Verbose "[TimerTick] Job introuvable !" }

                if ($j -and $j.State -ne 'Running') {
                    if ($sender) { $sender.Stop() }
                    
                    $safeCb = $ctx.CbSites
                    $safeLog = $ctx.LogBox
                    if ($ctx.Ctrl -and $ctx.Ctrl.SiteLoadingBar) { 
                        $ctx.Ctrl.SiteLoadingBar.Visibility = [System.Windows.Visibility]::Collapsed 
                        Write-Verbose "[timerSites] SiteLoadingBar masqué."
                    }

                    if ($null -eq $safeCb) { return }

                    # Récupération UNIQUE de TOUT (Logs + Objets)
                    $rawResults = @(Receive-Job $j -Wait)
                    if ($j) { Remove-Job $j -ErrorAction SilentlyContinue }
                    
                    # Séparation Logs vs Données
                    $debugLogs = $rawResults | Where-Object { $_ -is [string] -and ($_ -like "JOB_*") }
                    $realData = $rawResults | Where-Object { $_ -isnot [string] -or ($_ -notlike "JOB_*") }

                    # Affichage des logs internes du Job
                    foreach ($line in $debugLogs) { 
                        Write-Verbose ">> $line" 
                        if ($line -like "JOB_ERROR*") {
                            Write-AppLog -Message $line -Level Error -RichTextBox $safeLog
                        }
                    }

                    if ($j.State -eq 'Failed') {
                        $err = if ($j.ChildJobs) { $j.ChildJobs[0].Error } else { "Erreur inconnue" }
                        $safeCb.ItemsSource = @("Erreur de chargement")
                        Write-AppLog -Message "DÉFAILLANCE SITE LOAD : $err" -Level Error -RichTextBox $safeLog
                        Write-Verbose "[DEBUG] Job State: Failed. Error: $err"
                    }
                    else {
                        $sitesArray = @($realData)
                        $Global:AllSharePointSites = $sitesArray
                        Write-Verbose "[DEBUG] Sites extraits du flux : $($sitesArray.Count)"

                        if ($sitesArray.Count -gt 0) {
                            $safeCb.ItemsSource = $sitesArray
                            $safeCb.DisplayMemberPath = "Title"
                            $safeCb.IsEnabled = $true
                            Write-AppLog -Message "$($sitesArray.Count) sites chargés avec succès." -Level Success -RichTextBox $safeLog
                            
                            $btnLoad = $ctx.Window.FindName("LoadConfigButton")
                            $cbConfig = $ctx.Window.FindName("DeployConfigComboBox")
                            if ($btnLoad -and $cbConfig -and $cbConfig.SelectedItem) {
                                $btnLoad.IsEnabled = $true
                            }
                        }
                        else {
                            $safeCb.ItemsSource = @("Aucun site trouvé")
                            Write-AppLog -Message "Résultat vide (0 sites trouvés)." -Level Warning -RichTextBox $safeLog
                        }
                    }
                }
            }
            catch {
                if ($sender) { 
                    $sender.Stop() 
                    $ctx = $sender.Tag
                    if ($ctx -and $ctx.Window) {
                        Write-Warning "CRASH DANS timerSitesBlock: $($_.Exception.Message) `n$($_.InvocationInfo.PositionMessage)"
                        $logErr = $ctx.Window.FindName("LogRichTextBox")
                        if ($logErr) { Write-AppLog -Message "CRASH DANS timerSitesBlock: $($_.Exception.Message)" -Level Error -RichTextBox $logErr }
                    }
                }
            }
        } # Plus de Capture Closure !

        $timerSites.Add_Tick($timerSitesBlock)
        $timerSites.Start()

        # --- RESTE DU FICHIER (Events manuels KeyUp, SelectionChanged...) ---
        # Je remets le code de filtrage et chargement lib ici pour que ce soit complet
        
        # B. FILTRAGE AVEC DEBOUNCE (Anti-Freeze)
        $searchTimer = New-Object System.Windows.Threading.DispatcherTimer
        $searchTimer.Interval = [TimeSpan]::FromMilliseconds(500)
        $searchTimer.Tag = @{ Cb = $Ctrl.CbSites }
        
        # Injection du minuteur dans les ressources WPF natives de la ComboBox (Survit à l'Async)
        if ($Ctrl.CbSites.Resources.Contains("DebouceTimer")) {
            $Ctrl.CbSites.Resources.Remove("DebouceTimer")
        }
        $Ctrl.CbSites.Resources.Add("DebouceTimer", $searchTimer)

        $searchAction = {
            param($sender, $e)
            if ($sender) { $sender.Stop() }
            $ctx = $sender.Tag
            $cb = $ctx.Cb
            $filterText = $cb.Text
            
            # Run filtering in background/idle to not block? 
            # Actually filtering an array is fast, it's the UI update that might lag if too frequent.
            
            if ($Global:AllSharePointSites) {
                Write-Verbose "[searchAction] Filtrage sur: '$filterText' (Total: $($Global:AllSharePointSites.Count))"
                if ([string]::IsNullOrWhiteSpace($filterText)) {
                    $cb.ItemsSource = $Global:AllSharePointSites
                    Write-AppLog -Message "Recherche vide : toutes les sources affichées." -Level Info -RichTextBox ($Window.FindName("LogRichTextBox"))
                }
                else {
                    $filtered = $Global:AllSharePointSites | Where-Object { $_.Title -like "*$filterText*" }
                    $cb.ItemsSource = @($filtered)
                    Write-AppLog -Message "Recherche : '$filterText' -> $($filtered.Count) résultats." -Level Info -RichTextBox ($Window.FindName("LogRichTextBox"))
                }
                $cb.IsDropDownOpen = $true
            }
        } # End SearchAction without GetNewClosure

        $searchTimer.Add_Tick($searchAction)

        $Ctrl.CbSites.Add_KeyUp({
                param($sender, $e)
                if ($e.Key -in 'Up', 'Down', 'Enter', 'Tab', 'Left', 'Right') { return }
                
                # Récupération sécurisée du Timer dé-bouncing depuis l'arbre WPF
                $savedTimer = $sender.Resources["DebouceTimer"]
                if ($null -ne $savedTimer) {
                    $savedTimer.Stop()
                    $savedTimer.Start()
                }
            })

        $Ctrl.CbSites.Add_SelectionChanged({
                try {
                    $site = $this.SelectedItem
                    $vVisible = [System.Windows.Visibility]::Visible
                    $vCollapsed = [System.Windows.Visibility]::Collapsed

                    $siteName = if ($site -and $site.Title) { $site.Title } else { "Inconnu" }
                    Write-Verbose "[SelectionChanged] Site sélectionné: $siteName"
                
                    # Assouplissement : on accepte tout objet qui n'est pas une simple chaîne de texte informative
                    if ($site -and $site -isnot [string]) {
                
                        $uiLog = $Window.FindName("LogRichTextBox")
                        if ($uiLog) {
                            Write-AppLog -Message "Site sélectionné : '$($site.Title)'" -Level Info -RichTextBox $uiLog
                            Write-Verbose "[CbSites] URL: $($site.Url) | Type: $($site.GetType().Name)"
                        }

                        if ($Ctrl.CbLibs) {
                            $Ctrl.CbLibs.ItemsSource = @("Chargement...")
                            # On laisse IsEnabled = true pour v3.0 comme convenu
                            $Ctrl.CbLibs.IsEnabled = $true 
                        }
                        if ($Ctrl.LibLoadingBar) { $Ctrl.LibLoadingBar.Visibility = $vVisible }

                        # RESET TREEVIEW (Step 1) & SELECTION
                        if ($Ctrl.TargetTree) {
                            $Ctrl.TargetTree.Items.Clear()
                            # Restauration Placeholder
                            $ph = New-Object System.Windows.Controls.TreeViewItem
                            $ph.Header = "Veuillez sélectionner une bibliothèque..."
                            $ph.SetResourceReference([System.Windows.Controls.Control]::ForegroundProperty, "TextDisabledBrush")
                            $ph.FontStyle = "Italic"
                            $ph.IsEnabled = $false
                            $ph.SetResourceReference([System.Windows.Controls.TreeViewItem]::StyleProperty, "ModernTreeViewItemStyle") # Cohérence
                            $Ctrl.TargetTree.Items.Add($ph)
                        }
                        $Global:SelectedTargetFolder = $null
                        $st = $Window.FindName("TargetFolderStatusText")
                        if ($st) { $st.Text = "" }

                        # Nouvelle définition BaseArgs V2 (v3.6 : Pré-chargement des IDs)
                        $libArgs = @{
                            Thumb       = $Global:AppConfig.azure.certThumbprint
                            ClientId    = $Global:AppConfig.azure.authentication.userAuth.appId
                            Tenant      = $Global:AppConfig.azure.tenantName # Correction : On utilise le même que pour les sites
                            SiteUrl     = $site.Url
                            SiteId      = $site.Id # Nouveau : On passe l'ID déjà résolu
                            ProjectRoot = $Global:ProjectRoot
                        }
                        $jobLibs = Start-Job -ScriptBlock {
                            param($ArgsMap)
                            $env:PSModulePath = "$($ArgsMap.ProjectRoot)\Modules;$($ArgsMap.ProjectRoot)\Vendor;$($env:PSModulePath)"
                            Write-Output "JOB_LOG: Import des modules..."
                            Import-Module Core, Azure -Force
                            try {
                                Write-Output "JOB_LOG: Connexion Graph..."
                                Connect-AppAzureCert -TenantId $ArgsMap.Tenant -ClientId $ArgsMap.ClientId -Thumbprint $ArgsMap.Thumb | Out-Null
                            
                                $siteId = if ($ArgsMap.SiteId) { $ArgsMap.SiteId } else { Get-AppGraphSiteId -SiteUrl $ArgsMap.SiteUrl }
                                Write-Output "JOB_LOG: Récupération des bibliothèques pour SiteId: $siteId"
                                $lists = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/lists?`$expand=drive"
                                Write-Output "JOB_LOG: $($lists.value.Count) listes brutes reçues de Graph."
                            
                                $result = New-Object System.Collections.Generic.List[object]
                                foreach ($l in $lists.value) {
                                    if ($l.list -and $l.list.template -ne 'documentLibrary') { continue }
                                    if ($l.hidden -or $l.displayName -eq "Form Templates" -or $l.displayName -eq "Site Assets" -or $l.displayName -eq "Style Library") { continue }
                                
                                    $relUrl = ""
                                    if ($l.webUrl) { $relUrl = [System.Uri]::new($l.webUrl).AbsolutePath }
                                
                                    $libObj = [PSCustomObject]@{ 
                                        Title      = $l.displayName; 
                                        Id         = $l.id; 
                                        SiteId     = $siteId;
                                        DriveId    = if ($l.drive) { $l.drive.id } else { $null };
                                        RootFolder = [PSCustomObject]@{ ServerRelativeUrl = $relUrl }
                                    }
                                    $result.Add($libObj)
                                }
                                $final = $result | Sort-Object Title
                                Write-Output "JOB_LOG: Fin. $($final.Count) bibliothèques conservées après filtrage."
                                return $final
                            }
                            catch { 
                                Write-Output "JOB_ERROR: $($_.Exception.Message)"
                                throw $_ 
                            }
                        } -ArgumentList $libArgs

                        $libJobId = $jobLibs.Id

                        $timerLibs = New-Object System.Windows.Threading.DispatcherTimer
                        $timerLibs.Interval = [TimeSpan]::FromMilliseconds(200)
                
                        $timerLibs.Tag = @{
                            JobId        = $libJobId
                            Window       = $Window
                            Ctrl         = $Ctrl
                            PreviewLogic = $PreviewLogic
                        }

                        $timerLibsBlock = {
                            param($sender, $e)
                            try {
                                $ctx = $sender.Tag
                                $j = Get-Job -Id $ctx.JobId -ErrorAction SilentlyContinue
                                $vVisible = [System.Windows.Visibility]::Visible
                                $vCollapsed = [System.Windows.Visibility]::Collapsed

                                if ($j) {
                                    Write-Verbose "[timerLibs-V3.2] JobId: $($ctx.JobId) | État: $($j.State)"
                                
                                    if ($j.State -ne 'Running') {
                                        if ($sender) { $sender.Stop() }
                                    
                                        # 1. Récupération des données
                                        $rawRes = @(Receive-Job $j -Wait)
                                        if ($j) { Remove-Job $j -ErrorAction SilentlyContinue }
                                    
                                        # Séparation Logs vs Données
                                        $debugLogs = $rawRes | Where-Object { $_ -is [string] -and ($_ -like "JOB_*") }
                                        $libsData = $rawRes | Where-Object { $_ -isnot [string] -or ($_ -notlike "JOB_*") }

                                        foreach ($line in $debugLogs) { 
                                            Write-Verbose ">> $line" 
                                            if ($line -like "JOB_ERROR*") {
                                                if ($ctx.Ctrl.LogBox) { Write-AppLog -Message $line -Level Error -RichTextBox $ctx.Ctrl.LogBox }
                                            }
                                        }

                                        # 2. Mise à jour UI forcée (v3.5 - Simplification Draconienne)
                                        $ctx.Window.Dispatcher.Invoke({
                                                try {
                                                    $vCollapsed = [System.Windows.Visibility]::Collapsed
                                                    $c = $ctx.Ctrl
                                            
                                                    if ($c.LibLoadingBar) { $c.LibLoadingBar.Visibility = $vCollapsed }
                                            
                                                    $libArray = @($libsData)
                                            
                                                    if ($c.CbLibs) {
                                                        if ($libArray.Count -gt 0) {
                                                            $c.CbLibs.ItemsSource = $libArray
                                                            $c.CbLibs.DisplayMemberPath = "Title"
                                                            $c.CbLibs.IsEnabled = $true
                                                    
                                                            if ($libArray.Count -eq 1) { 
                                                                $c.CbLibs.SelectedIndex = 0 
                                                                Write-Verbose "[timerLibs-V3.5] Auto-sélection de l'unique bibliothèque."
                                                            }
                                                    
                                                            if ($c.LogBox) { Write-AppLog -Message "$($libArray.Count) bibliothèques prêtes (v4.2)." -Level Success -RichTextBox $c.LogBox }
                                                        }
                                                        else {
                                                            $c.CbLibs.ItemsSource = @("Aucune")
                                                            if ($c.LogBox) { Write-AppLog -Message "Liste vide reçue (v4.2)." -Level Warning -RichTextBox $c.LogBox }
                                                        }
                                                        $c.CbLibs.UpdateLayout()
                                                    }
                                                }
                                                catch { Write-Warning "Erreur UI (timerLibs): $_" }
                                            })
                                    
                                        if ($null -ne $ctx.PreviewLogic) { & $ctx.PreviewLogic } 
                                    }
                                }
                                else {
                                    Write-Verbose "[timerLibs-V3.2] Job introuvable (Id: $($ctx.JobId))"
                                    if ($sender) { $sender.Stop() }
                                }
                            }
                            catch {
                                if ($sender) { $sender.Stop() }
                                Write-Warning "CRASH CbSites_timerLibsBlock : $_"
                            }
                        }

                        $timerLibs.Add_Tick($timerLibsBlock)
                        $timerLibs.Start()
                    }
                }
                catch {
                    $logErr = $Window.FindName("LogRichTextBox")
                    if ($logErr) {
                        Write-AppLog -Message "CRASH CbSites_SelectionChanged : $($_.Exception.Message) `n $($_.InvocationInfo.PositionMessage)" -Level Error -RichTextBox $logErr
                    }
                }
            }.GetNewClosure())
    }

    # --- D. LOGIQUE EXPLORATEUR CENTRALISÉ (v4.2) ---
    
    # 1. Moteur de Population (v4.2)
    $PopulateNodeInternal = {
        param($ParentNode)
        
        $tag = $ParentNode.Tag
        $lB = $Ctrl.LogBox
        $engName = "v4.2"

        # Suivi du chemin (FullPath pour les logs)
        $path = if ($tag.FullPath) { $tag.FullPath } else { "/" }

        try {
            if ($lB) { Write-AppLog -Message "[$engName] Exploration : $path" -Level Info -RichTextBox $lB }

            # Sécurité IDs
            if (-not $tag.DriveId -or -not $tag.SiteId) {
                if ($lB) { Write-AppLog -Message "[$engName] Erreur : ID Manquant pour $path" -Level Warning -RichTextBox $lB }
                return
            }

            $overlay = $Window.FindName("ExplorerLoadingOverlay")
            if ($overlay) { $overlay.Visibility = "Visible" }
            $Window.Cursor = [System.Windows.Input.Cursors]::Wait
            
            # Rafraîchissement UI
            [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([Action] {}, [System.Windows.Threading.DispatcherPriority]::Render)

            # Sécurité Connexion Graph
            if (-not (Get-MgContext)) {
                Connect-AppAzureCert -TenantId $Global:AppConfig.azure.tenantId -ClientId $Global:AppConfig.azure.authentication.userAuth.appId -Thumbprint $Global:AppConfig.azure.certThumbprint | Out-Null
            }

            $ParentNode.Items.Clear()
            
            # Requête Graph
            $uri = "https://graph.microsoft.com/v1.0/sites/$($tag.SiteId)/drives/$($tag.DriveId)/items/$($tag.ItemId)/children"
            $res = Invoke-MgGraphRequest -Method GET -Uri $uri
            
            $subFolders = @($res.value | Where-Object { $null -ne $_.folder -and -not $_.name.StartsWith("_") })
            
            # --- Logic Point 1.2 : Mise en cache pour pagination ---
            $tag | Add-Member -MemberType NoteProperty -Name "CachedChildren" -Value $subFolders -Force
            $tag | Add-Member -MemberType NoteProperty -Name "RenderedCount" -Value 0 -Force
            
            Write-Verbose "[v4.17] Données reçues ($($subFolders.Count) items). Appel Invoke-AppSPRenderBatch..."
            
            # Rendu du premier lot via fonction Globale
            Invoke-AppSPRenderBatch -ParentNode $ParentNode -Ctrl $Ctrl
            
            if ($lB) { 
                $msg = "$($subFolders.Count) dossiers trouvés dans : $path"
                Write-AppLog -Message $msg -Level Success -RichTextBox $lB 
            }
        }
        catch {
            if ($lB) { Write-AppLog -Message "[$engName] Erreur : $_" -Level Error -RichTextBox $lB }
        }
        finally {
            if ($overlay) { $overlay.Visibility = "Collapsed" }
            $Window.Cursor = [System.Windows.Input.Cursors]::Arrow
        }
    }

    # Proxy pour la sélection initiale
    $PopulateProxy = $PopulateNodeInternal

    # 2. Event SÉLECTION BIBLIOTHÈQUE -> Init (v4.2)
    $Ctrl.CbLibs.Add_SelectionChanged({
            try {
                $lib = $this.SelectedItem
                $c = $Ctrl
            
                if ($lib -is [System.Management.Automation.PSCustomObject] -and $c.CbSites.SelectedItem) {
                    Write-Verbose "[CbLibs] Sélection (v4.2) : '$($lib.Title)'"
                
                    if ($c.TargetTree) {
                        $c.TargetTree.Items.Clear()
                        
                        $rootItem = New-Object System.Windows.Controls.TreeViewItem
                        $rootItem.SetResourceReference([System.Windows.Controls.TreeViewItem]::StyleProperty, "ModernTreeViewItemStyle")
                        $rootItem.Header = $lib.Title
                        $rootItem.IsExpanded = $true
                        $rootItem.Tag = [PSCustomObject]@{
                            Name              = "Racine"
                            DriveId           = $lib.DriveId
                            ItemId            = "root"
                            SiteId            = $lib.SiteId
                            FullPath          = "/$($lib.Title)"
                            ServerRelativeUrl = if ($lib.RootFolder) { $lib.RootFolder.ServerRelativeUrl } else { "/" }
                        }
                    
                        $c.TargetTree.Items.Add($rootItem) | Out-Null
                        
                        if ($PopulateProxy) { & $PopulateProxy -ParentNode $rootItem }
                    }
                }
            }
            catch {
                Write-AppLog -Message "CRASH CbLibs (v4.2) : $_" -Level Error -RichTextBox $Ctrl.LogBox
            }
        }.GetNewClosure())

    # 3. Événement TreeView Centralisé (v4.5)
    $exTV = $Ctrl.TargetTree
    if ($exTV) {
        Write-Verbose "[Register-SiteEvents] Branchement événements TreeView OK."
        Write-AppLog -Message "Système d'exploration SharePoint initialisé (v4.5)." -Level Success -RichTextBox $Ctrl.LogBox
        
        # A. Gestionnaire Expansion Global (Bubbling)
        $ExpansionHandler = {
            param($s, $e)
            try {
                $item = $e.OriginalSource
                if ($item -is [System.Windows.Controls.TreeViewItem]) {
                    if ($item.Tag -eq "ACTION_LOAD_MORE") { return }
                    
                    # LOG DE DIAGNOSTIC WPF (v4.17)
                    $nodeName = if ($item.Tag -and $item.Tag.Name) { $item.Tag.Name } 
                    elseif ($item.Header -is [System.Windows.Controls.StackPanel]) { "Dossier" }
                    else { $item.Header }

                    Write-Verbose "[v4.17] Event Expansion capté sur: $nodeName"
                    
                    if ($item.Items.Count -eq 1 -and $item.Items[0].Tag -eq "DUMMY_TAG") {
                        if ($PopulateProxy) { & $PopulateProxy -ParentNode $item }
                    }
                }
            }
            catch { Write-Warning "Crash Expansion v4.2 : $_" }
        }.GetNewClosure()

        $exTV.AddHandler([System.Windows.Controls.TreeViewItem]::ExpandedEvent, [System.Windows.RoutedEventHandler]$ExpansionHandler)

        # B. Événement Sélection (Diagnostic souhaité par l'utilisateur)
        # C. Événement CLIC DIRECT (v4.5)
        $exTV.Add_PreviewMouseLeftButtonUp({
                param($sender, $e)
                try {
                    $item = $e.OriginalSource
                    while ($item -and -not ($item -is [System.Windows.Controls.TreeViewItem])) {
                        $item = [System.Windows.Media.VisualTreeHelper]::GetParent($item)
                    }

                    if ($item -and $item.Tag) {
                        # 1. CAS BOUTON "LOAD MORE" (v4.10)
                        if ($item.Tag -eq "ACTION_LOAD_MORE") {
                            # Remonter au TreeViewItem Parent
                            $parent = [System.Windows.Media.VisualTreeHelper]::GetParent($item)
                            while ($parent -and -not ($parent -is [System.Windows.Controls.TreeViewItem])) {
                                $parent = [System.Windows.Media.VisualTreeHelper]::GetParent($parent)
                            }
                        
                            if ($parent) {
                                $parentName = if ($parent.Tag -and $parent.Tag.Name) { $parent.Tag.Name } else { $parent.Header }
                                Write-Verbose "[v4.17] Clic Load More détecté pour : $parentName"
                                Invoke-AppSPRenderBatch -ParentNode $parent -Ctrl $Ctrl
                            }
                            else {
                                Write-Warning "[v4.17] Impossible de trouver le parent de Load More !"
                            }
                            return
                        }

                        # 2. CAS DOSSIER STANDARD
                        if ($item.Tag -is [System.Management.Automation.PSCustomObject]) {
                            # LOG DE CLIC (Diagnostic)
                            Write-AppLog -Message "Clic détecté sur : $($item.Tag.FullPath)" -Level Info -RichTextBox $Ctrl.LogBox
                        
                            if ($item.Items.Count -eq 1 -and "$($item.Items[0].Tag)" -eq "DUMMY_TAG") {
                                Write-AppLog -Message "Chargement Forcé (Dummy détecté) pour : $($item.Tag.Name)" -Level Warning -RichTextBox $Ctrl.LogBox
                                if ($PopulateProxy) { & $PopulateProxy -ParentNode $item }
                                $item.IsExpanded = $true
                            }
                        }
                    }
                }
                catch { Write-Warning "Crash Click v4.5 : $_" }
            }.GetNewClosure())

        $exTV.Add_SelectedItemChanged({
                param($sender, $e)
                try {
                    $item = $sender.SelectedItem
                    if ($item -and $item.Tag -is [System.Management.Automation.PSCustomObject]) {
                        $folderData = $item.Tag
                        $Global:SelectedTargetFolder = $folderData
                        
                        # --- Logic Point 1.1 : On-Demand Loading via Selected (v4.3/v4.4) ---
                        if ($item.Items.Count -eq 1 -and "$($item.Items[0].Tag)" -eq "DUMMY_TAG") {
                            Write-Verbose "[v4.4] Déclenchement chargement via Sélection pour : $($item.Tag.Name)"
                            if ($PopulateProxy) { & $PopulateProxy -ParentNode $item }
                            $item.IsExpanded = $true 
                        }

                        # LOG DE SÉLECTION (Nouveauté v4.2)
                        if ($Ctrl.LogBox) {
                            $isPending = ($item.Items.Count -eq 1 -and "$($item.Items[0].Tag)" -eq "DUMMY_TAG")
                            $isLoaded = if ($isPending) { "[En attente]" } else { "[Chargé]" }
                            Write-AppLog -Message "Sélection dossier : $($item.Tag.FullPath) $isLoaded" -Level Info -RichTextBox $Ctrl.LogBox
                        }
                        
                        $st = $Window.FindName("TargetFolderStatusText")
                        if ($st) { $st.Text = $folderData.ServerRelativeUrl }
                        
                        if ($PreviewLogic) { & $PreviewLogic }
                    }
                }
                catch { Write-Warning "Crash Selection v4.4 : $_" }
            }.GetNewClosure())
    }
}
