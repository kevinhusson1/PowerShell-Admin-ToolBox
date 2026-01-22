<#
.SYNOPSIS
    Gère la génération dynamique du formulaire en fonction de la configuration sélectionnée.

.DESCRIPTION
    Écoute l'événement SelectionChanged de la liste des configs.
    Charge la Règle de nommage associée (JSON) et génère les champs de saisie (TextBox, ComboBox) dynamiquement.
    Gère la prévisualisation (Preview) en temps réel du futur nom de dossier via l'écouteur $UpdatePreviewAction.
    Utilise une fonction Helper Récursive Globale pour parcourir l'arbre visuel généré.

.PARAMETER Ctrl
    Hashtable contenant les contrôles UI.

.PARAMETER Window
    Fenêtre parente.
#>
function Register-FormEvents {
    param(
        [hashtable]$Ctrl,
        [System.Windows.Window]$Window
    )

    # Helper Log local
    $Log = { 
        param($msg, $level = "Info") 
        if ($Ctrl.LogBox) { Write-AppLog -Message $msg -Level $level -RichTextBox $Ctrl.LogBox }
    }.GetNewClosure()

    # Helpers Loc
    $Loc = { param($k) if (Get-Command Get-AppLocalizedString -ErrorAction SilentlyContinue) { Get-AppLocalizedString -Key $k } else { $k } }.GetNewClosure()

    if ($Ctrl.ListBox) {
        $Ctrl.ListBox.Add_SelectionChanged({
                $cfg = $this.SelectedItem
                if (-not $cfg) { return }
                
                # Toggle UI
                if ($Ctrl.PlaceholderPanel) { $Ctrl.PlaceholderPanel.Visibility = "Collapsed" }
                if ($Ctrl.DetailGrid) { $Ctrl.DetailGrid.Visibility = "Visible" }

                # Update Header
                $Ctrl.Title.Text = $cfg.ConfigName
                $Ctrl.Site.Text = $cfg.SiteUrl
                $Ctrl.Lib.Text = $cfg.LibraryName
            
                # Nom du Template
                $tplName = $cfg.TemplateId
                try { 
                    $t = Get-AppSPTemplates | Where-Object { $_.TemplateId -eq $cfg.TemplateId } | Select-Object -First 1
                    if ($t) { $tplName = $t.DisplayName }
                }
                catch {}
                $Ctrl.Template.Text = $tplName

                # Warning Overwrite
                if ($Ctrl.Warning) {
                    $Ctrl.Warning.Visibility = if ($cfg.OverwritePermissions -eq 1) { "Visible" } else { "Collapsed" }
                }

                # GÉNÉRATION FORMULAIRE
                if ($Ctrl.DynamicFormPanel) { $Ctrl.DynamicFormPanel.Children.Clear() }
                $Ctrl.BtnDeploy.IsEnabled = $false 

                if ($cfg.TargetFolder) {
                    # Charger la règle
                    try {
                        $rules = Get-AppNamingRules
                        $targetRule = $rules | Where-Object { $_.RuleId -eq $cfg.TargetFolder } | Select-Object -First 1

                        if ($targetRule) {
                            $layout = ($targetRule.DefinitionJson | ConvertFrom-Json).Layout
                            
                            # --- LOGIQUE PREVIEW ---
                            $UpdatePreviewAction = {
                                param($s, $e)
                                try {
                                    $root = $null
                                    # 1. Try Sender
                                    if ($s -is [System.Windows.Controls.StackPanel] -and $s.Name -eq "DynamicFormPanel") { $root = $s }
                                    # 2. Try Capture
                                    if (-not $root -and $Ctrl.DynamicFormPanel) { $root = $Ctrl.DynamicFormPanel }
                                    # 3. Try Refetch
                                    if (-not $root -and $Window) { $root = $Window.FindName("DynamicFormPanel") }
                                    
                                    # Utilisation de la fonction Globale (Safe Scope)
                                    if (-not (Get-Command "Find-ControlRecursive" -ErrorAction SilentlyContinue)) { return }

                                    # 1. Sous-dossier optionnel
                                    $optVal = ""
                                    $optCtrl = Find-ControlRecursive -parent $root -tagName "OptionalSubFolder"
                                    if ($optCtrl) { $optVal = $optCtrl.Text }

                                    # 2. Nom Dynamique
                                    $dynName = ""
                                    $dynStack = Find-ControlRecursive -parent $root -tagName "FormDynamicStack"

                                    if ($dynStack) {
                                        foreach ($child in $dynStack.Children) {
                                            $part = ""
                                            if ($child -is [System.Windows.Controls.TextBox]) { $part = $child.Text }
                                            elseif ($child -is [System.Windows.Controls.TextBlock]) { $part = $child.Text }
                                            elseif ($child -is [System.Windows.Controls.ComboBox]) { $part = $child.SelectedItem }
                                            $dynName += $part
                                        }
                                    }
                                    
                                    # 3. Assemblage
                                    $finalText = $dynName
                                    if (-not [string]::IsNullOrWhiteSpace($optVal)) {
                                        if ([string]::IsNullOrWhiteSpace($finalText)) { $finalText = $optVal }
                                        else { $finalText = "$optVal/$finalText" }
                                    }
                                    
                                    # 4. UPDATE UI
                                    $previewRef = $Ctrl.FolderNamePreview 
                                    if (-not $previewRef) {
                                        $previewRef = Find-ControlRecursive -parent $root -tagName "PreviewText"
                                    }
                                    
                                    if ($previewRef) {
                                        $previewRef.Text = if ($finalText) { $finalText } else { " " } 
                                    }
                                }
                                catch {
                                    Write-Host "Preview Error: $_"
                                }
                            }.GetNewClosure()

                            # --- GÉNÉRATION UI ---
                            
                            # 1. OPTIONAL FOLDER
                            $optPanel = New-Object System.Windows.Controls.StackPanel
                            $optPanel.Margin = [System.Windows.Thickness]::new(0, 0, 0, 20)
                            
                            $optLabel = New-Object System.Windows.Controls.TextBlock
                            $optLabel.Text = & $Loc "sp_deploy.opt_folder"
                            $optLabel.FontWeight = "SemiBold"
                            $optLabel.Margin = [System.Windows.Thickness]::new(0, 0, 0, 5)
                            $optPanel.Children.Add($optLabel)
                            
                            $optTxt = New-Object System.Windows.Controls.TextBox
                            $optTxt.Tag = "OptionalSubFolder"
                            $optTxt.Width = 300
                            $optTxt.HorizontalAlignment = "Left"
                            $optTxt.Style = $Window.FindResource("StandardTextBoxStyle")
                            $optTxt.Add_TextChanged($UpdatePreviewAction)
                            $optPanel.Children.Add($optTxt)
                            
                            $Ctrl.DynamicFormPanel.Children.Add($optPanel)

                            # 2. DYNAMIC FORM
                            $scroll = New-Object System.Windows.Controls.ScrollViewer
                            $scroll.HorizontalScrollBarVisibility = "Auto"
                            $scroll.VerticalScrollBarVisibility = "Disabled"
                            $scroll.Margin = [System.Windows.Thickness]::new(0, 0, 0, 20)
                            
                            $dynamicStack = New-Object System.Windows.Controls.StackPanel
                            $dynamicStack.Orientation = "Horizontal"
                            $dynamicStack.Tag = "FormDynamicStack"
                            $scroll.Content = $dynamicStack

                            function Get-SanitizedName { param($n) return $n -replace '[^a-zA-Z0-9_]', '' }

                            foreach ($elem in $layout) {
                                $width = 200
                                if ($elem.Width -and $elem.Width -match '^\d+$') { $width = [double]$elem.Width }
                            
                                if ($elem.Type -eq "Label") {
                                    $t = New-Object System.Windows.Controls.TextBlock
                                    $t.Text = $elem.Content
                                    $t.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#00AEEF")
                                    $t.FontWeight = "Bold"
                                    $t.VerticalAlignment = "Center"
                                    $t.Margin = [System.Windows.Thickness]::new(5, 0, 5, 0)
                                    $dynamicStack.Children.Add($t)
                                }
                                elseif ($elem.Type -eq "TextBox") {
                                    $t = New-Object System.Windows.Controls.TextBox
                                    $t.Tag = $elem.Name
                                    $t.Text = $elem.DefaultValue
                                    $t.Width = $width 
                                    $t.VerticalAlignment = "Center"
                                    $t.Style = $Window.FindResource("StandardTextBoxStyle")
                                    if ($elem.IsUppercase) { $t.CharacterCasing = [System.Windows.Controls.CharacterCasing]::Upper }
                                    
                                    $t.Add_TextChanged($UpdatePreviewAction) 
                                    $dynamicStack.Children.Add($t)
                                }
                                elseif ($elem.Type -eq "ComboBox") {
                                    $c = New-Object System.Windows.Controls.ComboBox
                                    $c.Tag = $elem.Name
                                    $c.Width = $width
                                    $c.VerticalAlignment = "Center"
                                    $c.ItemsSource = $elem.Options
                                    $c.Style = $Window.FindResource("StandardComboBoxStyle")
                                    if ($elem.DefaultValue -and $elem.Options -contains $elem.DefaultValue) { $c.SelectedItem = $elem.DefaultValue }
                                    else { $c.SelectedIndex = 0 }
                                    
                                    $c.Add_SelectionChanged($UpdatePreviewAction)
                                    $dynamicStack.Children.Add($c)
                                }
                            }
                            
                            $Ctrl.DynamicFormPanel.Children.Add($scroll)
                            
                            # 3. PREVIEW
                            $previewPanel = New-Object System.Windows.Controls.StackPanel
                            $previewPanel.Orientation = "Horizontal"
                            $previewPanel.Margin = [System.Windows.Thickness]::new(0, 10, 0, 0)
                            
                            $pLabel = New-Object System.Windows.Controls.TextBlock
                            $pLabel.Text = & $Loc "sp_deploy.preview_label"
                            $pLabel.FontWeight = "SemiBold"
                            $pLabel.VerticalAlignment = "Center"
                            $pLabel.Margin = [System.Windows.Thickness]::new(0, 0, 10, 0)
                            $previewPanel.Children.Add($pLabel)
                            
                            $pBorder = New-Object System.Windows.Controls.Border
                            $pBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#F3F3F3")
                            $pBorder.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E0E0E0")
                            $pBorder.BorderThickness = [System.Windows.Thickness]::new(1)
                            $pBorder.CornerRadius = [System.Windows.CornerRadius]::new(4)
                            $pBorder.Padding = [System.Windows.Thickness]::new(10, 5, 10, 5)
                            $pBorder.HorizontalAlignment = "Stretch"
                            
                            $pVal = New-Object System.Windows.Controls.TextBlock
                            $pVal.Tag = "PreviewText" 
                            $pVal.Text = "..."
                            $pVal.FontWeight = "SemiBold"
                            $pVal.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#00AEEF")
                            
                            $pBorder.Child = $pVal
                            $previewPanel.Children.Add($pBorder)
                            
                            # Important: Update Ctrl Reference
                            $Ctrl.FolderNamePreview = $pVal 
                            
                            $Ctrl.DynamicFormPanel.Children.Add($previewPanel)
                        
                            # Init Preview
                            $UpdatePreviewAction.Invoke($Ctrl.DynamicFormPanel, $null)

                            $Ctrl.BtnDeploy.IsEnabled = $true
                        }
                        else {
                            $err = New-Object System.Windows.Controls.TextBlock
                            $err.Text = "Règle de nommage '$($cfg.TargetFolder)' introuvable."
                            $err.Foreground = [System.Windows.Media.Brushes]::Red
                            if ($Ctrl.DynamicFormPanel) { $Ctrl.DynamicFormPanel.Children.Add($err) }
                        }
                    }
                    catch {
                        & $Log "Erreur génération formulaire : $($_.Exception.Message)" "Error"
                    }
                }
                else {
                    # Pas de dossier cible dynamique (Racine)
                    $info = New-Object System.Windows.Controls.TextBlock
                    $info.Text = "Aucun dossier dynamique configuré. Déploiement à la racine de la bibliothèque."
                    if ($Ctrl.DynamicFormPanel) { $Ctrl.DynamicFormPanel.Children.Add($info) }
                    if ($Ctrl.BtnDeploy) { $Ctrl.BtnDeploy.IsEnabled = $true }
                }

            }.GetNewClosure())
    }
}
