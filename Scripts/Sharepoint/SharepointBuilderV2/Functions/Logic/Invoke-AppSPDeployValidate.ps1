# Scripts/Sharepoint/SharepointBuilderV2/Functions/Logic/Invoke-AppSPDeployValidate.ps1

<#
.SYNOPSIS
    Orchestrateur de validation pour le déploiement SharePoint.
.DESCRIPTION
    Exécute les tests de cohérence sur le modèle (Test-AppSPModel) et vérifie la triade
    Schéma / Architecture / Formulaire. Met à jour l'interface en conséquence.
#>
function Global:Invoke-AppSPDeployValidate {
    param(
        [hashtable]$Ctrl,
        [System.Windows.Window]$Window,
        [hashtable]$ValidationState
    )

    $v = "v4.18"
    Write-Verbose "[$v] Démarrage de la validation globale..."

    # 1. UI LOCK & FEEDBACK
    $Ctrl.BtnValidate.IsEnabled = $false
    $oldCursor = [System.Windows.Input.Mouse]::OverrideCursor
    [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait

    try {
        Write-AppLog -Message (Get-AppLocalizedString -Key "sp_builder.log_validation_start") -Level Info -RichTextBox $Ctrl.LogBox
    
        # FORCE UI REFRESH
        $Ctrl.LogBox.Dispatcher.Invoke([Action] {}, [System.Windows.Threading.DispatcherPriority]::Background)
    
        # Reset avant check
        $Ctrl.BtnDeploy.IsEnabled = $false
        $ValidationState.IsValid = $false
        
        # Helper interne pour la mise à jour du statut de sauvegarde (BtnSaveConfig)
        $updateSave = {
            $hasSite = ($null -ne $Ctrl.CbSites.SelectedItem -and $Ctrl.CbSites.SelectedItem -isnot [string])
            $hasLib = ($null -ne $Ctrl.CbLibs.SelectedItem -and $Ctrl.CbLibs.SelectedItem -isnot [string] -and $Ctrl.CbLibs.SelectedItem -ne "Chargement...")
            $hasTpl = ($null -ne $Ctrl.CbTemplates.SelectedItem)
            $Ctrl.BtnSaveConfig.IsEnabled = ($hasSite -and $hasLib -and $hasTpl -and $ValidationState.IsValid)
        }

        $selTemplate = $Ctrl.CbTemplates.SelectedItem
        if (-not $selTemplate) {
            Write-AppLog -Message (Get-AppLocalizedString -Key "sp_builder.log_no_template") -Level Warning -RichTextBox $Ctrl.LogBox
            return 
        }

        try {
            $structure = $selTemplate.StructureJson | ConvertFrom-Json
        
            # S'assurer que le module SharePoint est dispo
            if (-not (Get-Command "Test-AppSPModel" -ErrorAction SilentlyContinue)) {
                if ($Global:ProjectRoot) {
                    Import-Module (Join-Path $Global:ProjectRoot "Modules\Toolbox.SharePoint") -Force
                }
            }

            # --- PRÉPARATION VALIDATION ---
            $params = @{ StructureData = $structure }

            Write-AppLog -Message (Get-AppLocalizedString -Key "sp_builder.log_validation_conn_active") -Level Info -RichTextBox $Ctrl.LogBox
            if ($Ctrl.CbLibs.SelectedItem -and $Ctrl.CbLibs.SelectedItem -isnot [string]) {
                $params.TargetLibraryName = $Ctrl.CbLibs.SelectedItem.Title
            }

            # Refresh UI
            $Ctrl.LogBox.Dispatcher.Invoke([Action] {}, [System.Windows.Threading.DispatcherPriority]::Background)

            $issues = Test-AppSPModel @params
    
            # --- CHECK COHÉRENCE TRIADE ---
            $selSchema = $Ctrl.CbFolderSchema.SelectedItem
            $selRule = $Ctrl.CbFolderTemplates.SelectedItem
            
            if ($selSchema -and $selSchema.Tag -and $selTemplate) {
                $targetSchemaId = $selSchema.Tag.SchemaId
                $tplStruct = $selTemplate.StructureJson | ConvertFrom-Json
                if ($tplStruct.TargetSchemaId -and $tplStruct.TargetSchemaId -ne $targetSchemaId) {
                    $issues += [PSCustomObject]@{ Status = "Error"; NodeName = "Template"; Message = "L'architecture sélectionnée ne correspond pas au schéma choisi ($($tplStruct.TargetSchemaId) vs $targetSchemaId)." }
                }

                if ($selRule) {
                    $ruleDef = $selRule.DefinitionJson | ConvertFrom-Json
                    if ($ruleDef.TargetSchemaId -and $ruleDef.TargetSchemaId -ne $targetSchemaId) {
                        $issues += [PSCustomObject]@{ Status = "Error"; NodeName = "NamingRule"; Message = "Le formulaire sélectionné ne correspond pas au schéma choisi ($($ruleDef.TargetSchemaId) vs $targetSchemaId)." }
                    }
                }
            }

            if ($issues.Count -eq 0) {
                Write-AppLog -Message (Get-AppLocalizedString -Key "sp_builder.log_validation_success") -Level Success -RichTextBox $Ctrl.LogBox
            
                # SUCCESS : Activation des boutons
                $ValidationState.IsValid = $true
                $Ctrl.BtnDeploy.IsEnabled = $true
                & $updateSave
            }
            else {
                $errCount = ($issues | Where-Object { $_.Status -eq 'Error' }).Count
                if ($errCount -gt 0) {
                    $msgFailed = (Get-AppLocalizedString -Key "sp_builder.log_validation_failed") -f $errCount
                    Write-AppLog -Message $msgFailed -Level Error -RichTextBox $Ctrl.LogBox
                }
                else {
                    Write-AppLog -Message (Get-AppLocalizedString -Key "sp_builder.log_validation_warning") -Level Warning -RichTextBox $Ctrl.LogBox
                    $ValidationState.IsValid = $true
                    $Ctrl.BtnDeploy.IsEnabled = $true
                    & $updateSave
                }

                foreach ($issue in $issues) {
                    $icon = switch ($issue.Status) { "Error" { "❌" } "Warning" { "⚠️" } Default { "ℹ️" } }
                    $logLvl = switch ($issue.Status) { "Error" { "Error" } "Warning" { "Warning" } Default { "Info" } }
                    Write-AppLog -Message "   $icon [$($issue.NodeName)] : $($issue.Message)" -Level $logLvl -RichTextBox $Ctrl.LogBox
                }
            }
        }
        catch {
            $msgTech = (Get-AppLocalizedString -Key "sp_builder.log_validation_tech_error") -f $_.Exception.Message
            Write-AppLog -Message $msgTech -Level Error -RichTextBox $Ctrl.LogBox
        }
    }
    finally {
        # RESTORE UI
        $Ctrl.BtnValidate.IsEnabled = $true
        [System.Windows.Input.Mouse]::OverrideCursor = $oldCursor
    }
}
