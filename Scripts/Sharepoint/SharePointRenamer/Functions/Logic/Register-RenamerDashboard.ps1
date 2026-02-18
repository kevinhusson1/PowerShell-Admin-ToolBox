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

                    $driftPath = Join-Path $ArgsMap.ProjRoot "Modules\Toolbox.SharePoint\Functions\Logic\Test-AppSPDrift.ps1"
                    if (Test-Path $driftPath) { . $driftPath } else { Write-Output "[LOG] ERROR: Script not found: $driftPath" }
        
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
                        # LOGGING DIRECT (FIX: Use TickCtrl directly)
                        if ($item -is [string] -and $item.StartsWith("[LOG]")) {
                            $msg = $item.Substring(5).Trim()
                            if ($TickCtrl.LogRichTextBox) {
                                Write-AppLog -Message $msg -Level "Info" -RichTextBox $TickCtrl.LogRichTextBox
                            }
                        }
                        # FINAL RESULT OBJECT
                        elseif ($item -is [PSCustomObject] -and $item.PSObject.Properties['Exists']) {
                            
                            $timer.Stop()
                            
                            if ($TickCtrl) {
                                # UI Updates
                                if ($TickCtrl.LoadingPanel) { 
                                    $TickCtrl.LoadingPanel.Visibility = "Collapsed" 
                                }

                                if ($TickCtrl.BtnAnalyze) { $TickCtrl.BtnAnalyze.IsEnabled = $true }
                                
                                # --- SUCCESS : DISPLAY DASHBOARD ---
                                if ($TickCtrl.DashboardPanel) { 
                                    $TickCtrl.DashboardPanel.Visibility = "Visible" 
                                }

                                $res = $item 
                                
                                if ($res.Error) {
                                    if ($TickCtrl.ErrorPanel) { $TickCtrl.ErrorPanel.Visibility = "Visible" }
                                    if ($TickCtrl.ErrorText) { $TickCtrl.ErrorText.Text = $res.Error }
                                    
                                    if ($TickCtrl.LogRichTextBox) {
                                        Write-AppLog -Message "Echec: $($res.Error)" -Level "Error" -RichTextBox $TickCtrl.LogRichTextBox
                                    }
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
                                        $ver = if ($res.HistoryItem) { $res.HistoryItem.TemplateVersion } else { "?" }
                                    
                                        if ($TickCtrl.TextStatus) { $TickCtrl.TextStatus.Text = "SUIVI (v$ver)" }
                                        if ($TickCtrl.BadgeStatus) { $TickCtrl.BadgeStatus.Background = [System.Windows.Media.Brushes]::MintCream }
                                    
                                        if ($TickCtrl.TextConfig) { $TickCtrl.TextConfig.Text = "Config: $($res.HistoryItem.ConfigName)" }
                                        if ($TickCtrl.KpiVersion) { $TickCtrl.KpiVersion.Text = "v$ver" }
                                    
                                    
                                        # [DRIFT] Populate KPI with Real Analysis
                                        if ($res.Drift) {
                                            # STRUCTURE
                                            if ($res.Drift.StructureStatus -eq "OK") {
                                                $TickCtrl.KpiStructure.Text = "Conforme"
                                                $TickCtrl.KpiStructure.Foreground = [System.Windows.Media.Brushes]::Green
                                            }
                                            else {
                                                $TickCtrl.KpiStructure.Text = $res.Drift.StructureStatus
                                                $TickCtrl.KpiStructure.Foreground = [System.Windows.Media.Brushes]::Orange
                                            }

                                            # META
                                            if ($res.Drift.MetaStatus -eq "OK") {
                                                $TickCtrl.KpiMeta.Text = "Sync"
                                                $TickCtrl.KpiMeta.Foreground = [System.Windows.Media.Brushes]::Green
                                            } 
                                            elseif ($res.Drift.MetaStatus -eq "DRIFT") {
                                                $TickCtrl.KpiMeta.Text = "Différence"
                                                $TickCtrl.KpiMeta.Foreground = [System.Windows.Media.Brushes]::OrangeRed
                                                $TickCtrl.KpiMeta.ToolTip = ($res.Drift.MetaDrifts -join "`n")
                                            }
                                            else {
                                                $TickCtrl.KpiMeta.Text = $res.Drift.MetaStatus
                                                $TickCtrl.KpiMeta.Foreground = [System.Windows.Media.Brushes]::Gray
                                            }
                                        }
                                        else {
                                            if ($TickCtrl.KpiStructure) { $TickCtrl.KpiStructure.Text = "?" }
                                            if ($TickCtrl.KpiMeta) { $TickCtrl.KpiMeta.Text = "?" }
                                        }

                                        if ($TickCtrl.MetaGrid) { $TickCtrl.MetaGrid.Children.Clear() }
                                    
                                        if ($res.HistoryItem.FormValuesJson) {
                                            try {
                                                $formVals = $res.HistoryItem.FormValuesJson | ConvertFrom-Json
                                                $row = 0
                                                $driftKeys = @{}
                                                if ($res.Drift -and $res.Drift.MetaDrifts) {
                                                    foreach ($d in $res.Drift.MetaDrifts) {
                                                        # format: "Key : Expected 'X' but found 'Y'"
                                                        if ($d -match "^(.+?) :") {
                                                            $k = $Matches[1].Trim()
                                                            $driftKeys[$k] = $d
                                                        }
                                                    }
                                                }

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

                                                    # Highlight Drift
                                                    if ($driftKeys.ContainsKey($prop.Name)) {
                                                        $val.Foreground = [System.Windows.Media.Brushes]::OrangeRed
                                                        $val.FontWeight = "Bold"
                                                        $val.ToolTip = $driftKeys[$prop.Name]
                                                        $lbl.Foreground = [System.Windows.Media.Brushes]::OrangeRed
                                                    }

                                                    $TickCtrl.MetaGrid.Children.Add($lbl)
                                                    $TickCtrl.MetaGrid.Children.Add($val)
                                                    $row++
                                                }
                                            }
                                            catch {}
                                        }
                                    } 
                                    else {
                                        if ($TickCtrl.TextStatus) { $TickCtrl.TextStatus.Text = "NON GÉRÉ" }
                                        if ($TickCtrl.BadgeStatus) { $TickCtrl.BadgeStatus.Background = [System.Windows.Media.Brushes]::MistyRose }
                                        if ($TickCtrl.TextConfig) { $TickCtrl.TextConfig.Text = "Aucune configuration" }
                                        if ($TickCtrl.MetaGrid) { $TickCtrl.MetaGrid.Children.Clear() }
                                        if ($TickCtrl.KpiVersion) { $TickCtrl.KpiVersion.Text = "-" }
                                        if ($TickCtrl.KpiStructure) { $TickCtrl.KpiStructure.Text = "-" }
                                        if ($TickCtrl.KpiMeta) { $TickCtrl.KpiMeta.Text = "-" }
                                    }
                                }
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
    
    # [FIX] Action Handlers
    if ($Ctrl.BtnRepair) {
        $Ctrl.BtnRepair.Add_Click({
                [System.Windows.MessageBox]::Show("Fonctionnalité 'Réparer' en cours de développement.", "Info")
            }.GetNewClosure())
    }
    
    if ($Ctrl.BtnRename) {
        $Ctrl.BtnRename.Add_Click({
                [System.Windows.MessageBox]::Show("Fonctionnalité 'Renommer' en cours de développement.", "Info")
            }.GetNewClosure())
    }

    # [FIX] Forget Action Handler (Confirmation Only for now)
    if ($Ctrl.BtnForget) {
        $Ctrl.BtnForget.Add_Click({
                $res = [System.Windows.MessageBox]::Show("Êtes-vous sûr de vouloir oublier ce projet ?`n`nCette action supprimera le suivi de déploiement (PropertyBag) mais ne supprimera pas les fichiers.", "Confirmation", "YesNo", "Warning")
                if ($res -eq "Yes") {
                    [System.Windows.MessageBox]::Show("Action 'Oublier' non encore implémentée (Phase 3).", "Info")
                }
            }.GetNewClosure())
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
