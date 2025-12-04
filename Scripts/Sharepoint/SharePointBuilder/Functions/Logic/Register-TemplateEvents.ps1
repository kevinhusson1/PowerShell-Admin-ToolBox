# Scripts/SharePoint/SharePointBuilder/Functions/Logic/Register-TemplateEvents.ps1

function Register-TemplateEvents {
    param(
        [hashtable]$Ctrl,
        [scriptblock]$PreviewLogic,
        [System.Windows.Window]$Window,
        [hashtable]$Context
    )

    # 1. CHARGEMENT DES DONNÉES (Au démarrage)
    try {
        # A. Templates Architecture
        $templates = @(Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query "SELECT * FROM sp_templates ORDER BY DisplayName")
        $Ctrl.CbTemplates.ItemsSource = $templates
        $Ctrl.CbTemplates.DisplayMemberPath = "DisplayName"

        # B. Règles de Nommage (Modèles de dossier)
        # On charge TOUJOURS, peu importe si la case est cochée ou non
        $rules = @(Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query "SELECT * FROM sp_naming_rules")
        if ($Ctrl.CbFolderTemplates) {
            $Ctrl.CbFolderTemplates.ItemsSource = $rules
            $Ctrl.CbFolderTemplates.DisplayMemberPath = "RuleId"
            
            # Sélection par défaut (la première règle)
            if ($rules.Count -gt 0) { $Ctrl.CbFolderTemplates.SelectedIndex = 0 }
        }

        # C. Autopilot
        if ($Context.AutoTemplateId) {
            $target = $templates | Where-Object { $_.TemplateId -eq $Context.AutoTemplateId } | Select-Object -First 1
            if ($target) {
                $Ctrl.CbTemplates.SelectedItem = $target
                $Ctrl.CbTemplates.IsEnabled = $false
                Write-AppLog -Message "Autopilot : Modèle '$($target.DisplayName)' sélectionné." -Level Info -RichTextBox $Ctrl.LogBox
            }
        }
    }
    catch {
        Write-AppLog -Message "Erreur chargement données : $_" -Level Error -RichTextBox $Ctrl.LogBox
    }

    # 2. ÉVÉNEMENT : SÉLECTION MODÈLE ARCHITECTURE
    $Ctrl.CbTemplates.Add_SelectionChanged({
            $tpl = $this.SelectedItem
            if (-not $tpl) { return }
        
            $Ctrl.TxtDesc.Text = $tpl.Description
            # Mise à jour arbre visuel
            if ($null -ne $PreviewLogic) { & $PreviewLogic }
        }.GetNewClosure())

    # 3. ÉVÉNEMENT : SÉLECTION RÈGLE DE NOMMAGE
    # Génère le formulaire quand on change la sélection dans la ComboBox "Modèle de dossier"
    # OU quand elle est initialisée
    if ($Ctrl.CbFolderTemplates) {
        $Ctrl.CbFolderTemplates.Add_SelectionChanged({
                $rule = $this.SelectedItem
                if (-not $rule) { return }
            
                $Ctrl.PanelForm.Children.Clear()

                try {
                    $layout = ($rule.DefinitionJson | ConvertFrom-Json).Layout
                    foreach ($elem in $layout) {
                    
                        # Valeurs par défaut
                        $defaultValue = $elem.DefaultValue
                        if ($elem.Name -and $Context.AutoFormData -and $Context.AutoFormData.ContainsKey($elem.Name)) {
                            $defaultValue = $Context.AutoFormData[$elem.Name]
                        }

                        if ($elem.Type -eq "Label") {
                            $l = New-Object System.Windows.Controls.TextBlock -Property @{ Text = $elem.Content; Tag = "Static"; VerticalAlignment = "Center"; Margin = "0,0,5,0"; FontWeight = "Bold" }
                            $Ctrl.PanelForm.Children.Add($l)
                        }
                        elseif ($elem.Type -eq "TextBox") {
                            $t = New-Object System.Windows.Controls.TextBox -Property @{ Text = $defaultValue; Width = $elem.Width; Style = $Window.FindResource("StandardTextBoxStyle"); Margin = "0,0,5,0" }
                            $t.Add_TextChanged($PreviewLogic) 
                            $Ctrl.PanelForm.Children.Add($t)
                        }
                        elseif ($elem.Type -eq "ComboBox") {
                            $c = New-Object System.Windows.Controls.ComboBox -Property @{ ItemsSource = $elem.Options; Width = $elem.Width; Style = $Window.FindResource("StandardComboBoxStyle"); Margin = "0,0,5,0" }
                        
                            if ($defaultValue -and $elem.Options -contains $defaultValue) { $c.SelectedItem = $defaultValue }
                            else { $c.SelectedIndex = 0 }
                        
                            $c.Add_SelectionChanged($PreviewLogic)
                            $Ctrl.PanelForm.Children.Add($c)
                        }
                    }
                    & $PreviewLogic
                }
                catch { Write-AppLog -Message "Erreur formulaire : $_" -Level Error -RichTextBox $Ctrl.LogBox }

            }.GetNewClosure())
    }

    # 4. ÉVÉNEMENT : TOGGLE CHECKBOX "Créer Dossier" (NOUVEAU)
    # C'est ici qu'on déclenche la re-validation pour activer le bouton si on décoche
    $Ctrl.ChkCreateFolder.Add_Click({
            # Déclenchement immédiat de la validation
            if ($null -ne $PreviewLogic) { & $PreviewLogic }
        
            # Astuce : Si on active la création et que le formulaire est vide, on le recharge
            if ($this.IsChecked -and $Ctrl.PanelForm.Children.Count -eq 0 -and $Ctrl.CbFolderTemplates.SelectedItem) {
                $currentRule = $Ctrl.CbFolderTemplates.SelectedItem
                $Ctrl.CbFolderTemplates.SelectedItem = $null
                $Ctrl.CbFolderTemplates.SelectedItem = $currentRule
            }
        }.GetNewClosure())
}