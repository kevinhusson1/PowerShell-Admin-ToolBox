# Scripts/SharePoint/SharePointBuilder/Functions/Logic/Register-TemplateEvents.ps1

function Register-TemplateEvents {
    param(
        [hashtable]$Ctrl,
        [scriptblock]$PreviewLogic,
        [System.Windows.Window]$Window,
        [hashtable]$Context
    )

    # 1. Chargement des données
    try {
        $templates = @(Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query "SELECT * FROM sp_templates ORDER BY DisplayName")
        $Ctrl.CbTemplates.ItemsSource = $templates
        $Ctrl.CbTemplates.DisplayMemberPath = "DisplayName"
    } catch {
        Write-AppLog -Message "Erreur templates : $_" -Level Error -RichTextBox $Ctrl.LogBox
    }

    # 2. Définition de l'événement (AVANT de sélectionner quoi que ce soit)
    $Ctrl.CbTemplates.Add_SelectionChanged({
        $tpl = $this.SelectedItem
        if (-not $tpl) { return }
        
        $safeDesc = $Window.FindName("TemplateDescText")
        $safePanel = $Window.FindName("DynamicFormPanel")
        
        if ($safeDesc) { $safeDesc.Text = $tpl.Description }
        if ($safePanel) { $safePanel.Children.Clear() }

        if ($tpl.NamingRuleId) {
            $rule = Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query "SELECT DefinitionJson FROM sp_naming_rules WHERE RuleId = '$($tpl.NamingRuleId)'"
            if ($rule) {
                try {
                    $layout = ($rule.DefinitionJson | ConvertFrom-Json).Layout
                    foreach ($elem in $layout) {
                        
                        # --- CORRECTION AUTOPILOT : Vérification Name ---
                        $defaultValue = $elem.DefaultValue
                        # On vérifie que 'Name' existe AVANT de chercher dans la Hashtable
                        if ($elem.Name -and $Context.AutoFormData -and $Context.AutoFormData.ContainsKey($elem.Name)) {
                            $defaultValue = $Context.AutoFormData[$elem.Name]
                        }

                        if ($elem.Type -eq "Label") {
                            $l = New-Object System.Windows.Controls.TextBlock -Property @{ Text = $elem.Content; Tag = "Static"; VerticalAlignment="Center"; Margin="0,0,5,0"; FontWeight="Bold" }
                            $safePanel.Children.Add($l)
                        }
                        elseif ($elem.Type -eq "TextBox") {
                            $t = New-Object System.Windows.Controls.TextBox -Property @{ Text = $defaultValue; Width = $elem.Width; Style = $Window.FindResource("StandardTextBoxStyle"); Margin="0,0,5,0" }
                            $t.Add_TextChanged($PreviewLogic) 
                            $safePanel.Children.Add($t)
                        }
                        elseif ($elem.Type -eq "ComboBox") {
                            $c = New-Object System.Windows.Controls.ComboBox -Property @{ ItemsSource = $elem.Options; Width = $elem.Width; Style = $Window.FindResource("StandardComboBoxStyle"); Margin="0,0,5,0" }
                            
                            if ($defaultValue -and $elem.Options -contains $defaultValue) { $c.SelectedItem = $defaultValue }
                            else { $c.SelectedIndex = 0 }
                            
                            $c.Add_SelectionChanged($PreviewLogic)
                            $safePanel.Children.Add($c)
                        }
                    }
                    & $PreviewLogic
                } catch { Write-AppLog -Message "Erreur formulaire : $_" -Level Error -RichTextBox $Ctrl.LogBox }
            }
        }
    }.GetNewClosure())

    # 3. AUTOPILOT : SÉLECTION TEMPLATE
    if ($Context.AutoTemplateId) {
        $target = $templates | Where-Object { $_.TemplateId -eq $Context.AutoTemplateId } | Select-Object -First 1
        if ($target) {
            $Ctrl.CbTemplates.SelectedItem = $target
            $Ctrl.CbTemplates.IsEnabled = $false
            Write-AppLog -Message "Autopilot : Modèle '$($target.DisplayName)' sélectionné." -Level Info -RichTextBox $Ctrl.LogBox
        }
    }
}