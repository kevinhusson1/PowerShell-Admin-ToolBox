<#
.SYNOPSIS
    Gère l'action de renommage (Lancement Job).
#>
function Register-RenamerActionEvents {
    param(
        [hashtable]$Ctrl,
        [System.Windows.Window]$Window
    )

    # Logging Helper
    $Log = { param($msg, $lvl = "Info") 
        Write-AppLog -Message $msg -Level $lvl -Collection $Global:AppLogCollection 
        if ($Ctrl.LogBox) {
            $Ctrl.LogBox.Dispatcher.Invoke([Action] {
                    $Ctrl.LogBox.AppendText("[$([DateTime]::Now.ToString('HH:mm:ss'))] $msg`r`n")
                    $Ctrl.LogBox.ScrollToEnd()
                })
        }
    }.GetNewClosure()

    if ($Ctrl.BtnRename) {
        $Ctrl.BtnRename.Add_Click({
                $cfg = $Ctrl.ListBox.SelectedItem
                $folder = $Ctrl.TargetFolderBox.Tag
            
                if (-not $cfg -or -not $folder) { return }

                # 1. Validation & Data Extraction
                $allData = @{ FormValues = @{}; RootMetadata = @{} }
            
                # Helper Recursive (similaire à Deployer)
                function Get-FormDataRecursive {
                    param($root, $accum)
                    if ($root -is [System.Windows.Controls.Panel]) {
                        foreach ($child in $root.Children) { Get-FormDataRecursive -root $child -accum $accum }
                    }
                    elseif ($root -is [System.Windows.Controls.ContentControl] -and $root.Content -is [System.Windows.UIElement]) {
                        Get-FormDataRecursive -root $root.Content -accum $accum
                    }
                
                    # Check IDs
                    if ($root -is [System.Windows.UIElement] -and $root.Tag) {
                        $key = $null
                        $isMeta = $false
                        if ($root.Tag -is [System.Collections.IDictionary]) {
                            $key = $root.Tag.Key
                            $isMeta = $root.Tag.IsMeta
                        }
                        elseif ($root.Tag -is [string]) { $key = $root.Tag }
                    
                        if ($key) {
                            $val = $null
                            # TextBlock (Label as Variable), TextBox, ComboBox
                            if ($root -is [System.Windows.Controls.TextBox]) { $val = $root.Text }
                            elseif ($root -is [System.Windows.Controls.ComboBox]) { $val = $root.SelectedItem }
                            elseif ($root -is [System.Windows.Controls.TextBlock]) { $val = $root.Text }
                        
                            if ($val) {
                                $accum.FormValues[$key] = $val
                                if ($isMeta) { $accum.RootMetadata[$key] = $val }
                            }
                        }
                    }
                }
                Get-FormDataRecursive -root $Ctrl.DynamicFormPanel -accum $allData
                $formData = $allData.FormValues
                $rootMetadata = $allData.RootMetadata
            
                # Validation Vide
                # (Simplifié : on assume que l'utilisateur sait ce qu'il fait ou que le template n'a pas changé)
            
                # 2. Construction Nom Dossier
                # On réutilise la Preview
                $newName = $Ctrl.FolderNamePreview.Text
                if ([string]::IsNullOrWhiteSpace($newName)) {
                    [System.Windows.MessageBox]::Show("Le nom calculé est vide.")
                    return 
                }
            
                # Confirm
                $msg = "Vous allez renommer le dossier :`n'$($folder.Name)'`n`nVers :`n'$newName'`n`nCette opération modifiera également les métadonnées et tentera de réparer les liens internes.`nConfirmer ?"
                $res = [System.Windows.MessageBox]::Show($msg, "Confirmation", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
                if ($res -ne "Yes") { return }
            
                # 3. Preparation Job
                $Ctrl.BtnRename.IsEnabled = $false
                $Ctrl.BtnPickFolder.IsEnabled = $false
                $Ctrl.ListBox.IsEnabled = $false
            
                & $Log "Démarrage de la maintenance..." "Info"
                & $Log "Cible : $($folder.ServerRelativeUrl)" "Info"
                & $Log "Nouveau Nom : $newName" "Info"
                & $Log "Métadonnées à jour : $($rootMetadata.Keys -join ', ')" "Info"
            
                $jobArgs = @{
                    ModPath   = Join-Path $Global:ProjectRoot "Modules"
                    Thumb     = $Global:AppConfig.azure.certThumbprint
                    ClientId  = $Global:AppConfig.azure.authentication.userAuth.appId
                    Tenant    = $Global:AppConfig.azure.tenantName
                    SiteUrl   = $cfg.SiteUrl
                    TargetUrl = $folder.ServerRelativeUrl
                    NewName   = $newName
                    Metadata  = $rootMetadata
                }
            
                $job = Start-Job -ScriptBlock {
                    param($ArgsMap)
                    $env:PSModulePath = "$($ArgsMap.ModPath);$($env:PSModulePath)"
                    Import-Module "Toolbox.SharePoint" -Force
                
                    try {
                        $conn = Connect-PnPOnline -Url $ArgsMap.SiteUrl -ClientId $ArgsMap.ClientId -Thumbprint $ArgsMap.Thumb -Tenant $ArgsMap.Tenant -ReturnConnection -ErrorAction Stop
                    
                        # 1. Renommage Atomic
                        $resRename = Rename-AppSPFolder -TargetFolderUrl $ArgsMap.TargetUrl -NewFolderName $ArgsMap.NewName -Metadata $ArgsMap.Metadata -Connection $conn
                        if (-not $resRename.Success) { throw $resRename.Message }
                    
                        Write-Output "RENAME_OK"
                        Write-Output $resRename.Message
                    
                        # 2. Réparation Liens
                        # Old Root = TargetUrl
                        # New Root = NewUrl from result
                        $newRoot = $resRename.NewUrl
                    
                        Write-Output "Scan et réparation des liens en cours..."
                        $resRepair = Repair-AppSPLinks -RootFolderUrl $newRoot -OldRootUrl $ArgsMap.TargetUrl -NewRootUrl $newRoot -Connection $conn
                    
                        Write-Output "Réparation terminée. Scannés: $($resRepair.ProcessedCount), Corrigés: $($resRepair.FixedCount)"
                        if ($resRepair.Errors.Count -gt 0) {
                            Write-Output "Erreurs liens : $($resRepair.Errors -join '; ')"
                        }
                    
                    }
                    catch {
                        Write-Output "ERROR: $($_.Exception.Message)"
                        throw $_
                    }
                } -ArgumentList $jobArgs
            
                # Timer Monitoring
                $timer = New-Object System.Windows.Threading.DispatcherTimer
                $timer.Interval = [TimeSpan]::FromMilliseconds(500)
                $timer.Add_Tick({
                        $state = Get-Job -Id $job.Id
                
                        # Read Output
                        $output = Receive-Job -Id $job.Id -Keep
                        if ($output) {
                            Receive-Job -Id $job.Id | ForEach-Object {
                                if ($_ -is [string]) {
                                    if ($_ -eq "RENAME_OK") { return } # Skip marker
                                    if ($_ -match "^ERROR:") { & $Log $_ "Error" }
                                    else { & $Log $_ "Info" }
                                }
                            }
                        }
                
                        if ($state.State -eq "Completed" -or $state.State -eq "Failed") {
                            $timer.Stop()
                            Remove-Job -Id $job.Id
                            $Ctrl.BtnRename.IsEnabled = $true
                            $Ctrl.BtnPickFolder.IsEnabled = $true
                            $Ctrl.ListBox.IsEnabled = $true
                    
                            if ($state.State -eq "Completed") {
                                [System.Windows.MessageBox]::Show("Opération terminée avec succès.", "Succès", "OK", "Information")
                                # Reset UI? Maybe let user see result.
                            }
                            else {
                                [System.Windows.MessageBox]::Show("L'opération a échoué. Consultez les logs.", "Erreur", "OK", "Error")
                            }
                        }
                    })
                $timer.Start()
            })
    }
}
