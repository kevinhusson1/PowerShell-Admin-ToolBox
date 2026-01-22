# Scripts/SharePoint/SharePointBuilder/Functions/Logic/Register-TemplateEvents.ps1

<#
.SYNOPSIS
    Gère le chargement et la sélection des Templates (Modèle d'Architecture et Règle de Nommage).

.DESCRIPTION
    - Charge la liste des templates JSON depuis la base de données.
    - Charge la liste des règles de nommage depuis la base de données.
    - Gère la génération dynamique du formulaire (champs de saisie) lorsqu'une règle est sélectionnée.
    - Gère l'activation/désactivation de l'option "Créer un dossier racine".

.PARAMETER Ctrl
    La Hashtable des contrôles UI.

.PARAMETER PreviewLogic
    ScriptBlock de validation pour mettre à jour l'état du formulaire.

.PARAMETER Window
    La fenêtre WPF principale.

.PARAMETER Context
    Hashtable contextuel (Autopilot, etc.).
#>
function Register-TemplateEvents {
    param(
        [hashtable]$Ctrl,
        [scriptblock]$PreviewLogic,
        [System.Windows.Window]$Window,
        [hashtable]$Context
    )

    # Capture Locale Robuste
    $GetLoc = Get-Command Get-AppLocalizedString -ErrorAction SilentlyContinue

    # 1. CHARGEMENT DES DONNÉES (Au démarrage)
    try {
        # A. Templates Architecture
        $templates = @(Get-AppSPTemplates)
        $Ctrl.CbTemplates.ItemsSource = $templates
        $Ctrl.CbTemplates.DisplayMemberPath = "DisplayName"

        # B. Règles de Nommage (Modèles de dossier)
        # On charge TOUJOURS, peu importe si la case est cochée ou non
        $rules = @(Get-AppNamingRules)
        if ($Ctrl.CbFolderTemplates) {
            $Ctrl.CbFolderTemplates.ItemsSource = $rules
            $Ctrl.CbFolderTemplates.DisplayMemberPath = "RuleId"
            
            # Sélection par défaut (la première règle)
            # if ($rules.Count -gt 0) { $Ctrl.CbFolderTemplates.SelectedIndex = 0 }
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

    # 2. AUTO-REFRESH : Mise à jour de la liste à l'ouverture (DropDownOpened)
    $Ctrl.CbTemplates.Add_DropDownOpened({
            try {
                $current = $this.SelectedItem
                $freshTemplates = @(Get-AppSPTemplates)
                
                # Mise à jour de la source
                $this.ItemsSource = $freshTemplates
                $this.DisplayMemberPath = "DisplayName"

                # Restauration de la sélection
                if ($current) {
                    $match = $freshTemplates | Where-Object { $_.TemplateId -eq $current.TemplateId } | Select-Object -First 1
                    if ($match) { $this.SelectedItem = $match }
                }
            }
            catch {
                Write-AppLog -Message "Erreur Refresh Templates : $_" -Level Error -RichTextBox $Ctrl.LogBox
            }
        }.GetNewClosure())

    # 3. ÉVÉNEMENT : SÉLECTION MODÈLE ARCHITECTURE
    $Ctrl.CbTemplates.Add_SelectionChanged({
            $tpl = $this.SelectedItem
            if (-not $tpl) { return }
        
            $Ctrl.TxtDesc.Text = $tpl.Description
            
            # LOG USER
            if ($GetLoc) {
                $fmt = & $GetLoc "sp_builder.log_template_selected"
                $msg = $fmt -f $tpl.DisplayName
                Write-AppLog -Message $msg -Level Info -RichTextBox $Ctrl.LogBox
            }

            # Mise à jour arbre visuel
            if ($null -ne $PreviewLogic) { & $PreviewLogic }
        }.GetNewClosure())

    # 3. ÉVÉNEMENT : SÉLECTION RÈGLE DE NOMMAGE
    # Génère le formulaire quand on change la sélection dans la ComboBox "Modèle de dossier"
    # OU quand elle est initialisée
    if ($Ctrl.CbFolderTemplates) {
        # AUTO-REFRESH : Mise à jour des règles à l'ouverture
        $Ctrl.CbFolderTemplates.Add_DropDownOpened({
                try {
                    $current = $this.SelectedItem
                    $freshRules = @(Get-AppNamingRules)
                
                    $this.ItemsSource = $freshRules
                    $this.DisplayMemberPath = "RuleId"

                    if ($current) {
                        $match = $freshRules | Where-Object { $_.RuleId -eq $current.RuleId } | Select-Object -First 1
                        if ($match) { $this.SelectedItem = $match }
                    }
                }
                catch { Write-AppLog -Message "Erreur Refresh Rules : $_" -Level Error -RichTextBox $Ctrl.LogBox }
            }.GetNewClosure())

        $Ctrl.CbFolderTemplates.Add_SelectionChanged({
                $rule = $this.SelectedItem
                if (-not $rule) { return }
            
                $Ctrl.PanelForm.Children.Clear()

                # LOG USER
                if ($GetLoc) {
                    $fmt = & $GetLoc "sp_builder.log_rule_selected"
                    $msg = $fmt -f $rule.RuleId
                    Write-AppLog -Message $msg -Level Info -RichTextBox $Ctrl.LogBox
                }

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
                            if ($elem.IsUppercase) { $t.CharacterCasing = [System.Windows.Controls.CharacterCasing]::Upper }
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