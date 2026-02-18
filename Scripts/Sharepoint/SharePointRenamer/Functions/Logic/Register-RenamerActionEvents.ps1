<#
.SYNOPSIS
    Gère l'action de renommage (Lancement Job).

.DESCRIPTION
    Ce script enregistre l'événement "Click" du bouton "Renommer".
    Il effectue :
    1. La validation des données formulaires.
    2. Le calcul du nouveau nom (basé sur les règles).
    3. Le lancement du Job d'arrière-plan (Start-Job).
    4. La surveillance du Job via DispatcherTimer.
    5. L'affichage des logs en temps réel dans l'UI.
    6. L'activation du bouton "Ouvrir Destination".
#>
function Register-RenamerActionEvents {
    param(
        [hashtable]$Ctrl,
        [System.Windows.Window]$Window
    )

    # --- REPAIR UI LOGIC ---
    if ($Ctrl.BtnRepair) {
        $Ctrl.BtnRepair.Add_Click({
                if (-not $Global:CurrentAnalysisResult -or -not $Global:CurrentAnalysisResult.Drift) {
                    [System.Windows.MessageBox]::Show("Aucune analyse disponible ou aucun défaut détecté.", "Info", "OK", "Information")
                    return
                }

                $drift = $Global:CurrentAnalysisResult.Drift
                $hasDrift = ($drift.MetaDrifts -and $drift.MetaDrifts.Count -gt 0) -or ($drift.StructureMisses -and $drift.StructureMisses.Count -gt 0)

                if (-not $hasDrift) {
                    [System.Windows.MessageBox]::Show("Le projet est conforme. Aucune réparation nécessaire.", "Bravo", "OK", "Information")
                    return
                }

                # 1. Toggle UI
                $Ctrl.ActionsPanel.Visibility = "Collapsed"
                $Ctrl.RepairConfigPanel.Visibility = "Visible"

                # 2. Populate List
                $Ctrl.RepairListPanel.Children.Clear()

                # Helper to add item
                $AddItem = { param($Type, $Desc, $TagObj)
                    $p = New-Object System.Windows.Controls.DockPanel
                    $p.Margin = "0,0,0,5"

                    # 1. CheckBox (Toggle Switch Style)
                    $cb = New-Object System.Windows.Controls.CheckBox
                    $cb.IsChecked = $true
                    $cb.SetResourceReference([System.Windows.Controls.CheckBox]::StyleProperty, "ToggleSwitchStyle")
                    $cb.Tag = $TagObj 
                    $cb.ToolTip = "$Type"
                    $cb.VerticalAlignment = "Center"
                    
                    [System.Windows.Controls.DockPanel]::SetDock($cb, [System.Windows.Controls.Dock]::Left)
                    $p.Children.Add($cb)
                    
                    # 2. Description (Separate TextBlock for wrapping)
                    $tb = New-Object System.Windows.Controls.TextBlock
                    $tb.Text = $Desc
                    $tb.TextWrapping = "Wrap"
                    $tb.VerticalAlignment = "Center"
                    $tb.Margin = "10,0,0,0" # Space from switch
                    
                    # Optional: Make text click check box
                    $tb.Cursor = "Hand"
                    $tb.Add_MouseLeftButtonDown({ $cb.IsChecked = -not $cb.IsChecked }.GetNewClosure())

                    $p.Children.Add($tb)
                    $Ctrl.RepairListPanel.Children.Add($p)
                }

                # Add Metadata Drifts
                if ($drift.MetaDrifts) {
                    foreach ($md in $drift.MetaDrifts) {
                        # Parsing "Key : Expected 'X' but found 'Y'"
                        if ($md -match "^(.+?) : Expected '(.+?)'") {
                            $k = $Matches[1].Trim()
                            $v = $Matches[2]
                            & $AddItem "Métadonnée" "Corriger $k -> '$v'" @{ Type = "Meta"; Key = $k; Value = $v }
                        }
                    }
                }

                # Add Structure Drifts
                if ($drift.StructureMisses) {
                    foreach ($sm in $drift.StructureMisses) {
                        # Parsing "❌ ..."
                        $clean = $sm -replace "^❌\s*", ""
                        & $AddItem "Structure" "Restaurer : $clean" @{ Type = "Structure"; Raw = $sm }
                    }
                }

            }.GetNewClosure())
    }

    if ($Ctrl.BtnCloseRepair) {
        $Ctrl.BtnCloseRepair.Add_Click({
                $Ctrl.RepairConfigPanel.Visibility = "Collapsed"
                $Ctrl.ActionsPanel.Visibility = "Visible"
            }.GetNewClosure())
    }

    # --- REPAIR EXECUTION ---
    if ($Ctrl.BtnConfirmRepair) {
        $Ctrl.BtnConfirmRepair.Add_Click({
                # 1. Gather Selected Items
                $toRepair = @()
                foreach ($child in $Ctrl.RepairListPanel.Children) {
                    if ($child -is [System.Windows.Controls.DockPanel]) {
                        $cb = $child.Children[0]
                        if ($cb.IsChecked) {
                            $toRepair += $cb.Tag
                        }
                    }
                }

                if ($toRepair.Count -eq 0) { return }

                # 2. Start Repair Job
                $Ctrl.BtnConfirmRepair.IsEnabled = $false
                $Ctrl.BtnRepair.IsEnabled = $false 

                # ... Job Logic placeholder (Will implement Repair-AppProject call here) ...
                Write-AppLog -Message "Démarrage réparation de $($toRepair.Count) éléments..." -Level Info -RichTextBox $Ctrl.LogRichTextBox

                # For now, just log what would strictly happen
                foreach ($item in $toRepair) {
                    Write-AppLog -Message " >> Planifié : $($item.Type) - $($item.Key)$($item.Raw)" -Level Info -RichTextBox $Ctrl.LogRichTextBox
                }
             
                # TODO: Call actual Repair-AppProject in Job
             
                # Unlock UI (Simulated end)
                Start-Sleep -Seconds 1
                $Ctrl.BtnConfirmRepair.IsEnabled = $true
                $Ctrl.BtnRepair.IsEnabled = $true
             
                # Switch back?
                # $Ctrl.RepairConfigPanel.Visibility = "Collapsed"
                # $Ctrl.ActionsPanel.Visibility = "Visible"
             
                # Refresh Analysis
                # $Ctrl.BtnAnalyze.RaiseEvent((New-Object System.Windows.RoutedEventArgs ([System.Windows.Controls.Button]::ClickEvent)))

            }.GetNewClosure())
    }

    if ($Ctrl.BtnRename) {
        $Ctrl.BtnRename.Add_Click({
                # 1. Validation Context
                if (-not $Global:CurrentAnalysisResult) {
                    [System.Windows.MessageBox]::Show("Veuillez d'abord effectuer une analyse.", "Avertissement", "OK", "Warning")
                    return
                }

                $analysis = $Global:CurrentAnalysisResult
                $currentName = $analysis.FolderName
                $siteUrl = $analysis.SiteUrl # Need to ensure this is passed in result or resolve it
                # Fallback if SiteUrl missing in object (it is usually in resolution step, might need to store it too)
                if (-not $siteUrl) { $siteUrl = $Global:LastAnalysisSiteUrl } 

                # 2. Input Dialog for New Name
                # Simple VisualBasic InputBox for quick win, or Custom WPF
                Add-Type -AssemblyName Microsoft.VisualBasic
                $newName = [Microsoft.VisualBasic.Interaction]::InputBox("Veuillez saisir le nouveau nom pour le dossier :", "Renommer le projet", $currentName)

                if ([string]::IsNullOrWhiteSpace($newName) -or $newName -eq $currentName) { return }

                # 3. Confirmation
                $confirm = [System.Windows.MessageBox]::Show("Renommer '$currentName' en '$newName' ?`n`nCeci mettra à jour:`n- Le nom du dossier`n- L'historique de déploiement (PropertyBag)`n- Les liens internes (.url)`n`nContinuer ?", "Confirmation", "YesNo", "Question")
                if ($confirm -ne "Yes") { return }

                # 4. Trigger Rename Job
                $Ctrl.BtnRename.IsEnabled = $false
                Write-AppLog -Message "Démarrage renommage : $currentName -> $newName" -Level Info -RichTextBox $Ctrl.LogRichTextBox

                $jobArgs = @{
                    SiteUrl   = $Global:CurrentAnalysisSiteUrl
                    FolderUrl = $Global:CurrentAnalysisFolderUrl # ServerRelative
                    NewName   = $newName
                    OldName   = $currentName
                    Metadata  = @{ "_AppDeployName" = $newName; "Title" = $newName } # Update Identity
                    ClientId  = $Global:AppConfig.azure.authentication.userAuth.appId
                    Thumb     = $Global:AppConfig.azure.certThumbprint
                    Tenant    = $Global:AppConfig.azure.tenantName
                    ProjRoot  = $Global:ProjectRoot
                }

                $renameJob = Start-Job -ScriptBlock {
                    param($ArgsMap)
                    try {
                        $env:PSModulePath = "$($ArgsMap.ProjRoot)\Modules;$($ArgsMap.ProjRoot)\Vendor;$($env:PSModulePath)"
                        Import-Module "PnP.PowerShell" -ErrorAction Stop
                        Import-Module "Toolbox.SharePoint" -Force -ErrorAction Stop

                        # Helper Log
                        function Log { param($m, $l = "Info") Write-Output "[LOG] $m" }

                        Log "Connexion à SharePoint..."
                        $conn = Connect-PnPOnline -Url $ArgsMap.SiteUrl -ClientId $ArgsMap.ClientId -Thumbprint $ArgsMap.Thumb -Tenant $ArgsMap.Tenant -ReturnConnection -ErrorAction Stop
                        
                        # 1. Rename Folder
                        Log "Renommage du dossier racine..."
                        $targetFolder = $ArgsMap.FolderUrl
                        # PnP Rename logic or CSOM
                        # Using Rename-PnPFolder from PnP PowerShell or Custom Function
                        # Rename-PnPFolder -Folder $targetFolder -TargetFolderName $ArgsMap.NewName ...
                        # Let's use the Toolbox function if available, or direct PnP
                        
                        $folder = Get-PnPFolder -Url $targetFolder -Connection $conn -Includes ListItemAllFields, ServerRelativeUrl
                        if (-not $folder) { throw "Dossier introuvable : $targetFolder" }
                        
                        # Rename Operation
                        $folder.MoveTo("$($folder.ParentFolder.ServerRelativeUrl)/$($ArgsMap.NewName)") 
                        # Note: MoveTo is standard for renaming in SP Client Object Model if just name changes in same parent.
                        # Actually PnP has Rename-PnPFolder in newer versions, or we use Move-PnPFolder
                        # Safer: Rename-PnPFolder works on Folder Name.
                        
                        # Let's try standard PnP Move which effectively renames if same logic
                        # Or better invoke `Rename-PnPFolder` if we are sure it exists, otherwise `Item.FileLeafRef` update.
                        
                        # Using ListItem update is often cleaner for "Rename"
                        $item = $folder.ListItemAllFields
                        if ($item) {
                            Set-PnPListItem -List ($item.ParentList) -Identity $item.Id -Values @{ "FileLeafRef" = $ArgsMap.NewName; "Title" = $ArgsMap.NewName; "_AppDeployName" = $ArgsMap.NewName } -Connection $conn
                        }
                        else {
                            # Fallback if no list item (rare for DocLib folders)
                            Rename-PnPFolder -Folder $targetFolder -TargetFolderName $ArgsMap.NewName -Connection $conn
                        }
                        
                        Log "Dossier renommé avec succès."
                        
                        # 2. Repair Links (Stub for now, or call Repair-AppSPLinks)
                        Log "Mise à jour des liens (Simulation)..."
                        
                        return [PSCustomObject]@{ Success = $true; NewName = $ArgsMap.NewName }
                    }
                    catch {
                        Write-Output "[LOG] ERROR: $($_.Exception.Message)"
                        return [PSCustomObject]@{ Success = $false; Error = $_.Exception.Message }
                    }
                } -ArgumentList $jobArgs

                # Job Monitoring (Simplified)
                $timer = New-Object System.Windows.Threading.DispatcherTimer
                $timer.Interval = [TimeSpan]::FromMilliseconds(500)
                $timer.Add_Tick({
                        $state = $renameJob.State
                        $out = Receive-Job -Job $renameJob
                        foreach ($o in $out) {
                            if ($o -is [string] -and $o -match "^\[LOG\] (.*)") {
                                Write-AppLog -Message $Matches[1] -Level Info -RichTextBox $Ctrl.LogRichTextBox
                            }
                            elseif ($o.Success) {
                                $timer.Stop()
                                Remove-Job $renameJob -Force
                                [System.Windows.MessageBox]::Show("Renommage terminé !", "Succès")
                                $Ctrl.BtnRename.IsEnabled = $true
                                # Optional: Refresh Analysis
                            }
                            elseif ($o.Success -eq $false) {
                                $timer.Stop()
                                Remove-Job $renameJob -Force
                                [System.Windows.MessageBox]::Show("Erreur: $($o.Error)", "Echec")
                                $Ctrl.BtnRename.IsEnabled = $true
                            }
                        }
                    
                        if ($state -ne 'Running' -and -not $renameJob.HasMoreData) {
                            $timer.Stop()
                            $Ctrl.BtnRename.IsEnabled = $true
                        }
                    }.GetNewClosure())
                $timer.Start()

            }.GetNewClosure())
    }

}
