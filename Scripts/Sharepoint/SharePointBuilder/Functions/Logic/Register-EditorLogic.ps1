# Scripts/SharePoint/SharePointBuilder/Functions/Logic/Register-EditorLogic.ps1

function Register-EditorLogic {
    param(
        [hashtable]$Ctrl,
        [System.Windows.Window]$Window
    )

    # ==========================================================================
    # 0. HELPER : MISE À JOUR VISUELLE (BADGES)
    # ==========================================================================
    $UpdateBadges = {
        param($TreeItem)
        if (-not $TreeItem) { return }

        $data = $TreeItem.Tag
        # Structure Header : [0]Icon [1]Name [2]BadgePerm [3]BadgeTag [4]BadgeLink
        $header = $TreeItem.Header
        if ($header -isnot [System.Windows.Controls.StackPanel]) { return }

        # Perms
        $bdgPerm = $header.Children[2]
        $cntP = if ($data.Permissions) { $data.Permissions.Count } else { 0 }
        if ($cntP -gt 0) { $bdgPerm.Visibility = "Visible"; $bdgPerm.Child.Text = "👤 $cntP" } else { $bdgPerm.Visibility = "Collapsed" }

        # Tags
        $bdgTag = $header.Children[3]
        $cntT = if ($data.Tags) { $data.Tags.Count } else { 0 }
        if ($cntT -gt 0) { $bdgTag.Visibility = "Visible"; $bdgTag.Child.Text = "🏷️ $cntT" } else { $bdgTag.Visibility = "Collapsed" }

        # Liens (NOUVEAU)
        $bdgLink = $header.Children[4]
        $cntL = if ($data.Links) { $data.Links.Count } else { 0 }
        if ($cntL -gt 0) { $bdgLink.Visibility = "Visible"; $bdgLink.Child.Text = "🔗 $cntL" } else { $bdgLink.Visibility = "Collapsed" }

    }.GetNewClosure()

    # ==========================================================================
    # 1. HELPER : RENDU LIGNES
    # ==========================================================================
    $RenderPermissionRow = {
        param($PermData, $ParentList)
        if ($null -eq $ParentList) { return }
        $row = New-Object System.Windows.Controls.Grid; $row.Margin = "0,0,0,5"; $row.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{Width = "*"; })); $row.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{Width = "120"; })); $row.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{Width = "Auto"; }))
        
        $t1 = New-Object System.Windows.Controls.TextBox -Property @{Text = $PermData.Email; Style = $Window.FindResource("StandardTextBoxStyle"); Margin = "0,0,5,0" }; $t1.Add_TextChanged({ $PermData.Email = $this.Text }.GetNewClosure())
        $c1 = New-Object System.Windows.Controls.ComboBox -Property @{ItemsSource = @("Read", "Contribute", "Full Control"); SelectedItem = $PermData.Level; Style = $Window.FindResource("StandardComboBoxStyle"); Margin = "0,0,5,0"; Height = 34 }; $c1.Add_SelectionChanged({ if ($this.SelectedItem) { $PermData.Level = $this.SelectedItem } }.GetNewClosure())
        $b1 = New-Object System.Windows.Controls.Button -Property @{Content = "🗑️"; Style = $Window.FindResource("IconButtonStyle"); Width = 34; Height = 34; Foreground = $Window.FindResource("DangerBrush") }; $b1.Add_Click({ $sel = $Ctrl.EdTree.SelectedItem; if ($sel) { $sel.Tag.Permissions.Remove($PermData); & $UpdateBadges -TreeItem $sel }; $ParentList.Items.Remove($row) }.GetNewClosure())

        [System.Windows.Controls.Grid]::SetColumn($t1, 0); $row.Children.Add($t1) | Out-Null; [System.Windows.Controls.Grid]::SetColumn($c1, 1); $row.Children.Add($c1) | Out-Null; [System.Windows.Controls.Grid]::SetColumn($b1, 2); $row.Children.Add($b1) | Out-Null
        $ParentList.Items.Add($row) | Out-Null
    }

    $RenderTagRow = {
        param($TagData, $ParentList)
        if ($null -eq $ParentList) { return }
        $row = New-Object System.Windows.Controls.Grid; $row.Margin = "0,0,0,5"; $row.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{Width = "*"; })); $row.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{Width = "*"; })); $row.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{Width = "Auto"; }))
        
        $t1 = New-Object System.Windows.Controls.TextBox -Property @{Text = $TagData.Name; Style = $Window.FindResource("StandardTextBoxStyle"); Margin = "0,0,5,0" }; $t1.Add_TextChanged({ $TagData.Name = $this.Text }.GetNewClosure())
        $t2 = New-Object System.Windows.Controls.TextBox -Property @{Text = $TagData.Value; Style = $Window.FindResource("StandardTextBoxStyle"); Margin = "0,0,5,0" }; $t2.Add_TextChanged({ $TagData.Value = $this.Text }.GetNewClosure())
        $b1 = New-Object System.Windows.Controls.Button -Property @{Content = "🗑️"; Style = $Window.FindResource("IconButtonStyle"); Width = 34; Height = 34; Foreground = $Window.FindResource("DangerBrush") }; $b1.Add_Click({ $sel = $Ctrl.EdTree.SelectedItem; if ($sel) { $sel.Tag.Tags.Remove($TagData); & $UpdateBadges -TreeItem $sel }; $ParentList.Items.Remove($row) }.GetNewClosure())

        [System.Windows.Controls.Grid]::SetColumn($t1, 0); $row.Children.Add($t1) | Out-Null; [System.Windows.Controls.Grid]::SetColumn($t2, 1); $row.Children.Add($t2) | Out-Null; [System.Windows.Controls.Grid]::SetColumn($b1, 2); $row.Children.Add($b1) | Out-Null
        $ParentList.Items.Add($row) | Out-Null
    }

    # --- C. LIGNE LIEN (NOUVEAU) ---
    $RenderLinkRow = {
        param($LinkData, $ParentList)
        if ($null -eq $ParentList) { return }
        
        $row = New-Object System.Windows.Controls.Grid; $row.Margin = "0,0,0,5"
        $row.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(1, "Star") })) # Nom
        $row.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(2, "Star") })) # URL
        $row.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::Auto }))          # Del

        # Nom Lien
        $tName = New-Object System.Windows.Controls.TextBox -Property @{ Text = $LinkData.Name; Margin = "0,0,5,0"; VerticalContentAlignment = "Center" }
        $tName.Style = $Window.FindResource("StandardTextBoxStyle")
        $tName.Add_TextChanged({ $LinkData.Name = $this.Text }.GetNewClosure())

        # URL Lien
        $tUrl = New-Object System.Windows.Controls.TextBox -Property @{ Text = $LinkData.Url; Margin = "0,0,5,0"; VerticalContentAlignment = "Center" }
        $tUrl.Style = $Window.FindResource("StandardTextBoxStyle")
        $tUrl.Add_TextChanged({ $LinkData.Url = $this.Text }.GetNewClosure())

        # Delete
        $btnDel = New-Object System.Windows.Controls.Button -Property @{ Content = "🗑️"; Width = 34; Height = 34; Foreground = $Window.FindResource("DangerBrush") }
        $btnDel.Style = $Window.FindResource("IconButtonStyle")
        $btnDel.Add_Click({
                $sel = $Ctrl.EdTree.SelectedItem
                if ($sel) { 
                    $sel.Tag.Links.Remove($LinkData)
                    & $UpdateBadges -TreeItem $sel
                }
                $ParentList.Items.Remove($row)
            }.GetNewClosure())

        [System.Windows.Controls.Grid]::SetColumn($tName, 0); $row.Children.Add($tName) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($tUrl, 1); $row.Children.Add($tUrl) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($btnDel, 2); $row.Children.Add($btnDel) | Out-Null
        $ParentList.Items.Add($row) | Out-Null
    }

    # ==========================================================================
    # 2. GESTION DE LA SÉLECTION
    # ==========================================================================
    $Ctrl.EdTree.Add_SelectedItemChanged({
            $selectedItem = $Ctrl.EdTree.SelectedItem

            if ($null -eq $selectedItem) {
                $Ctrl.EdNoSelPanel.Visibility = "Visible"; $Ctrl.EdPropPanel.Visibility = "Collapsed"
            }
            else {
                $Ctrl.EdNoSelPanel.Visibility = "Collapsed"; $Ctrl.EdPropPanel.Visibility = "Visible"
                $data = $selectedItem.Tag
                if ($data) { $Ctrl.EdNameBox.Text = $data.Name }

                # A. Perms
                if ($Ctrl.EdPermissionsListBox) { $Ctrl.EdPermissionsListBox.Items.Clear(); if ($data.Permissions) { foreach ($p in $data.Permissions) { & $RenderPermissionRow -PermData $p -ParentList $Ctrl.EdPermissionsListBox } } }
                # B. Tags
                if ($Ctrl.EdTagsListBox) { $Ctrl.EdTagsListBox.Items.Clear(); if ($data.Tags) { foreach ($t in $data.Tags) { & $RenderTagRow -TagData $t -ParentList $Ctrl.EdTagsListBox } } }
                # C. Liens (NOUVEAU)
                if ($Ctrl.EdLinksListBox) { $Ctrl.EdLinksListBox.Items.Clear(); if ($data.Links) { foreach ($l in $data.Links) { & $RenderLinkRow -LinkData $l -ParentList $Ctrl.EdLinksListBox } } }
            }
        }.GetNewClosure())

    # ==========================================================================
    # 3. MODIFICATION NOM
    # ==========================================================================
    $Ctrl.EdNameBox.Add_TextChanged({
            $sel = $Ctrl.EdTree.SelectedItem
            if ($sel -and $sel.Tag) {
                $newName = $Ctrl.EdNameBox.Text
                $sel.Tag.Name = $newName
                if ($sel.Header -is [System.Windows.Controls.StackPanel]) { $sel.Header.Children[1].Text = if ([string]::IsNullOrWhiteSpace($newName)) { "(Sans nom)" } else { $newName } }
            }
        }.GetNewClosure())

    # ==========================================================================
    # 4. ACTIONS ARBRE
    # ==========================================================================
    $Ctrl.EdBtnNew.Add_Click({
            if ([System.Windows.MessageBox]::Show("Tout effacer et créer un nouveau modèle ?", "Confirmation", "YesNo", "Warning") -eq 'Yes') {
            
                # 1. Nettoyage de l'UI
                $Ctrl.EdTree.Items.Clear()
                $Ctrl.EdNameBox.Text = ""
                if ($Ctrl.EdPermissionsListBox) { $Ctrl.EdPermissionsListBox.Items.Clear() }
                if ($Ctrl.EdTagsListBox) { $Ctrl.EdTagsListBox.Items.Clear() }
                if ($Ctrl.EdLinksListBox) { $Ctrl.EdLinksListBox.Items.Clear() }
            
                # Masquer le panneau de droite
                $Ctrl.EdNoSelPanel.Visibility = "Visible"
                $Ctrl.EdPropPanel.Visibility = "Collapsed"

                # 2. CORRECTION CRITIQUE : Réinitialisation de l'état (Mémoire)
                $Ctrl.EdLoadCb.Tag = $null        # On oublie l'ID du modèle précédent
                $Ctrl.EdLoadCb.SelectedIndex = -1 # On désélectionne visuellement dans la liste

            }
        }.GetNewClosure())

    $Ctrl.EdBtnRoot.Add_Click({ $newItem = New-EditorNode -Name "Racine"; $Ctrl.EdTree.Items.Add($newItem) | Out-Null; $newItem.IsSelected = $true }.GetNewClosure())

    $Ctrl.EdBtnChild.Add_Click({
            $p = $Ctrl.EdTree.SelectedItem
            if ($null -eq $p) { [System.Windows.MessageBox]::Show("Sélectionnez un dossier.", "Info", "OK", "Information"); return }
            $n = New-EditorNode -Name "Nouveau dossier"; $p.Items.Add($n) | Out-Null; $p.IsExpanded = $true; $n.IsSelected = $true
        }.GetNewClosure())

    $Ctrl.EdBtnDel.Add_Click({
            $i = $Ctrl.EdTree.SelectedItem; if ($null -eq $i) { return }
            if ([System.Windows.MessageBox]::Show("Supprimer '$($i.Tag.Name)' ?", "Confirmation", "YesNo", "Question") -eq 'No') { return }
            $FnDel = { param($C, $I) if ($C.Contains($I)) { $C.Remove($I); return $true } foreach ($s in $C) { if (& $FnDel -C $s.Items -I $I) { return $true } } return $false }
            & $FnDel -C $Ctrl.EdTree.Items -I $i
        }.GetNewClosure())

    # ==========================================================================
    # 5. ACTIONS PROPRIÉTÉS
    # ==========================================================================
    
    # A. Perm
    if ($Ctrl.EdBtnAddPerm) {
        $Ctrl.EdBtnAddPerm.Add_Click({
                $sel = $Ctrl.EdTree.SelectedItem; if (-not $sel) { return }
                $obj = [PSCustomObject]@{ Email = "user@domaine.com"; Level = "Read" }
                if ($null -eq $sel.Tag.Permissions) { $sel.Tag.Permissions = [System.Collections.Generic.List[psobject]]::new() }
                elseif ($sel.Tag.Permissions -is [System.Array]) { $sel.Tag.Permissions = [System.Collections.Generic.List[psobject]]::new($sel.Tag.Permissions) }
                $sel.Tag.Permissions.Add($obj)
                if ($Ctrl.EdPermissionsListBox) { & $RenderPermissionRow -PermData $obj -ParentList $Ctrl.EdPermissionsListBox }
                & $UpdateBadges -TreeItem $sel
            }.GetNewClosure())
    }

    # B. Tag
    if ($Ctrl.EdBtnAddTag) {
        $Ctrl.EdBtnAddTag.Add_Click({
                $sel = $Ctrl.EdTree.SelectedItem; if (-not $sel) { return }
                $obj = [PSCustomObject]@{ Name = "NomColonne"; Value = "Valeur" }
                if ($null -eq $sel.Tag.Tags) { $sel.Tag.Tags = [System.Collections.Generic.List[psobject]]::new() }
                elseif ($sel.Tag.Tags -is [System.Array]) { $sel.Tag.Tags = [System.Collections.Generic.List[psobject]]::new($sel.Tag.Tags) }
                $sel.Tag.Tags.Add($obj)
                if ($Ctrl.EdTagsListBox) { & $RenderTagRow -TagData $obj -ParentList $Ctrl.EdTagsListBox }
                & $UpdateBadges -TreeItem $sel
            }.GetNewClosure())
    }

    # C. Link (NOUVEAU)
    if ($Ctrl.EdBtnAddLink) {
        $Ctrl.EdBtnAddLink.Add_Click({
                $sel = $Ctrl.EdTree.SelectedItem; if (-not $sel) { return }
                $obj = [PSCustomObject]@{ Name = "Google"; Url = "https://google.com" }
            
                if ($null -eq $sel.Tag.Links) { $sel.Tag.Links = [System.Collections.Generic.List[psobject]]::new() }
                elseif ($sel.Tag.Links -is [System.Array]) { $sel.Tag.Links = [System.Collections.Generic.List[psobject]]::new($sel.Tag.Links) }
            
                $sel.Tag.Links.Add($obj)
                if ($Ctrl.EdLinksListBox) { & $RenderLinkRow -LinkData $obj -ParentList $Ctrl.EdLinksListBox }
                & $UpdateBadges -TreeItem $sel
            }.GetNewClosure())
    }

    # ==========================================================================
    # 6. PERSISTANCE (LOAD / SAVE / NEW / DELETE) - MISE A JOUR
    # ==========================================================================

    $ResetUI = {
        $Ctrl.EdTree.Items.Clear()
        $Ctrl.EdNameBox.Text = ""
        if ($Ctrl.EdPermissionsListBox) { $Ctrl.EdPermissionsListBox.Items.Clear() }
        if ($Ctrl.EdTagsListBox) { $Ctrl.EdTagsListBox.Items.Clear() }
        if ($Ctrl.EdLinksListBox) { $Ctrl.EdLinksListBox.Items.Clear() }
        $Ctrl.EdNoSelPanel.Visibility = "Visible"; $Ctrl.EdPropPanel.Visibility = "Collapsed"
        $Ctrl.EdLoadCb.Tag = $null; $Ctrl.EdLoadCb.SelectedIndex = -1
    }.GetNewClosure()

    $LoadTemplateList = {
        try {
            $tpls = @(Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query "SELECT * FROM sp_templates ORDER BY DisplayName")
            $Ctrl.EdLoadCb.ItemsSource = $tpls
            $Ctrl.EdLoadCb.DisplayMemberPath = "DisplayName"
        }
        catch { }
    }.GetNewClosure()
    & $LoadTemplateList

    $Ctrl.EdBtnNew.Add_Click({
            if ([System.Windows.MessageBox]::Show("Tout effacer et créer un nouveau modèle ?", "Confirmation", "YesNo", "Warning") -eq 'Yes') { & $ResetUI }
        }.GetNewClosure())

    $Ctrl.EdBtnLoad.Add_Click({
            $selectedTpl = $Ctrl.EdLoadCb.SelectedItem
            if (-not $selectedTpl) { return }
            if ($Ctrl.EdTree.Items.Count -gt 0) { if ([System.Windows.MessageBox]::Show("Charger va écraser le modèle actuel. Continuer ?", "Attention", "YesNo", "Warning") -ne 'Yes') { return } }
            Convert-JsonToEditorTree -Json $selectedTpl.StructureJson -TreeView $Ctrl.EdTree
            $Ctrl.EdNoSelPanel.Visibility = "Visible"; $Ctrl.EdPropPanel.Visibility = "Collapsed"
            $Ctrl.EdLoadCb.Tag = $selectedTpl.TemplateId
        }.GetNewClosure())

    # --- D. BOUTON SAUVEGARDER AVEC CHOIX "ENREGISTRER SOUS" ---
    $Ctrl.EdBtnSave.Add_Click({
            if ($Ctrl.EdTree.Items.Count -eq 0) { [System.Windows.MessageBox]::Show("L'arbre est vide.", "Erreur", "OK", "Warning"); return }

            $json = Convert-EditorTreeToJson -TreeView $Ctrl.EdTree
            $cleanJson = $json.Replace("'", "''")

            $currentId = $Ctrl.EdLoadCb.Tag
            $currentName = if ($Ctrl.EdLoadCb.SelectedItem) { $Ctrl.EdLoadCb.SelectedItem.DisplayName } else { "" }

            # 1. Logique de choix si existant
            if ($currentId) {
                $msg = "Le modèle '$currentName' est actuellement chargé.`n`nVoulez-vous écraser les modifications ?`n`nOUI : Écraser l'existant`nNON : Créer une copie (Enregistrer sous)`nANNULER : Ne rien faire"
                $choice = [System.Windows.MessageBox]::Show($msg, "Sauvegarde", [System.Windows.MessageBoxButton]::YesNoCancel, [System.Windows.MessageBoxImage]::Question)

                switch ($choice) {
                    'Cancel' { return }
                    'No' {
                        # Mode "Enregistrer Sous"
                        $currentId = $null
                        Add-Type -AssemblyName Microsoft.VisualBasic
                        $newName = [Microsoft.VisualBasic.Interaction]::InputBox("Nom du nouveau modèle :", "Enregistrer une copie", "$currentName - Copie")
                        if ([string]::IsNullOrWhiteSpace($newName)) { return }
                        $currentName = $newName
                    }
                    'Yes' { 
                        # On garde ID et Nom pour écraser
                    }
                }
            }

            # 2. Logique Nouveau (ou devenu nouveau suite au choix "Non")
            if (-not $currentId) {
                # Si le nom est vide (cas d'un vrai nouveau, pas d'une copie nommée), on demande
                if ([string]::IsNullOrWhiteSpace($currentName)) {
                    Add-Type -AssemblyName Microsoft.VisualBasic
                    $currentName = [Microsoft.VisualBasic.Interaction]::InputBox("Nom du nouveau modèle :", "Sauvegarder", "Mon Nouveau Modèle")
                }
                if ([string]::IsNullOrWhiteSpace($currentName)) { return }
                $currentId = [Guid]::NewGuid().ToString()
            }

            try {
                $query = "INSERT OR REPLACE INTO sp_templates (TemplateId, DisplayName, Description, Category, StructureJson, DateModified) 
                      VALUES ('$currentId', '$currentName', 'Modèle personnalisé', 'Custom', '$cleanJson', '$(Get-Date -Format 'o')');"
            
                Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $query
                [System.Windows.MessageBox]::Show("Modèle '$currentName' sauvegardé !", "Succès", "OK", "Information")
            
                & $LoadTemplateList
            
                # Resélectionner le bon
                $newItem = $Ctrl.EdLoadCb.ItemsSource | Where-Object { $_.TemplateId -eq $currentId } | Select-Object -First 1
                if ($newItem) { 
                    $Ctrl.EdLoadCb.SelectedItem = $newItem 
                    $Ctrl.EdLoadCb.Tag = $currentId
                }

            }
            catch { [System.Windows.MessageBox]::Show("Erreur sauvegarde : $($_.Exception.Message)", "Erreur", "OK", "Error") }

        }.GetNewClosure())

    if ($Ctrl.EdBtnDeleteTpl) {
        $Ctrl.EdBtnDeleteTpl.Add_Click({
                $currentId = $Ctrl.EdLoadCb.Tag
                if (-not $currentId -and $Ctrl.EdLoadCb.SelectedItem) { $currentId = $Ctrl.EdLoadCb.SelectedItem.TemplateId }
                if (-not $currentId) { [System.Windows.MessageBox]::Show("Aucun modèle sélectionné.", "Info", "OK", "Information"); return }
            
                $nom = if ($Ctrl.EdLoadCb.SelectedItem) { $Ctrl.EdLoadCb.SelectedItem.DisplayName } else { "ce modèle" }
                if ([System.Windows.MessageBox]::Show("Supprimer définitivement '$nom' ?", "Suppression", "YesNo", "Error") -eq 'Yes') {
                    try {
                        Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query "DELETE FROM sp_templates WHERE TemplateId = '$currentId'"
                        [System.Windows.MessageBox]::Show("Modèle supprimé.", "Succès", "OK", "Information")
                        & $LoadTemplateList; & $ResetUI
                    }
                    catch { [System.Windows.MessageBox]::Show("Erreur : $($_.Exception.Message)", "Erreur", "OK", "Error") }
                }
            }.GetNewClosure())
    }
}