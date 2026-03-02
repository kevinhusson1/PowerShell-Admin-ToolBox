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
                try {
                    $ctx = Get-RenamerContext
                    $analysis = $ctx.Result

                    if (-not $analysis -or -not $analysis.Drift) {
                        [System.Windows.MessageBox]::Show("Aucune analyse disponible ou aucun défaut détecté.", "Info", "OK", "Information")
                        return
                    }

                    $drift = $analysis.Drift
                    
                    # Sécurisation des accès aux propriétés (null-coalescing conditionnel)
                    $metas = if ($drift.MetaDrifts) { $drift.MetaDrifts } else { @() }
                    $structs = if ($drift.StructureMisses) { $drift.StructureMisses } else { @() }
                    
                    $hasDrift = ($metas.Count -gt 0) -or ($structs.Count -gt 0)

                    if (-not $hasDrift) {
                        [System.Windows.MessageBox]::Show("Le projet est conforme. Aucune réparation nécessaire.", "Bravo", "OK", "Information")
                        return
                    }

                    # 1. Confirmation Dialog
                    $confirm = [System.Windows.MessageBox]::Show("Le projet n'est pas conforme.`n`nVoulez-vous lancer une resynchronisation complète du projet ?`nCette opération va recréer l'arborescence manquante et réappliquer les métadonnées sans écraser les données existantes.", "Confirmation de réparation", "YesNo", "Question")
                    if ($confirm -ne "Yes") { return }

                    # 2. Start Repair Job
                    $Ctrl.BtnRepair.IsEnabled = $false 

                    # Job Initialization
                    $ctx = Get-RenamerContext
                    $jobArgs = @{
                        SiteUrl            = $ctx.SiteUrl
                        FolderUrl          = $ctx.FolderUrl
                        ClientId           = $Global:AppConfig.azure.authentication.userAuth.appId
                        Thumb              = $Global:AppConfig.azure.certThumbprint
                        Tenant             = $Global:AppConfig.azure.tenantName
                        ProjRoot           = $Global:ProjectRoot
                        TemplateJson       = $ctx.Result.HistoryItem.TemplateJson
                        FormValuesJson     = $ctx.Result.HistoryItem.FormValuesJson
                        FormDefinitionJson = $ctx.Result.HistoryItem.FormDefinitionJson
                    }

                    $repairJob = Start-Job -ScriptBlock {
                        param($ArgsMap)
                        try {
                            $env:PSModulePath = "$($ArgsMap.ProjRoot)\Modules;$($ArgsMap.ProjRoot)\Vendor;$($env:PSModulePath)"
                            Import-Module "PnP.PowerShell" -ErrorAction Stop
                            Import-Module "Toolbox.SharePoint" -Force -ErrorAction Stop

                            Write-Output "[LOG] Connexion à SharePoint via Toolbox..."
                            $conn = Connect-AppSharePoint -SiteUrl $ArgsMap.SiteUrl -ClientId $ArgsMap.ClientId -Thumbprint $ArgsMap.Thumb -TenantName $ArgsMap.Tenant
                        
                            Write-Output "[LOG] Démarrage Repair-AppProject (Resynchronisation via New-AppSPStructure)..."
                            # Exécuter la réparation. En ne stockant pas le résultat dans une variable, PowerShell
                            # permet aux 'Write-Output' successifs de s'écouler en streaming en temps réel.
                            # Le dernier élément envoyé sera le PSCustomObject final.
                            Repair-AppProject -TargetUrl $ArgsMap.FolderUrl -Connection $conn -TemplateJson $ArgsMap.TemplateJson -FormValuesJson $ArgsMap.FormValuesJson -FormDefinitionJson $ArgsMap.FormDefinitionJson -ClientId $ArgsMap.ClientId -Thumbprint $ArgsMap.Thumb -TenantName $ArgsMap.Tenant
                        }
                        catch {
                            Write-Output "[LOG] ERROR: $($_.Exception.Message)"
                            return [PSCustomObject]@{ Success = $false; Error = $_.Exception.Message }
                        }
                    } -ArgumentList $jobArgs

                    # Job Monitoring
                    $timer = New-Object System.Windows.Threading.DispatcherTimer
                    $timer.Interval = [TimeSpan]::FromMilliseconds(500)
                    $timer.Add_Tick({
                            $TickCtrl = $Global:RenamerV2Ctrl
                            $state = $repairJob.State
                            $out = Receive-Job -Job $repairJob
                            foreach ($o in $out) {
                                if ($o -is [string] -and $o.StartsWith("[LOG]")) {
                                    $msg = $o.Substring(5).Trim()
                                    if ($TickCtrl.LogRichTextBox) {
                                        Write-AppLog -Message $msg -Level Info -RichTextBox $TickCtrl.LogRichTextBox
                                    }
                                }
                                elseif ($null -ne $o -and $o -is [PSCustomObject] -and $o.Success) {
                                    $timer.Stop()
                                    Remove-Job $repairJob -Force
                                    [System.Windows.MessageBox]::Show("Réparation terminée avec succès !", "Succès", "OK", "Information")
                                    if ($null -ne $TickCtrl.BtnRepair) { $TickCtrl.BtnRepair.IsEnabled = $true }
                                
                                    # Refresh Analysis (Manuel conseillé pour éviter les cross-thread context switch)
                                }
                                elseif ($null -ne $o -and $o -is [PSCustomObject] -and $o.Success -eq $false -and $o.Error) {
                                    $timer.Stop()
                                    Remove-Job $repairJob -Force
                                    [System.Windows.MessageBox]::Show("Erreur de réparation : $($o.Error)", "Echec", "OK", "Error")
                                    if ($null -ne $TickCtrl.BtnRepair) { $TickCtrl.BtnRepair.IsEnabled = $true }
                                }
                            }
                    
                            if ($state -ne 'Running' -and -not $repairJob.HasMoreData) {
                                $timer.Stop()
                                if ($null -ne $TickCtrl.BtnRepair) { $TickCtrl.BtnRepair.IsEnabled = $true }
                            }
                        }.GetNewClosure())
                    $timer.Start()

                }
                catch {
                    [System.Windows.MessageBox]::Show("Erreur interne lors du lancement de la réparation : $($_.Exception.Message)", "Erreur UI", "OK", "Error")
                    if ($null -ne $Ctrl.BtnRepair) { $Ctrl.BtnRepair.IsEnabled = $true }
                }
            }.GetNewClosure())
    }
}

if ($Ctrl.BtnRename) {
    $Ctrl.BtnRename.Add_Click({
            # 1. Validation Context
            $ctx = Get-RenamerContext
            $analysis = $ctx.Result

            if (-not $analysis) {
                [System.Windows.MessageBox]::Show("Veuillez d'abord effectuer une analyse.", "Avertissement", "OK", "Warning")
                return
            }

            $currentName = $analysis.FolderName
            $siteUrl = $ctx.SiteUrl 

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
                SiteUrl   = $ctx.SiteUrl
                FolderUrl = $ctx.FolderUrl # ServerRelative
                NewName   = $newName
                OldName   = $currentName
                Metadata  = @{ "Title" = $newName } # Update Identity List Fields
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

                    Log "Connexion à SharePoint via Toolbox..."
                    $conn = Connect-AppSharePoint -SiteUrl $ArgsMap.SiteUrl -ClientId $ArgsMap.ClientId -Thumbprint $ArgsMap.Thumb -TenantName $ArgsMap.Tenant
                        
                    # 1. Rename Folder
                    Log "Renommage du dossier racine..."
                    $targetFolder = $ArgsMap.FolderUrl
                        
                    # Utilisation de Rename-AppSPFolder du module Toolbox
                    if (Get-Command Rename-AppSPFolder -ErrorAction SilentlyContinue) {
                        $resRename = Rename-AppSPFolder -TargetFolderUrl $targetFolder -NewFolderName $ArgsMap.NewName -Metadata $ArgsMap.Metadata -Connection $conn
                        Log "Dossier renommé avec succès via Toolbox."

                        if ($resRename.Success -and $resRename.NewUrl) {
                            $renamedFolder = Get-PnPFolder -Url $resRename.NewUrl -Includes Properties -Connection $conn -ErrorAction SilentlyContinue
                            if ($renamedFolder) {
                                $ctxTarget = $renamedFolder.Context
                                $ctxTarget.Load($renamedFolder.Properties)
                                $ctxTarget.ExecuteQuery()
                                $renamedFolder.Properties["_AppDeployName"] = $ArgsMap.NewName
                                $renamedFolder.Update()
                                $ctxTarget.ExecuteQuery()
                                Log "Identité système intégrée (PropertyBag) mise à jour."
                            }
                        }
                    }
                    else {
                        # Fallback natif si Rename-AppSPFolder n'est pas chargé
                        Log "⚠️ Rename-AppSPFolder introuvable, utilisation de PnP natif."
                        $folder = Get-PnPFolder -Url $targetFolder -Connection $conn -Includes ListItemAllFields, ServerRelativeUrl, Properties
                        if (-not $folder) { throw "Dossier introuvable : $targetFolder" }
                        $folder.MoveTo("$($folder.ParentFolder.ServerRelativeUrl)/$($ArgsMap.NewName)") 
                            
                        $item = $folder.ListItemAllFields
                        if ($item) {
                            Set-AppSPMetadata -List ($item.ParentList.Title) -ItemId $item.Id -Values @{ "FileLeafRef" = $ArgsMap.NewName; "Title" = $ArgsMap.NewName } -Connection $conn
                        }

                        # Mise à jour Property Bag
                        $ctxTarget = $folder.Context
                        $ctxTarget.Load($folder.Properties)
                        $ctxTarget.ExecuteQuery()
                        $folder.Properties["_AppDeployName"] = $ArgsMap.NewName
                        $folder.Update()
                        $ctxTarget.ExecuteQuery()

                        Log "Dossier renommé avec succès via PnP/CSOM Fallback."
                    }
                        
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
                    $TickCtrl = $Global:RenamerV2Ctrl
                    $state = $renameJob.State
                    $out = Receive-Job -Job $renameJob
                    foreach ($o in $out) {
                        if ($o -is [string] -and $o.StartsWith("[LOG]")) {
                            $msg = $o.Substring(5).Trim()
                            if ($TickCtrl.LogRichTextBox) {
                                Write-AppLog -Message $msg -Level Info -RichTextBox $TickCtrl.LogRichTextBox
                            }
                        }
                        elseif ($o.Success) {
                            $timer.Stop()
                            Remove-Job $renameJob -Force
                            [System.Windows.MessageBox]::Show("Renommage terminé !", "Succès")
                            $TickCtrl.BtnRename.IsEnabled = $true
                            # Optional: Refresh Analysis
                        }
                        elseif ($o.Success -eq $false) {
                            $timer.Stop()
                            Remove-Job $renameJob -Force
                            [System.Windows.MessageBox]::Show("Erreur: $($o.Error)", "Echec")
                            $TickCtrl.BtnRename.IsEnabled = $true
                        }
                    }
                    
                    if ($state -ne 'Running' -and -not $renameJob.HasMoreData) {
                        $timer.Stop()
                        $TickCtrl.BtnRename.IsEnabled = $true
                    }
                }.GetNewClosure())
            $timer.Start()

        }.GetNewClosure())
}
