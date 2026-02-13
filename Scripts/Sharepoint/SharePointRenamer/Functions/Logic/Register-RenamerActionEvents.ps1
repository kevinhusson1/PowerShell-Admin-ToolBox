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

    if ($Ctrl.BtnRename) {
        $Ctrl.BtnRename.Add_Click({
                # Logging Helper (Defined INSIDE closure to ensure visibility)
                function Write-RenamerLog {
                    param($msg, $lvl = "Info")
                    Write-AppLog -Message $msg -Level $lvl -Collection $Global:AppLogCollection 
                    if ($Ctrl.LogBox) {
                        $Ctrl.LogBox.Dispatcher.Invoke([Action] {
                                $Ctrl.LogBox.AppendText("[$([DateTime]::Now.ToString('HH:mm:ss'))] $msg`r`n")
                                $Ctrl.LogBox.ScrollToEnd()
                            })
                    }
                }

                # Robust Retrieval
                $listBox = $Ctrl.ListBox
                if (-not $listBox -and $Window) { $listBox = $Window.FindName("ConfigListBox") }
                
                $cfg = $null
                if ($listBox) { $cfg = $listBox.SelectedItem }
                
                $folder = $Ctrl.TargetFolderBox.Tag
            
                if (-not $cfg -or -not $folder) { return }

                # 1. Validation & Data Extraction
                $allData = @{ FormValues = @{}; RootMetadata = @{} }
            
                # Helper Recursive (Updated to match Deployer Logic / Robust Global Use)
                if (Get-Command "Find-ControlRecursive" -ErrorAction SilentlyContinue) {
                    # On utilise la fonction globale mais attention, elle cherche UN control par tag.
                    # Ici on veut *scanner* le FormDynamicStack.
                    
                    $dynStack = Find-ControlRecursive -parent $Ctrl.DynamicFormPanel -tagName "FormDynamicStack"
                    
                    if ($dynStack) {
                        foreach ($child in $dynStack.Children) {
                            $key = $null
                            $isMeta = $false
                            
                            if ($child.Tag -is [System.Collections.IDictionary]) {
                                $key = $child.Tag.Key
                                $isMeta = $child.Tag.IsMeta
                            }
                            elseif ($child.Tag -is [string]) { $key = $child.Tag }
                            
                            if ($key) {
                                $val = $null
                                if ($child -is [System.Windows.Controls.TextBox]) { $val = $child.Text }
                                elseif ($child -is [System.Windows.Controls.ComboBox]) { $val = $child.SelectedItem }
                                elseif ($child -is [System.Windows.Controls.TextBlock]) { $val = $child.Text }
                                
                                if ($val) {
                                    $allData.FormValues[$key] = $val
                                    if ($isMeta) { $allData.RootMetadata[$key] = $val }
                                }
                            }
                        }
                    }
                    else {
                        # Stack not found, silent or log verbose
                    }
                }
                
                $formData = $allData.FormValues
                $rootMetadata = $allData.RootMetadata
            
                # Validation Vide
                # (Simplifié : on assume que l'utilisateur sait ce qu'il fait ou que le template n'a pas changé)
            
                # 2. Construction Nom Dossier (Robust: Recalculate instead of relying on Preview)
                $newName = ""
                
                # Fetch Rule
                $rules = Get-AppNamingRules
                $targetRule = $rules | Where-Object { $_.RuleId -eq $cfg.TargetFolder } | Select-Object -First 1
                
                if ($targetRule) {
                    try {
                        $layout = ($targetRule.DefinitionJson | ConvertFrom-Json).Layout
                        foreach ($elem in $layout) {
                            if ($elem.Type -eq "Label") { $newName += $elem.Content }
                            elseif ($formData[$elem.Name]) { $newName += $formData[$elem.Name] }
                        }
                    }
                    catch {
                        Write-Host "DEBUG: Error calculating name: $_"
                    }
                }
                
                if ([string]::IsNullOrWhiteSpace($newName)) {
                    # Fallback to Preview if calculation fails (or if manual edit allowed later)
                    $newName = $Ctrl.FolderNamePreview.Text
                }

                if ([string]::IsNullOrWhiteSpace($newName) -or $newName -eq "...") {
                    [System.Windows.MessageBox]::Show("Le nom calculé est vide.")
                    return 
                }
            
                # Confirm
                $msg = "Vous allez renommer le dossier :`n'$($folder.Name)'`n`nVers :`n'$newName'`n`nCette opération modifiera également les métadonnées et tentera de réparer les liens internes.`nConfirmer ?"
                $res = [System.Windows.MessageBox]::Show($msg, "Confirmation", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
                if ($res -ne "Yes") { return }
            
                # 3. Preparation Job & Publications Logic
                $Ctrl.BtnRename.IsEnabled = $false
                $Ctrl.BtnPickFolder.IsEnabled = $false
                $Ctrl.ListBox.IsEnabled = $false
            
                Write-RenamerLog "Démarrage de la maintenance..." "Info"
                Write-RenamerLog "Cible : $($folder.ServerRelativeUrl)" "Info"
                Write-RenamerLog "Nouveau Nom : $newName" "Info"
                Write-RenamerLog "Métadonnées à jour : $($rootMetadata.Keys -join ', ')" "Info"
                
                # --- [LOGIC] RECHERCHE DES PUBLICATIONS À METTRE À JOUR ---
                # [DEEP UPDATE STRATEGY]
                # Au lieu de chercher manuellement, on va passer le JSON complet au Job
                # et lancer New-AppSPStructure sur le dossier renommé.
                
                $structureJson = ""
                if ($cfg.TemplateId) {
                    try {
                        $template = Get-AppSPTemplates -TemplateId $cfg.TemplateId
                        if ($template -and $template.StructureJson) {
                            $structureJson = $template.StructureJson
                        }
                    }
                    catch {
                        Write-RenamerLog "Erreur chargement template : $($_.Exception.Message)" "Warning"
                    }
                }
                
                # Calcul Dossier Parent (Pour New-AppSPStructure)
                # Le dossier Cible actuel est ex: /sites/X/Lib/OldName
                # On veut le Parent: /sites/X/Lib
                $parentUrl = $folder.ServerRelativeUrl.Substring(0, $folder.ServerRelativeUrl.LastIndexOf('/'))

                $jobArgs = @{
                    ModPath         = Join-Path $Global:ProjectRoot "Modules"
                    Thumb           = $Global:AppConfig.azure.certThumbprint
                    ClientId        = $Global:AppConfig.azure.authentication.userAuth.appId
                    Tenant          = $Global:AppConfig.azure.tenantName
                    
                    SiteUrl         = $cfg.SiteUrl
                    LibraryName     = $cfg.LibraryName
                    TargetParentUrl = $parentUrl # Parent folder where the renamed folder resides
                    NewName         = $newName
                    
                    StructureJson   = $structureJson
                    FormValues      = $allData.FormValues # Pour résolution tags dynamiques
                    RootMetadata    = $rootMetadata       # Pour tags racine
                    
                    # Legacy args for Rename/Repair
                    TargetUrl       = $folder.ServerRelativeUrl
                    Metadata        = $rootMetadata 
                }
            
                # ... (Start Job)
                $job = Start-Job -ScriptBlock {
                    param($ArgsMap)
                    
                    & {
                        $VerbosePreference = "SilentlyContinue" # Reduce Noise (PnP/Module loading)
                        
                        $env:PSModulePath = "$($ArgsMap.ModPath);$($env:PSModulePath)"
                        Import-Module "Logging" -Force
                        Import-Module "Toolbox.SharePoint" -Force
                    
                        # Helper Log Local
                        function Log { param($m, $l = "Info") Write-AppLog -Message $m -Level $l }

                        try {
                            Log "Connexion PnP..." "Info"
                            $conn = Connect-PnPOnline -Url $ArgsMap.SiteUrl -ClientId $ArgsMap.ClientId -Thumbprint $ArgsMap.Thumb -Tenant $ArgsMap.Tenant -ReturnConnection -ErrorAction Stop
                            Log "Connexion établie." "Success"

                            # 1. Renommage Atomic
                            Log "Renommage du dossier cible..." "Info"
                            $resRename = Rename-AppSPFolder -TargetFolderUrl $ArgsMap.TargetUrl -NewFolderName $ArgsMap.NewName -Metadata $ArgsMap.Metadata -Connection $conn
                            if (-not $resRename.Success) { throw $resRename.Message }
                        
                            Log "Renommage terminé : $($resRename.Message)" "Success"
                            
                            # Calculate Full URL for Button
                            $newRoot = $resRename.NewUrl
                            $mainUri = New-Object Uri($ArgsMap.SiteUrl)
                            $baseHost = "$($mainUri.Scheme)://$($mainUri.Host)"
                            $fullNewWebUrl = "$baseHost$newRoot"
                            
                            # Emit structured result
                            $resultJson = @{
                                Status = "OK"
                                Params = @{ NewUrlHTML = $fullNewWebUrl }
                            } | ConvertTo-Json -Compress
                            
                            Write-Output "RESULT_DATA:$resultJson"
                        
                            # 2. Réparation Liens
                            Log "Scan et réparation des liens internes (Contenu)..." "Info"
                            $resRepair = Repair-AppSPLinks -RootFolderUrl $newRoot -OldRootUrl $ArgsMap.TargetUrl -NewRootUrl $newRoot -Connection $conn
                        
                            Log "Réparation terminée. Corrigés: $($resRepair.FixedCount)" "Info"
                            
                            # 3. DEEP UPDATE
                            if (-not [string]::IsNullOrWhiteSpace($ArgsMap.StructureJson)) {
                                Log "Lancement de la mise à jour structurelle (Deep Update)..." "Info"
                                
                                $resDeep = New-AppSPStructure `
                                    -TargetSiteUrl $ArgsMap.SiteUrl `
                                    -TargetLibraryName $ArgsMap.LibraryName `
                                    -TargetFolderUrl $ArgsMap.TargetParentUrl `
                                    -RootFolderName $ArgsMap.NewName `
                                    -StructureJson $ArgsMap.StructureJson `
                                    -FormValues $ArgsMap.FormValues `
                                    -RootMetadata $ArgsMap.RootMetadata `
                                    -ClientId $ArgsMap.ClientId `
                                    -Thumbprint $ArgsMap.Thumb `
                                    -Tenant $ArgsMap.Tenant

                                # Relay Logs (Filter empty)
                                if ($resDeep.Logs) {
                                    $resDeep.Logs | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { Log $_ "Info" }
                                }
                                if ($resDeep.Errors) {
                                    $resDeep.Errors | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { Log "$_" "Error" }
                                }
                                
                                if ($resDeep.Success) {
                                    Log "Mise à jour structurelle terminée avec succès." "Success"
                                }
                                else {
                                    Log "Mise à jour structurelle terminée avec des erreurs." "Warning"
                                }
                            }
                            else {
                                Log "Pas de modèle de structure associé. Pas de Deep Update." "Info"
                            }
                            
                        }
                        catch {
                            Log "ERREUR CRITIQUE : $($_.Exception.Message)" "Error"
                            throw $_
                        }
                    } 4>&1 
                    
                } -ArgumentList $jobArgs
                
                # ... (Validation Code) ...
                if (-not $job) {
                    [System.Windows.MessageBox]::Show("Impossible de démarrer le Job.", "Erreur", "OK", "Error")
                    $Ctrl.BtnRename.IsEnabled = $true; return
                }

                # Timer Monitoring
                $timer = New-Object System.Windows.Threading.DispatcherTimer
                $timer.Interval = [TimeSpan]::FromMilliseconds(500)
                
                $logBox = $Ctrl.LogBox
                $btnOpen = $Ctrl.BtnOpenDest
                $jobId = $job.Id

                $timerBlock = {
                    if (-not $jobId) { $timer.Stop(); return }
                    
                    $state = Get-Job -Id $jobId -ErrorAction SilentlyContinue
                    if (-not $state) { return }

                    # Read Output
                    $newItems = Receive-Job -Id $jobId
                    if ($newItems) {
                        $logBox.Dispatcher.Invoke([Action] {
                                foreach ($item in $newItems) {
                                    $msg = ""
                                    $level = "Info"
                                    
                                    if ($item.LogType -eq 'AppLog') {
                                        $msg = $item.Message
                                        $level = $item.Level
                                    }
                                    elseif ($item -is [string]) {
                                        if ($item -match "^RESULT_DATA:(.*)") {
                                            # Special Data Handling
                                            try {
                                                $jsonResult = $matches[1] | ConvertFrom-Json
                                                if ($btnOpen -and $jsonResult.Params.NewUrlHTML) {
                                                    $btnOpen.IsEnabled = $true
                                                    $btnOpen.Tag = $jsonResult.Params.NewUrlHTML
                                                }
                                            }
                                            catch {}
                                            continue 
                                        }
                                        $msg = $item
                                    }
                                    elseif ($item -is [System.Management.Automation.ErrorRecord]) {
                                        $msg = $item.Exception.Message
                                        $level = "Error"
                                    }
                                    else {
                                        $msg = $item.ToString()
                                    }

                                    if (-not [string]::IsNullOrWhiteSpace($msg)) {
                                        # Emoji Mapping
                                        $emoji = switch ($level) {
                                            "Success" { "✅" }
                                            "Warning" { "⚠️" }
                                            "Error" { "❌" }
                                            default { "ℹ️" }
                                        }
                                        
                                        $timestamp = [DateTime]::Now.ToString('HH:mm:ss')
                                        $finalLine = "[$timestamp] $emoji $msg`r`n"
                                        $logBox.AppendText($finalLine)
                                    }
                                }
                                $logBox.ScrollToEnd()
                            })
                    }
                
                    if ($state.State -ne 'Running') {
                        $timer.Stop()
                        Remove-Job -Id $jobId -ErrorAction SilentlyContinue
                            
                        # UI Cleanup
                        if ($Window) {
                            $Window.Dispatcher.Invoke([Action] {
                                    if ($Ctrl.BtnRename) { $Ctrl.BtnRename.IsEnabled = $true }
                                    if ($Ctrl.BtnPickFolder) { $Ctrl.BtnPickFolder.IsEnabled = $true }
                                    if ($Ctrl.ListBox) { $Ctrl.ListBox.IsEnabled = $true }
                                })
                        }
                    
                        if ($state.State -eq 'Completed') {
                            [System.Windows.MessageBox]::Show("Opération terminée.", "Succès", "OK", "Information")
                        }
                        else {
                            [System.Windows.MessageBox]::Show("L'opération a échoué. Consultez les logs.", "Erreur", "OK", "Error")
                        }
                    }
                }.GetNewClosure()

                $timer.Add_Tick($timerBlock)
                $timer.Start()
            }.GetNewClosure())
            
        # Handler for Open Dest Button
        if ($Ctrl.BtnOpenDest) {
            $Ctrl.BtnOpenDest.Add_Click({
                    $url = $Ctrl.BtnOpenDest.Tag
                    if ($url) { Start-Process $url }
                }.GetNewClosure())
        }
    }
}
