<#
.SYNOPSIS
    Gère la génération dynamique du formulaire et son hydratation.

.DESCRIPTION
    Ce script est responsable de :
    1. Lire la règle de nommage associée à la configuration sélectionnée via son ID.
    2. Générer dynamiquement les contrôles UI (TextBox, ComboBox, Label) basés sur le JSON de la règle.
    3. Hydrater ces contrôles avec les métadonnées existantes du dossier cible (si disponibles).
    4. Gérer la logique de "Prévisualisation" en temps réel (mise à jour du nom calculé lors de la saisie).
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
        
        # --- LOGIQUE PREVIEW (Style Robust) ---
        # --- LOGIQUE PREVIEW (Style Robust) ---
        $UpdatePreviewAction = {
            param($s, $e)
            try {
                Write-Host "DEBUG: UpdatePreviewAction Triggered"
                $root = $Ctrl.DynamicFormPanel
                if (-not $root -and $Window) { $root = $Window.FindName("DynamicFormPanel") }
                
                if (-not (Get-Command "Find-ControlRecursive" -ErrorAction SilentlyContinue)) { 
                    Write-Host "DEBUG: Find-ControlRecursive CMD NOT FOUND"
                    return 
                }

                $dynStack = Find-ControlRecursive -parent $root -tagName "FormDynamicStack"
                if (-not $dynStack) { 
                    Write-Host "DEBUG: FormDynamicStack NOT FOUND in Root: $root"
                    return 
                }

                # 1. Scan Values
                $values = @{}
                foreach ($child in $dynStack.Children) {
                    $key = $null
                    if ($child.Tag -is [System.Collections.IDictionary]) { $key = $child.Tag.Key }
                    elseif ($child.Tag -is [string]) { $key = $child.Tag }
                    
                    if ($key) {
                        $val = ""
                        if ($child -is [System.Windows.Controls.TextBox]) { $val = $child.Text }
                        elseif ($child -is [System.Windows.Controls.ComboBox]) { $val = "$($child.SelectedItem)" }
                        elseif ($child -is [System.Windows.Controls.TextBlock]) { $val = $child.Text }
                        $values[$key] = $val
                    }
                }
                # Write-Host "DEBUG: Values Captured: $($values | Out-String)"

                # 2. Reconstruct from Layout
                $dynName = ""
                foreach ($elem in $layout) {
                    if ($elem.Type -eq "Label") { $dynName += $elem.Content }
                    elseif ($values.ContainsKey($elem.Name)) { $dynName += $values[$elem.Name] }
                }
                
                Write-Host "DEBUG: NewName Calculated: '$dynName'"

                # Update UI
                $previewBox = $Ctrl.FolderNamePreview
                if (-not $previewBox -and $Window) {
                     # Fallback Retrieval
                     $previewBox = $Window.FindName("FolderNamePreviewText")
                }

                if ($previewBox) { 
                    $previewBox.Dispatcher.Invoke([Action] {
                            $previewBox.Text = if ($dynName) { $dynName } else { "..." }
                        })
                }
                else {
                    Write-Host "DEBUG: Control FolderNamePreview NOT FOUND (Even with Fallback)"
                    # Try to log children of DetailGrid to understand why
                    if ($Ctrl.DetailGrid) {
                        Write-Host "DEBUG: DetailGrid Children Count: $([System.Windows.LogicalTreeHelper]::GetChildren($Ctrl.DetailGrid).Count)"
                    }
                }
            }
            catch {
                Write-Host "Preview Error: $($_.Exception.Message)"
            }
        }.GetNewClosure()

        # --- GÉNÉRATION UI ---
        
        # ScrollViewer Container
        $scroll = New-Object System.Windows.Controls.ScrollViewer
        $scroll.HorizontalScrollBarVisibility = "Auto"
        $scroll.VerticalScrollBarVisibility = "Disabled"
        $scroll.Margin = [System.Windows.Thickness]::new(0, 0, 0, 20)
        
        $dynamicStack = New-Object System.Windows.Controls.StackPanel
        $dynamicStack.Orientation = "Horizontal"
        $dynamicStack.Tag = "FormDynamicStack" # Tag Essentiel pour le repérage
        $scroll.Content = $dynamicStack

        foreach ($elem in $layout) {
            # Width
            $width = 200
            if ($elem.Width -and $elem.Width -match '^\d+$') { $width = [double]$elem.Width }

            if ($elem.Type -eq "Label") {
                $t = New-Object System.Windows.Controls.TextBlock
                $t.Text = $elem.Content
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
                
                # Style Standard (si dispo)
                try { $t.Style = $Window.FindResource("StandardTextBoxStyle") } catch {}
                 
                # HYDRATION
                if ($existingMeta.ContainsKey($elem.Name)) {
                    $t.Text = $existingMeta[$elem.Name]
                }
                else {
                    $t.Text = $elem.DefaultValue
                }
                 
                $t.Add_TextChanged($UpdatePreviewAction)
                $dynamicStack.Children.Add($t)
            }
            elseif ($elem.Type -eq "ComboBox") {
                $c = New-Object System.Windows.Controls.ComboBox
                $c.Tag = @{ Key = $elem.Name; IsMeta = $elem.IsMetadata }
                $c.Width = $width
                $c.VerticalAlignment = "Center"
                $c.ItemsSource = $elem.Options
                
                # Style Standard
                try { $c.Style = $Window.FindResource("StandardComboBoxStyle") } catch {}

                # HYDRATION
                if ($existingMeta.ContainsKey($elem.Name)) {
                    $found = $null
                    foreach ($opt in $elem.Options) { if ($opt -eq $existingMeta[$elem.Name]) { $found = $opt } }
                    if ($found) { $c.SelectedItem = $found }
                    else { $c.Text = $existingMeta[$elem.Name] }
                }
                 
                $c.Add_SelectionChanged($UpdatePreviewAction)
                $dynamicStack.Children.Add($c)
            }
        }
        
        $Ctrl.DynamicFormPanel.Children.Add($scroll)
        
        # Initial Preview
        $UpdatePreviewAction.Invoke($Ctrl.DynamicFormPanel, $null)

    }.GetNewClosure() # End Global Function

}
