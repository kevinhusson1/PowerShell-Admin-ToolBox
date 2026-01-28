<#
.SYNOPSIS
    Gère la génération dynamique du formulaire et son hydratation.
#>
function Register-RenamerFormEvents {
    param(
        [hashtable]$Ctrl,
        [System.Windows.Window]$Window
    )

    # Fonction globale rappelée après selection dossier
    $Global:UpdateRenamerForm = {
        
        $cfg = $Ctrl.ListBox.SelectedItem
        $folder = $Ctrl.TargetFolderBox.Tag
        
        if (-not $cfg -or -not $folder) { 
            $Ctrl.FormPanel.Visibility = "Collapsed"
            return 
        }

        $Ctrl.FormPanel.Visibility = "Visible"
        $Ctrl.DynamicFormPanel.Children.Clear()

        # 1. Load Rule
        $ruleId = $cfg.TargetFolder # Rule ID
        $rules = Get-AppNamingRules
        $targetRule = $rules | Where-Object { $_.RuleId -eq $ruleId } | Select-Object -First 1
        
        if (-not $targetRule) {
            [System.Windows.MessageBox]::Show("Règle de nommage '$ruleId' introuvable.")
            return
        }

        # 2. Generate Form
        $layout = ($targetRule.DefinitionJson | ConvertFrom-Json).Layout
        
        # Hydration Data
        $existingMeta = @{}
        if ($folder.ListItemAllFields) {
            $existingMeta = $folder.ListItemAllFields.FieldValues
        }
        # Hydrate Name also? No, Name is calculated. But we can parse? 
        # Too hard to reverse engineer Name. Better rely on Metadata.
        
        $dynamicStack = New-Object System.Windows.Controls.StackPanel
        
        # Preview Action Closure
        $UpdatePreviewAction = {
            # Recalculer le nom
            $builtName = ""
            $data = $Ctrl.DynamicFormPanel # StackPanel
            
            # Simple Scanner (Non-Recursive for flat layout)
            # Layout items match UI children index? Mostly yes if we process sequentially.
            # But better verify tags.
            
            # Re-read inputs
            $inputs = @{}
            foreach ($child in $dynamicStack.Children) {
                # Find input inside the child stack or direct
                # The children added below are TextBlocks, TextBoxes etc directly in DynamicStack?
                # No, standard layout adds them flat.
                
                # Using Helper
                $key = $null
                $val = $null
                
                if ($child.Tag -is [System.Collections.IDictionary]) { $key = $child.Tag.Key }
                elseif ($child.Tag -is [string]) { $key = $child.Tag }
                
                if ($key) {
                    if ($child -is [System.Windows.Controls.TextBox]) { $val = $child.Text }
                    elseif ($child -is [System.Windows.Controls.ComboBox]) { $val = $child.SelectedItem }
                    if ($val) { $inputs[$key] = $val }
                }
            }
            
            # Build
            foreach ($elem in $layout) {
                if ($elem.Type -eq "Label") { $builtName += $elem.Content }
                elseif ($inputs[$elem.Name]) { $builtName += $inputs[$elem.Name] }
            }
            if ($Ctrl.FolderNamePreview) { $Ctrl.FolderNamePreview.Text = $builtName }
        }.GetNewClosure()

        foreach ($elem in $layout) {
            # Width
            $width = 200
            if ($elem.Width -and $elem.Width -match '^\d+$') { $width = [double]$elem.Width }

            if ($elem.Type -eq "Label") {
                $t = New-Object System.Windows.Controls.TextBlock
                $t.Text = $elem.Content
                # Tagging for consistency/future scan
                if ($elem.Name) { $t.Tag = @{ Key = $elem.Name; IsMeta = $elem.IsMetadata } }
                $t.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#00AEEF")
                $t.FontWeight = "Bold"
                $t.VerticalAlignment = "Center"
                $t.Margin = [System.Windows.Thickness]::new(5, 0, 5, 0)
                $dynamicStack.Children.Add($t)
            }
            elseif ($elem.Type -eq "TextBox") {
                $t = New-Object System.Windows.Controls.TextBox
                $t.Tag = @{ Key = $elem.Name; IsMeta = $elem.IsMetadata }
                $t.Width = $width
                $t.VerticalAlignment = "Center"
                 
                # HYDRATION
                if ($existingMeta.ContainsKey($elem.Name)) {
                    $t.Text = $existingMeta[$elem.Name]
                }
                else {
                    $t.Text = $elem.DefaultValue
                }
                 
                $t.Add_TextChanged({ & $UpdatePreviewAction })
                $dynamicStack.Children.Add($t)
            }
            elseif ($elem.Type -eq "ComboBox") {
                $c = New-Object System.Windows.Controls.ComboBox
                $c.Tag = @{ Key = $elem.Name; IsMeta = $elem.IsMetadata }
                $c.Width = $width
                $c.VerticalAlignment = "Center"
                $c.ItemsSource = $elem.Options
                 
                # HYDRATION
                if ($existingMeta.ContainsKey($elem.Name)) {
                    $found = $null
                    foreach ($opt in $elem.Options) { if ($opt -eq $existingMeta[$elem.Name]) { $found = $opt } }
                    if ($found) { $c.SelectedItem = $found }
                    else { $c.Text = $existingMeta[$elem.Name] } # Editable?
                }
                 
                $c.Add_SelectionChanged({ & $UpdatePreviewAction })
                $dynamicStack.Children.Add($c)
            }
        }
        
        $Ctrl.DynamicFormPanel.Children.Add($dynamicStack)
        
        # Initial Preview
        & $UpdatePreviewAction

    }.GetNewClosure() # End Global Function

}
