# Scripts/Sharepoint/SharepointBuilderV2/Functions/Logic/Invoke-AppSPDeployFilter.ps1

<#
.SYNOPSIS
    Gère le filtrage en cascade des modèles et formulaires SharePoint.
.DESCRIPTION
    Filtre les ComboBoxes 'Modèles' et 'Formulaires' en fonction du schéma (Content Type) sélectionné.
    Gère la restauration de la sélection précédente si elle est toujours valide.
#>
function Global:Invoke-AppSPDeployFilter {
    param(
        [hashtable]$Ctrl,
        [scriptblock]$InvalidateState
    )

    $v = "v4.18"
    Write-Verbose "[$v] Application du filtre en cascade..."

    $selItem = $Ctrl.CbFolderSchema.SelectedItem
    $schema = if ($selItem -and $selItem.Tag) { $selItem.Tag } else { $null }
    $schemaId = if ($schema) { $schema.SchemaId } else { "" }

    Write-AppLog -Message "Filtrage par schéma : $(if($schemaId){$schemaId}else{'Aucun'})" -Level Info -RichTextBox $Ctrl.LogBox
    
    # --- 1. Filtrage des Architectures (Step 2) ---
    $oldTplId = $null
    if ($Ctrl.CbTemplates.SelectedItem -and $Ctrl.CbTemplates.SelectedItem.TemplateId) {
        $oldTplId = $Ctrl.CbTemplates.SelectedItem.TemplateId
    }
    
    $freshTemplates = @(Get-AppSPTemplates)
    $filteredTpls = $freshTemplates
    if ($schemaId) {
        $filteredTpls = $freshTemplates | Where-Object { 
            try {
                $struct = $_.StructureJson | ConvertFrom-Json
                return $struct.TargetSchemaId -eq $schemaId
            } catch { return $false }
        }
    }
    $Ctrl.CbTemplates.ItemsSource = @($filteredTpls)
    $Ctrl.CbTemplates.DisplayMemberPath = "DisplayName"
    
    # Restauration
    if ($oldTplId) {
        $matchingIndex = -1
        for ($i = 0; $i -lt $filteredTpls.Count; $i++) {
            if ($filteredTpls[$i].TemplateId -eq $oldTplId) { $matchingIndex = $i; break }
        }
        $Ctrl.CbTemplates.SelectedIndex = $matchingIndex
    } else {
        $Ctrl.CbTemplates.SelectedIndex = -1
    }

    # --- 2. Filtrage des Formulaires (Step 3) ---
    $oldRuleId = $null
    if ($Ctrl.CbFolderTemplates.SelectedItem -and $Ctrl.CbFolderTemplates.SelectedItem.RuleId) {
        $oldRuleId = $Ctrl.CbFolderTemplates.SelectedItem.RuleId
    }

    $freshRules = @(Get-AppNamingRules)
    $filteredRules = $freshRules
    if ($schemaId) {
        $filteredRules = $freshRules | Where-Object {
            try {
                $def = $_.DefinitionJson | ConvertFrom-Json
                return $def.TargetSchemaId -eq $schemaId
            } catch { return $false }
        }
    }
    $Ctrl.CbFolderTemplates.ItemsSource = @($filteredRules)
    $Ctrl.CbFolderTemplates.DisplayMemberPath = "RuleId"
    
    # Restauration
    if ($oldRuleId) {
        $matchingRuleIndex = -1
        for ($i = 0; $i -lt $filteredRules.Count; $i++) {
            if ($filteredRules[$i].RuleId -eq $oldRuleId) { $matchingRuleIndex = $i; break }
        }
        $Ctrl.CbFolderTemplates.SelectedIndex = $matchingRuleIndex
    } else {
        $Ctrl.CbFolderTemplates.SelectedIndex = -1
    }

    # --- 3. État des contrôles ---
    $Ctrl.ChkCreateFolder.IsEnabled = [bool]$schemaId
    if (-not $schemaId) { $Ctrl.ChkCreateFolder.IsChecked = $false }
    
    # Invalidation générale
    if ($InvalidateState) { & $InvalidateState }
}
