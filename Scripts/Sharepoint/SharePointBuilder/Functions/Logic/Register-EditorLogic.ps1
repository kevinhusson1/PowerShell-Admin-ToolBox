# Scripts/SharePoint/SharePointBuilder/Functions/Logic/Register-EditorLogic.ps1

function Register-EditorLogic {
    param(
        [hashtable]$Ctrl,
        [System.Windows.Window]$Window
    )

    # ==========================================================================
    # 1. HELPER : RENDU D'UNE LIGNE DE PERMISSION
    # ==========================================================================
    # Cette fonction génère l'UI d'une ligne et gère le binding manuel vers l'objet donnée
    $RenderPermissionRow = {
        param($PermData, $ParentList)

        $rowGrid = New-Object System.Windows.Controls.Grid
        $rowGrid.Margin = "0,0,0,5"
        $rowGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(1, "Star") })) # Email
        $rowGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(120) }))        # Role
        $rowGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::Auto }))           # Del

        # --- A. TextBox Email ---
        $txtEmail = New-Object System.Windows.Controls.TextBox
        $txtEmail.Text = $PermData.Email
        $txtEmail.Style = $Window.FindResource("StandardTextBoxStyle")
        $txtEmail.Margin = "0,0,5,0"
        $txtEmail.VerticalContentAlignment = "Center"
        # Binding Manuel : Quand on tape, on met à jour l'objet
        $txtEmail.Add_TextChanged({ $PermData.Email = $this.Text }.GetNewClosure())
        
        # --- B. ComboBox Rôle ---
        $cbRole = New-Object System.Windows.Controls.ComboBox
        $cbRole.ItemsSource = @("Read", "Contribute", "Full Control") # Rôles standards
        $cbRole.SelectedItem = $PermData.Level
        $cbRole.Style = $Window.FindResource("StandardComboBoxStyle")
        $cbRole.Margin = "0,0,5,0"
        $cbRole.Height = 34 # Ajustement visuel
        # Binding Manuel
        $cbRole.Add_SelectionChanged({ 
                if ($this.SelectedItem) { $PermData.Level = $this.SelectedItem } 
            }.GetNewClosure())

        # --- C. Bouton Supprimer ---
        $btnDel = New-Object System.Windows.Controls.Button
        $btnDel.Content = "🗑️"
        $btnDel.Style = $Window.FindResource("IconButtonStyle")
        $btnDel.Width = 34; $btnDel.Height = 34
        $btnDel.Foreground = $Window.FindResource("DangerBrush")
        
        # Action Suppression
        $btnDel.Add_Click({
                # 1. Retirer de l'objet de données du dossier parent
                $selectedFolder = $Ctrl.EdTree.SelectedItem
                if ($selectedFolder) {
                    $selectedFolder.Tag.Permissions.Remove($PermData)
                }
                # 2. Retirer visuellement de la liste
                $Ctrl.EdPermissionsListBox.Items.Remove($rowGrid)
            }.GetNewClosure())

        # --- Assemblage ---
        [System.Windows.Controls.Grid]::SetColumn($txtEmail, 0); $rowGrid.Children.Add($txtEmail)
        [System.Windows.Controls.Grid]::SetColumn($cbRole, 1); $rowGrid.Children.Add($cbRole)
        [System.Windows.Controls.Grid]::SetColumn($btnDel, 2); $rowGrid.Children.Add($btnDel)

        $Ctrl.EdPermissionsListBox.Items.Add($rowGrid) | Out-Null
    }

    # ==========================================================================
    # 2. GESTION DE LA SÉLECTION (Chargement des données)
    # ==========================================================================
    $Ctrl.EdTree.Add_SelectedItemChanged({
            $selectedItem = $Ctrl.EdTree.SelectedItem

            if ($null -eq $selectedItem) {
                $Ctrl.EdNoSelPanel.Visibility = "Visible"
                $Ctrl.EdPropPanel.Visibility = "Collapsed"
            }
            else {
                $Ctrl.EdNoSelPanel.Visibility = "Collapsed"
                $Ctrl.EdPropPanel.Visibility = "Visible"

                $data = $selectedItem.Tag
            
                # A. Nom du dossier
                if ($data) { $Ctrl.EdNameBox.Text = $data.Name }

                # B. Permissions (Rechargement complet de la liste)
                $Ctrl.EdPermissionsListBox.Items.Clear()
                if ($data.Permissions) {
                    foreach ($perm in $data.Permissions) {
                        & $RenderPermissionRow -PermData $perm -ParentList $Ctrl.EdPermissionsListBox
                    }
                }
            }
        }.GetNewClosure())

    # ==========================================================================
    # 3. MODIFICATION DU NOM (Live Update)
    # ==========================================================================
    $Ctrl.EdNameBox.Add_TextChanged({
            $selectedItem = $Ctrl.EdTree.SelectedItem
            if ($selectedItem -and $selectedItem.Tag) {
                $newName = $Ctrl.EdNameBox.Text
                $selectedItem.Tag.Name = $newName
            
                if ($selectedItem.Header -is [System.Windows.Controls.StackPanel]) {
                    $textBlock = $selectedItem.Header.Children[1]
                    $textBlock.Text = if ([string]::IsNullOrWhiteSpace($newName)) { "(Sans nom)" } else { $newName }
                }
            }
        }.GetNewClosure())

    # ==========================================================================
    # 4. ACTIONS BOUTONS ARBRE (Ajout / Suppression)
    # ==========================================================================
    $Ctrl.EdBtnNew.Add_Click({
            if ([System.Windows.MessageBox]::Show("Tout effacer ?", "Confirmation", "YesNo", "Warning") -eq 'Yes') {
                $Ctrl.EdTree.Items.Clear()
                $Ctrl.EdNameBox.Text = ""
                $Ctrl.EdPermissionsListBox.Items.Clear()
            }
        }.GetNewClosure())

    $Ctrl.EdBtnRoot.Add_Click({
            $newItem = New-EditorNode -Name "Racine"
            $Ctrl.EdTree.Items.Add($newItem) | Out-Null
            $newItem.IsSelected = $true
        }.GetNewClosure())

    $Ctrl.EdBtnChild.Add_Click({
            $parent = $Ctrl.EdTree.SelectedItem
            if ($null -eq $parent) {
                [System.Windows.MessageBox]::Show("Veuillez sélectionner un dossier parent.", "Info", "OK", "Information")
                return
            }
            $newItem = New-EditorNode -Name "Nouveau dossier"
            $parent.Items.Add($newItem) | Out-Null
            $parent.IsExpanded = $true
            $newItem.IsSelected = $true
        }.GetNewClosure())

    $Ctrl.EdBtnDel.Add_Click({
            $item = $Ctrl.EdTree.SelectedItem
            if ($null -eq $item) { return }
            if ([System.Windows.MessageBox]::Show("Supprimer '$($item.Tag.Name)' ?", "Confirmation", "YesNo", "Question") -eq 'No') { return }

            $RemoveItemLogic = {
                param($Collection, $ItemToRemove)
                if ($Collection.Contains($ItemToRemove)) {
                    $Collection.Remove($ItemToRemove)
                    return $true
                }
                foreach ($sub in $Collection) {
                    if (& $RemoveItemLogic -Collection $sub.Items -ItemToRemove $ItemToRemove) { return $true }
                }
                return $false
            }
            & $RemoveItemLogic -Collection $Ctrl.EdTree.Items -ItemToRemove $item
        }.GetNewClosure())

    # ==========================================================================
    # 5. ACTIONS PROPRIÉTÉS (Ajout Permission)
    # ==========================================================================
    
    # Il faut s'assurer que Get-BuilderControls récupère bien 'EditorAddPermButton' sous le nom 'EdBtnAddPerm'
    if ($Ctrl.EdBtnAddPerm) {
        $Ctrl.EdBtnAddPerm.Add_Click({
                $selectedFolder = $Ctrl.EdTree.SelectedItem
                if (-not $selectedFolder) { return }

                # 1. Création de l'objet de données
                $newPerm = [PSCustomObject]@{
                    Email = "utilisateur@domaine.com"
                    Level = "Read"
                }

                # 2. Ajout à la liste de données du dossier
                # (On s'assure que la liste existe)
                if ($null -eq $selectedFolder.Tag.Permissions) {
                    $selectedFolder.Tag.Permissions = [System.Collections.Generic.List[psobject]]::new()
                }
                $selectedFolder.Tag.Permissions.Add($newPerm)

                # 3. Rendu Visuel
                & $RenderPermissionRow -PermData $newPerm -ParentList $Ctrl.EdPermissionsListBox

            }.GetNewClosure())
    }
}