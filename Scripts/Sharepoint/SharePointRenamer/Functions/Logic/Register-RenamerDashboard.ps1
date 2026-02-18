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
            
            # [FIX] Store Context for Actions
            $Global:CurrentAnalysisSiteUrl = $resolveInfo.SiteUrl
            $Global:CurrentAnalysisFolderUrl = $resolveInfo.ServerRelativeUrl
            
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
                                $Global:CurrentAnalysisResult = $res # [FIX] Store for Actions 
                                
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
                                    if ($res.FolderName) { $title = $res.FolderName }
                                    elseif ($res.FolderItem) {
                                        if ($res.FolderItem.Title) { $title = $res.FolderItem.Title }
                                        elseif ($res.FolderItem.FileLeafRef) { $title = $res.FolderItem.FileLeafRef }
                                    }
                                    if ($TickCtrl.ProjectTitle) { $TickCtrl.ProjectTitle.Text = $title }
                                    if ($TickCtrl.ProjectUrl) { $TickCtrl.ProjectUrl.Text = $resolveInfo.ServerRelativeUrl }
                                
                                    # Tracking Logic
                                    if ($res.IsTracked) {
                                        try {
                                            $jsonSafe = $null
                                            if ($res.HistoryItem.FormValuesJson) {
                                                $jsonSafe = $res.HistoryItem.FormValuesJson | ConvertFrom-Json
                                            }

                                            # --- 1. HEADER (Title Drift) ---
                                            # Check PreviewText vs FolderName
                                            if ($jsonSafe -and $jsonSafe.PreviewText) {
                                                $expectedName = $jsonSafe.PreviewText
                                                $currentName = $res.FolderName
                                                
                                                # Normalize for comparison
                                                if ($expectedName -ne $currentName) {
                                                    $TickCtrl.ProjectTitle.Text = "$currentName"
                                                    $TickCtrl.ProjectTitle.Foreground = [System.Windows.Media.Brushes]::OrangeRed
                                                    # Add specific warning indicating the expected name
                                                    $TickCtrl.ProjectUrl.Text = "⚠️ Nom attendu : $expectedName`n$($resolveInfo.ServerRelativeUrl)"
                                                    $TickCtrl.ProjectUrl.Foreground = [System.Windows.Media.Brushes]::Red
                                                }
                                            }

                                            $ver = if ($res.HistoryItem) { $res.HistoryItem.TemplateVersion } else { "?" }
                                        
                                            if ($TickCtrl.TextStatus) { $TickCtrl.TextStatus.Text = "SUIVI (v$ver)" }
                                            if ($TickCtrl.TextStatus) { $TickCtrl.TextStatus.Foreground = [System.Windows.Media.Brushes]::Green }
                                        
                                            if ($TickCtrl.TextConfig) { $TickCtrl.TextConfig.Text = "Config: $($res.HistoryItem.ConfigName)" }
                                            if ($TickCtrl.TextDate) { $TickCtrl.TextDate.Text = "Déployé le: $($res.HistoryItem.DeployedDate)" }
                                        
                                            # [DRIFT] Populate KPI
                                            if ($res.Drift) {
                                                # STRUCTURE STATUS
                                                if ($res.Drift.StructureStatus -eq "OK") {
                                                    $TickCtrl.KpiStructure.Text = "Conforme"
                                                    $TickCtrl.KpiStructure.Foreground = [System.Windows.Media.Brushes]::Green
                                                }
                                                else {
                                                    $count = if ($res.Drift.StructureMisses) { $res.Drift.StructureMisses.Count } else { 0 }
                                                    $TickCtrl.KpiStructure.Text = "Non-conforme ($count)"
                                                    $TickCtrl.KpiStructure.Foreground = [System.Windows.Media.Brushes]::Red
                                                }

                                                # META STATUS
                                                if ($res.Drift.MetaStatus -eq "OK") {
                                                    $TickCtrl.KpiMeta.Text = "Sync"
                                                    $TickCtrl.KpiMeta.Foreground = [System.Windows.Media.Brushes]::Green
                                                } 
                                                elseif ($res.Drift.MetaStatus -eq "DRIFT") {
                                                    $count = if ($res.Drift.MetaDrifts) { $res.Drift.MetaDrifts.Count } else { 0 }
                                                    $TickCtrl.KpiMeta.Text = "Divergence ($count)"
                                                    $TickCtrl.KpiMeta.Foreground = [System.Windows.Media.Brushes]::OrangeRed
                                                }
                                                else {
                                                    $TickCtrl.KpiMeta.Text = $res.Drift.MetaStatus
                                                    $TickCtrl.KpiMeta.Foreground = [System.Windows.Media.Brushes]::Gray
                                                }
                                            }

                                            # --- POPULATE UI GRIDS ---
                                            
                                            # 1. METADATA GRID (Right Column)
                                            if ($TickCtrl.MetaGrid) { 
                                                $TickCtrl.MetaGrid.Children.Clear() 
                                            
                                                if ($jsonSafe) {
                                                    $row = 0
                                                    $driftData = @{}
                                                    
                                                    # Parse Drifts to find Expected Values
                                                    if ($res.Drift -and $res.Drift.MetaDrifts) {
                                                        foreach ($d in $res.Drift.MetaDrifts) {
                                                            # Format: "Key : Expected 'X' but found 'Y'"
                                                            if ($d -match "^(.+?) : Expected '(.+?)' but found '(.+?)'") {
                                                                $k = $Matches[1].Trim()
                                                                $exp = $Matches[2]
                                                                $fnd = $Matches[3]
                                                                $driftData[$k] = @{ Expected = $exp; Found = $fnd }
                                                            }
                                                            elseif ($d -match "^(.+?) :") {
                                                                # Fallback
                                                                $k = $Matches[1].Trim()
                                                                $driftData[$k] = @{ Expected = "N/A"; Found = "Erreur" }
                                                            }
                                                        }
                                                    }

                                                    foreach ($prop in $jsonSafe.PSObject.Properties) {
                                                        $TickCtrl.MetaGrid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{Height = "Auto" }))
                                                        
                                                        $lbl = New-Object System.Windows.Controls.TextBlock
                                                        $lbl.Text = "$($prop.Name):"
                                                        $lbl.FontWeight = "SemiBold"
                                                        $lbl.Foreground = [System.Windows.Media.Brushes]::Gray
                                                        $lbl.Margin = "0,0,10,5"
                                                        [System.Windows.Controls.Grid]::SetRow($lbl, $row)
                                                        [System.Windows.Controls.Grid]::SetColumn($lbl, 0)
                                                        
                                                        $val = New-Object System.Windows.Controls.TextBlock
                                                        $val.TextWrapping = "Wrap"
                                                        [System.Windows.Controls.Grid]::SetRow($val, $row)
                                                        [System.Windows.Controls.Grid]::SetColumn($val, 1)

                                                        # Highlight Drift
                                                        if ($driftData.ContainsKey($prop.Name)) {
                                                            $dInfo = $driftData[$prop.Name]
                                                            
                                                            # Display: "TEST test (Attendu: TEST)"
                                                            # Use Run for styling mixed content
                                                            $runFound = New-Object System.Windows.Documents.Run
                                                            $runFound.Text = $dInfo.Found + " "
                                                            $runFound.Foreground = [System.Windows.Media.Brushes]::OrangeRed
                                                            $runFound.FontWeight = "Bold"
                                                            
                                                            $runExp = New-Object System.Windows.Documents.Run
                                                            $runExp.Text = "(Attendu: $($dInfo.Expected))"
                                                            $runExp.Foreground = [System.Windows.Media.Brushes]::Gray
                                                            $runExp.FontSize = 10
                                                            $runExp.FontStyle = "Italic"
                                                            
                                                            $val.Inlines.Add($runFound)
                                                            $val.Inlines.Add($runExp)
                                                            
                                                            $lbl.Foreground = [System.Windows.Media.Brushes]::OrangeRed
                                                        }
                                                        else {
                                                            $val.Text = $prop.Value
                                                        }

                                                        $TickCtrl.MetaGrid.Children.Add($lbl)
                                                        $TickCtrl.MetaGrid.Children.Add($val)
                                                        $row++
                                                    }
                                                }
                                            }

                                            # 2. STRUCTURE GRID (Left Column)
                                            # Using StackPanel (Children.Add)
                                            if ($TickCtrl.StructureGrid) { 
                                                $TickCtrl.StructureGrid.Children.Clear() 
                                            
                                                if ($res.Drift) {
                                                    if ($res.Drift.StructureStatus -eq "OK") {
                                                        $okTxt = New-Object System.Windows.Controls.TextBlock
                                                        $okTxt.Text = "✅ Structure Complète"
                                                        $okTxt.Foreground = [System.Windows.Media.Brushes]::Green
                                                        $TickCtrl.StructureGrid.Children.Add($okTxt)
                                                    }
                                                    elseif ($res.Drift.StructureMisses) {
                                                        if ($Log) { & $Log "Populating StructureGrid with $($res.Drift.StructureMisses.Count) missing items." "Debug" }
                                                        $head = New-Object System.Windows.Controls.TextBlock
                                                        $head.Text = "Eléments manquants ou incorrects :"
                                                        $head.FontWeight = "Bold"
                                                        $head.Foreground = [System.Windows.Media.Brushes]::Red
                                                        $head.Margin = "0,0,0,5"
                                                        $TickCtrl.StructureGrid.Children.Add($head)

                                                        foreach ($miss in $res.Drift.StructureMisses) {
                                                            # $miss already contains "❌ ..." or similar text
                                                            if ($miss -notmatch "^❌") { $miss = "❌ $miss" }
                                                            if ($Log) { & $Log "Adding missing structure item: $miss" "Debug" }

                                                            $errTxt = New-Object System.Windows.Controls.TextBlock
                                                            $errTxt.Text = $miss
                                                            $errTxt.Foreground = [System.Windows.Media.Brushes]::Red
                                                            $errTxt.TextWrapping = "Wrap"
                                                            $errTxt.Margin = "0,2,0,5"
                                                            $TickCtrl.StructureGrid.Children.Add($errTxt)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                        catch {
                                            if ($Log) { & $Log "UI Update Exception: $_" "Error" }
                                            Write-Warning "[Renamer] UI Update Failed: $_"
                                        }

                                    } 
                                    else {
                                        # Not Tracked
                                        try {
                                            if ($TickCtrl.TextStatus) { $TickCtrl.TextStatus.Text = "NON GÉRÉ" }
                                            if ($TickCtrl.TextStatus) { $TickCtrl.TextStatus.Foreground = [System.Windows.Media.Brushes]::Gray }
                                            if ($TickCtrl.TextConfig) { $TickCtrl.TextConfig.Text = "Aucune configuration" }
                                            if ($TickCtrl.MetaGrid) { $TickCtrl.MetaGrid.Children.Clear() }
                                            if ($TickCtrl.StructureGrid) { $TickCtrl.StructureGrid.Children.Clear() }
                                        }
                                        catch {}
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
    
    # [FIX] Action Handlers delegated to Register-RenamerActionEvents.ps1
    # Check Initialize-RenamerLogic.ps1 for registration order.

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
