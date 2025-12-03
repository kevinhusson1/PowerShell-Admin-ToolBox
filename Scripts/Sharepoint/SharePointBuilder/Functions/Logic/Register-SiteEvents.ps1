# Scripts/SharePoint/SharePointBuilder/Functions/Logic/Register-SiteEvents.ps1

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
            } catch { throw $_ }
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
                    } else {
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
            } catch {
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
                $realData  = $rawResults | Where-Object { $_ -isnot [string] -or ($_ -notlike "JOB_*") }

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
                } else {
                    $sitesArray = @($realData)
                    $Global:AllSharePointSites = $sitesArray
                    
                    if ($sitesArray.Count -gt 0) {
                        $safeCb.ItemsSource = $sitesArray
                        $safeCb.DisplayMemberPath = "Title"
                        $safeCb.IsEnabled = $true
                        Write-AppLog -Message "$($sitesArray.Count) sites chargés." -Level Success -RichTextBox $safeLog
                    } else {
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
            if ($e.Key -in 'Up','Down','Enter','Tab') { return }
            $filterText = $sender.Text
            if ($Global:AllSharePointSites) {
                if ([string]::IsNullOrWhiteSpace($filterText)) {
                    $sender.ItemsSource = $Global:AllSharePointSites
                } else {
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
                    } catch { throw $_ }
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
                        } else {
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

    # --- D. EVENT COMMUN ---
    $Ctrl.CbLibs.Add_SelectionChanged({
        $lib = $this.SelectedItem
        if ($lib -is [System.Management.Automation.PSCustomObject]) {
            $safeLog = $Window.FindName("LogRichTextBox")
            $safeSiteCb = $Window.FindName("SiteComboBox")

            if ($safeLog -and $safeSiteCb.SelectedItem) {
                try {
                    $siteUri = [System.Uri]$safeSiteCb.SelectedItem.Url
                    $rootUrl = "$($siteUri.Scheme)://$($siteUri.Host)"
                    $fullLibUrl = "$rootUrl$($lib.RootFolder.ServerRelativeUrl)"
                    if (-not $Context.AutoLibraryName) {
                        Write-AppLog -Message "Bibliothèque : $($lib.Title)" -Level Info -RichTextBox $safeLog
                        Write-AppLog -Message "URL : $fullLibUrl" -Level Info -RichTextBox $safeLog
                    }
                } catch {}
            }
        }
        if ($null -ne $PreviewLogic) { & $PreviewLogic } 
    }.GetNewClosure())
}