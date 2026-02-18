function Register-RenamerDashboard {
    param([hashtable]$Ctrl, [System.Windows.Window]$Window)

    # Logging Helper
    $Log = { param($msg, $lvl = "Info") Write-AppLog -Message $msg -Level $lvl -RichTextBox $Ctrl.LogRichTextBox }.GetNewClosure()

    if ($Log) { & $Log "Dashboard V2 (Targeted Mode) initialisé." "Success" }
    
    # Check Critical Controls
    if (-not $Ctrl.BtnAnalyze) {
        Write-Warning "BtnAnalyze introuvable dans XAML."
    }

    # Capture ProjectRoot strictly for the closure
    $Root = $Global:ProjectRoot

    # --- ACTION D'ANALYSE ---
    $AnalyzeAction = {
        try {
            $rawUrl = $Ctrl.TargetUrlBox.Text

            if ([string]::IsNullOrWhiteSpace($rawUrl)) {
                if ($Ctrl.ErrorPanel) { $Ctrl.ErrorPanel.Visibility = "Visible" }
                if ($Ctrl.ErrorText) { $Ctrl.ErrorText.Text = "Veuillez saisir une URL." }
                return
            }

            # UI RESET
            if ($Ctrl.ErrorPanel) { $Ctrl.ErrorPanel.Visibility = "Collapsed" }
            if ($Ctrl.DashboardPanel) { $Ctrl.DashboardPanel.Visibility = "Collapsed" }
            if ($Ctrl.LoadingPanel) { $Ctrl.LoadingPanel.Visibility = "Visible" }
            
            $Ctrl.BtnAnalyze.IsEnabled = $false

            if ($Log) { & $Log "Analyse en cours : $rawUrl" "Info" }

            # 1. RESOLUTION URL
            if (-not (Get-Command "Resolve-AppSharePointUrl" -ErrorAction SilentlyContinue)) {
                try { 
                    $utilsPath = Join-Path $Root "Modules\Toolbox.SharePoint\Functions\Utils\Resolve-AppSharePointUrl.ps1"
                    if (-not (Test-Path $utilsPath)) { throw "File not found at $utilsPath" }
                    . $utilsPath 
                } 
                catch { throw "Helper Loading Failed: $_" }
            }
            
            $resolveInfo = Resolve-AppSharePointUrl -Url $rawUrl
            
            if (-not $resolveInfo.IsValid) {
                if ($Log) { & $Log "URL Invalide: $($resolveInfo.Error)" "Error" }
                $Ctrl.ErrorPanel.Visibility = "Visible"
                $Ctrl.ErrorText.Text = "URL Invalide: $($resolveInfo.Error)"
                $Ctrl.LoadingPanel.Visibility = "Collapsed"
                $Ctrl.BtnAnalyze.IsEnabled = $true
                return
            }
            
            # 2. JOB ASYNCHRONE
            $jobArgs = @{
                SiteUrl   = $resolveInfo.SiteUrl
                FolderUrl = $resolveInfo.ServerRelativeUrl
                ClientId  = $Global:AppConfig.azure.authentication.userAuth.appId
                Thumb     = $Global:AppConfig.azure.certThumbprint
                Tenant    = $Global:AppConfig.azure.tenantName
                ProjRoot  = $Global:ProjectRoot
            }

            $analyzeJob = Start-Job -ScriptBlock {
                param($ArgsMap)
                
                try {
                    $env:PSModulePath = "$($ArgsMap.ProjRoot)\Modules;$($ArgsMap.ProjRoot)\Vendor;$($env:PSModulePath)"
                    
                    Import-Module "PnP.PowerShell" -ErrorAction Stop
                    Import-Module "Toolbox.SharePoint" -Force -ErrorAction Stop
                    
                    # Chargement dynamique du script si pas dans le module encore
                    $funcPath = Join-Path $ArgsMap.ProjRoot "Modules\Toolbox.SharePoint\Functions\Logic\Get-AppProjectStatus.ps1"
                    if (Test-Path $funcPath) { . $funcPath } else { Write-Output "[LOG] ERROR: Script not found: $funcPath" }
        
                    return Get-AppProjectStatus `
                        -SiteUrl $ArgsMap.SiteUrl `
                        -FolderUrl $ArgsMap.FolderUrl `
                        -ClientId $ArgsMap.ClientId `
                        -Thumbprint $ArgsMap.Thumb `
                        -TenantName $ArgsMap.Tenant
                }
                catch {
                    Write-Output "[LOG] JOB CRASH: $($_.Exception.Message)"
                    return [PSCustomObject]@{ Error = "Job Crash: $($_.Exception.Message)" }
                }
            } -ArgumentList $jobArgs

            # 3. TIMER MONITOR (POLLING)
            $timer = New-Object System.Windows.Threading.DispatcherTimer([System.Windows.Threading.DispatcherPriority]::Normal, [System.Windows.Threading.Dispatcher]::CurrentDispatcher)
            $timer.Interval = [TimeSpan]::FromMilliseconds(500)
            $startTime = [DateTime]::Now
            
            $timer.Add_Tick({
                    $elapsed = [DateTime]::Now - $startTime
                    
                    # [FIX] Use Global Reference to bypass Closure Issues
                    $TickCtrl = $Global:RenamerV2Ctrl
                    
                    # --- DEBUG SCOPE ---
                    if (-not $TickCtrl) { 
                        Write-Warning "[TICK] CRITICAL: `$Global:RenamerV2Ctrl is NULL!" 
                    }

                    # --- STREAMING OUTPUT PROTOCOL ---
                    $newOutput = Receive-Job -Job $analyzeJob 
                    
                    if ($newOutput) {
                        # Write-Warning "[TICK] Received $($newOutput.Count) items."
                    }

                    foreach ($item in $newOutput) {
                        # LOGGING DIRECT
                        if ($item -is [string] -and $item.StartsWith("[LOG]")) {
                            $msg = $item.Substring(5).Trim()
                            # Write-Warning "[UI-RECV-LOG] $msg"
                            if ($Log) { & $Log $msg "Info" }
                        }
                        # FINAL RESULT OBJECT
                        elseif ($item -is [PSCustomObject] -and $item.PSObject.Properties['Exists']) {
                            Write-Warning "[UI-RECV-OBJ] Result Object Received! IsTracked=$($item.IsTracked)"
                            
                            $timer.Stop()
                            
                            if ($TickCtrl) {
                                # UI Updates
                                if ($TickCtrl.LoadingPanel) { 
                                    $TickCtrl.LoadingPanel.Visibility = "Collapsed" 
                                    # Write-Warning "[UI-UPDATE] LoadingPanel Collapsed"
                                }

                                if ($TickCtrl.BtnAnalyze) { $TickCtrl.BtnAnalyze.IsEnabled = $true }
                                
                                # --- SUCCESS : DISPLAY DASHBOARD ---
                                if ($TickCtrl.DashboardPanel) { 
                                    $TickCtrl.DashboardPanel.Visibility = "Visible" 
                                }

                                $res = $item 
                                
                                if ($res.Error) {
                                    Write-Warning "[UI-RECV-OBJ] Error in Result: $($res.Error)"
                                    if ($TickCtrl.ErrorPanel) { $TickCtrl.ErrorPanel.Visibility = "Visible" }
                                    if ($TickCtrl.ErrorText) { $TickCtrl.ErrorText.Text = $res.Error }
                                    if ($Log) { & $Log "Echec: $($res.Error)" "Error" }
                                }
                                else {
                                    # Title Logic
                                    $title = "Dossier Inconnu"
                                    if ($res.FolderItem) {
                                        if ($res.FolderItem.Title) { $title = $res.FolderItem.Title }
                                        elseif ($res.FolderItem.FileLeafRef) { $title = $res.FolderItem.FileLeafRef }
                                    }
                                    if ($TickCtrl.ProjectTitle) { $TickCtrl.ProjectTitle.Text = $title }
                                    if ($TickCtrl.ProjectUrl) { $TickCtrl.ProjectUrl.Text = $resolveInfo.ServerRelativeUrl }
                                
                                    # Tracking Logic
                                    if ($res.IsTracked) {
                                        # Write-Warning "[UI-RECV-OBJ] Project is Tracked."
                                        $ver = if ($res.HistoryItem) { $res.HistoryItem.TemplateVersion } else { "?" }
                                    
                                        if ($TickCtrl.TextStatus) { $TickCtrl.TextStatus.Text = "SUIVI (v$ver)" }
                                        if ($TickCtrl.BadgeStatus) { $TickCtrl.BadgeStatus.Background = [System.Windows.Media.Brushes]::MintCream }
                                    
                                        if ($TickCtrl.TextConfig) { $TickCtrl.TextConfig.Text = "Config: $($res.HistoryItem.ConfigName)" }
                                        if ($TickCtrl.KpiVersion) { $TickCtrl.KpiVersion.Text = "v$ver" }

                                        if ($TickCtrl.MetaGrid) { $TickCtrl.MetaGrid.Children.Clear() }
                                    
                                        if ($res.HistoryItem.FormValuesJson) {
                                            try {
                                                $formVals = $res.HistoryItem.FormValuesJson | ConvertFrom-Json
                                                $row = 0
                                                foreach ($prop in $formVals.PSObject.Properties) {
                                                    $TickCtrl.MetaGrid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{Height = "Auto" }))
                                                    
                                                    $lbl = New-Object System.Windows.Controls.TextBlock
                                                    $lbl.Text = "$($prop.Name):"
                                                    $lbl.FontWeight = "SemiBold"
                                                    $lbl.Foreground = [System.Windows.Media.Brushes]::Gray
                                                    $lbl.Margin = "0,0,10,5"
                                                    [System.Windows.Controls.Grid]::SetRow($lbl, $row)
                                                    [System.Windows.Controls.Grid]::SetColumn($lbl, 0)
                                                    
                                                    $val = New-Object System.Windows.Controls.TextBlock
                                                    $val.Text = $prop.Value
                                                    [System.Windows.Controls.Grid]::SetRow($val, $row)
                                                    [System.Windows.Controls.Grid]::SetColumn($val, 1)

                                                    $TickCtrl.MetaGrid.Children.Add($lbl)
                                                    $TickCtrl.MetaGrid.Children.Add($val)
                                                    $row++
                                                }
                                            }
                                            catch {}
                                        }
                                    } 
                                    else {
                                        # Write-Warning "[UI-RECV-OBJ] Project is NOT Tracked."
                                        if ($TickCtrl.TextStatus) { $TickCtrl.TextStatus.Text = "NON GÉRÉ" }
                                        if ($TickCtrl.BadgeStatus) { $TickCtrl.BadgeStatus.Background = [System.Windows.Media.Brushes]::MistyRose }
                                        if ($TickCtrl.TextConfig) { $TickCtrl.TextConfig.Text = "Aucune configuration" }
                                        if ($TickCtrl.MetaGrid) { $TickCtrl.MetaGrid.Children.Clear() }
                                        if ($TickCtrl.KpiVersion) { $TickCtrl.KpiVersion.Text = "-" }
                                    }
                                }
                            }
                            else {
                                Write-Warning "[UI-FATAL] TickCtrl is NULL even with GLOBAL! This is impossible unless init failed."
                            }

                            if ($Window.Resources.Contains("AnalyzeTimer")) { $Window.Resources.Remove("AnalyzeTimer") }
                            return
                        }
                    }

                    # Timeout Logic
                    if ($elapsed.TotalSeconds -gt 45) {
                        $timer.Stop()
                        $analyzeJob | Stop-Job -PassThru | Remove-Job -Force
                        
                        if ($TickCtrl.LoadingPanel) { $TickCtrl.LoadingPanel.Visibility = "Collapsed" }
                        if ($TickCtrl.BtnAnalyze) { $TickCtrl.BtnAnalyze.IsEnabled = $true }
                        if ($TickCtrl.ErrorPanel) { $TickCtrl.ErrorPanel.Visibility = "Visible" }
                        if ($TickCtrl.ErrorText) { $TickCtrl.ErrorText.Text = "Délai d'attente (45s) dépassé." }
                        
                        if ($Window.Resources.Contains("AnalyzeTimer")) { $Window.Resources.Remove("AnalyzeTimer") }
                        return
                    }

                    # Fail-safe
                    if ($analyzeJob.State -ne 'Running' -and (-not $analyzeJob.HasMoreData)) {
                        $timer.Stop()
                        if ($TickCtrl.LoadingPanel) { $TickCtrl.LoadingPanel.Visibility = "Collapsed" }
                        if ($TickCtrl.BtnAnalyze) { $TickCtrl.BtnAnalyze.IsEnabled = $true }
                        if ($TickCtrl.ErrorPanel) { $TickCtrl.ErrorPanel.Visibility = "Visible" }
                        if ($TickCtrl.ErrorText) { $TickCtrl.ErrorText.Text = "Erreur: Le Job s'est terminé sans résultat." }
                        
                        if ($Window.Resources.Contains("AnalyzeTimer")) { $Window.Resources.Remove("AnalyzeTimer") }
                    }

                }.GetNewClosure())

            if ($Window.Resources.Contains("AnalyzeTimer")) { $Window.Resources.Remove("AnalyzeTimer") }
            $Window.Resources.Add("AnalyzeTimer", $timer)
            $timer.Start()
            
        }
        catch {
            [System.Windows.MessageBox]::Show("ERREUR CRITIQUE: $($_.Exception.Message)", "Erreur")
            if ($Log) { & $Log "CRASH: $($_.Exception.Message)" "Error" }
            if ($Ctrl.LoadingPanel) { $Ctrl.LoadingPanel.Visibility = "Collapsed" }
            if ($Ctrl.BtnAnalyze) { $Ctrl.BtnAnalyze.IsEnabled = $true }
        }
    }.GetNewClosure()


    # --- BINDING EVENTS ---
    if ($Ctrl.BtnAnalyze) {
        $Ctrl.BtnAnalyze.Add_Click($AnalyzeAction)
    }

    # Overlay & Auth
    if ($Ctrl.OverlayConnectButton) {
        $Ctrl.OverlayConnectButton.Add_Click({
                $bgBtn = $Window.FindName("ScriptAuthTextButton")
                if ($bgBtn) {
                    $peer = [System.Windows.Automation.Peers.UIElementAutomationPeer]::CreatePeerForElement($bgBtn)
                    if ($peer) { $peer.GetPattern([System.Windows.Automation.Peers.PatternInterface]::Invoke).Invoke() }
                }
            }.GetNewClosure())
    }

    # --- GLOBAL LOAD ACTION ---
    $Global:RenamerLoadAction = { param($UserAuth) 
        $isConnected = if ($UserAuth) { $UserAuth.Connected } else { $false }
        if ($isConnected) {
            # Masquer l'overlay si connecté
            if ($Ctrl.AuthOverlay) { $Ctrl.AuthOverlay.Visibility = "Collapsed" }
        }
        else {
            # Afficher l'overlay si déconnecté
            if ($Ctrl.AuthOverlay) { $Ctrl.AuthOverlay.Visibility = "Visible" }
        }
    }.GetNewClosure()
}
