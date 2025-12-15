# Scripts/SharePoint/SharePointBuilder/Functions/Logic/Register-EditorLogic.ps1

function Register-EditorLogic {
    param(
        [hashtable]$Ctrl,
        [System.Windows.Window]$Window
    )

    # ==========================================================================
    # 1. HELPER : RENDU LIGNES (Avec Capture du TreeItem pour éviter la perte de focus)
    # ==========================================================================
    
    # --- A. PERMISSIONS ---
    $RenderPermissionRow = {
        # AJOUT DU PARAMETRE $CurrentTreeItem
        param($PermData, $ParentList, $CurrentTreeItem)
        if ($null -eq $ParentList) { return }
        
        $row = New-Object System.Windows.Controls.Grid; $row.Margin = "0,0,0,5"
        $row.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{Width = "*" }))
        $row.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{Width = "120" }))
        $row.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{Width = "Auto" }))
        
        $t1 = New-Object System.Windows.Controls.TextBox -Property @{Text = $PermData.Email; Style = $Window.FindResource("StandardTextBoxStyle"); Margin = "0,0,5,0" }; $t1.Add_TextChanged({ $PermData.Email = $this.Text }.GetNewClosure())
        $c1 = New-Object System.Windows.Controls.ComboBox -Property @{ItemsSource = @("Read", "Contribute", "Full Control"); SelectedItem = $PermData.Level; Style = $Window.FindResource("StandardComboBoxStyle"); Margin = "0,0,5,0"; Height = 34 }; $c1.Add_SelectionChanged({ if ($this.SelectedItem) { $PermData.Level = $this.SelectedItem } }.GetNewClosure())
        
        # SUPPRESSION
        $b1 = New-Object System.Windows.Controls.Button -Property @{Content = "🗑️"; Style = $Window.FindResource("IconButtonStyle"); Width = 34; Height = 34; Foreground = $Window.FindResource("DangerBrush") }
        $b1.Add_Click({ 
                # ICI : On utilise la variable CAPTURÉE ($CurrentTreeItem) et non le SelectedItem dynamique
                $sel = $CurrentTreeItem
            
                if ($sel -and $sel.Tag.Permissions) {
                    if ($sel.Tag.Permissions -is [System.Array]) {
                        $sel.Tag.Permissions = [System.Collections.Generic.List[psobject]]::new($sel.Tag.Permissions)
                    }
                    $sel.Tag.Permissions.Remove($PermData)
                    Update-EditorBadges -TreeItem $sel
                }
                $ParentList.Items.Remove($row) 
            }.GetNewClosure())

        [System.Windows.Controls.Grid]::SetColumn($t1, 0); $row.Children.Add($t1) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($c1, 1); $row.Children.Add($c1) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($b1, 2); $row.Children.Add($b1) | Out-Null
        $ParentList.Items.Add($row) | Out-Null
    }

    # --- B. TAGS ---
    $RenderTagRow = {
        param($TagData, $ParentList, $CurrentTreeItem)
        if ($null -eq $ParentList) { return }
        
        $row = New-Object System.Windows.Controls.Grid; $row.Margin = "0,0,0,5"
        $row.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{Width = "*" }))
        $row.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{Width = "*" }))
        $row.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{Width = "Auto" }))
        
        $t1 = New-Object System.Windows.Controls.TextBox -Property @{Text = $TagData.Name; Style = $Window.FindResource("StandardTextBoxStyle"); Margin = "0,0,5,0" }; $t1.Add_TextChanged({ $TagData.Name = $this.Text }.GetNewClosure())
        $t2 = New-Object System.Windows.Controls.TextBox -Property @{Text = $TagData.Value; Style = $Window.FindResource("StandardTextBoxStyle"); Margin = "0,0,5,0" }; $t2.Add_TextChanged({ $TagData.Value = $this.Text }.GetNewClosure())
        
        # SUPPRESSION
        $b1 = New-Object System.Windows.Controls.Button -Property @{Content = "🗑️"; Style = $Window.FindResource("IconButtonStyle"); Width = 34; Height = 34; Foreground = $Window.FindResource("DangerBrush") }
        $b1.Add_Click({ 
                $sel = $CurrentTreeItem # Capture
            
                if ($sel -and $sel.Tag.Tags) {
                    if ($sel.Tag.Tags -is [System.Array]) {
                        $sel.Tag.Tags = [System.Collections.Generic.List[psobject]]::new($sel.Tag.Tags)
                    }
                    $sel.Tag.Tags.Remove($TagData)
                    Update-EditorBadges -TreeItem $sel
                }
                $ParentList.Items.Remove($row) 
            }.GetNewClosure())

        [System.Windows.Controls.Grid]::SetColumn($t1, 0); $row.Children.Add($t1) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($t2, 1); $row.Children.Add($t2) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($b1, 2); $row.Children.Add($b1) | Out-Null
        $ParentList.Items.Add($row) | Out-Null
    }

    # --- C. LIENS ---
    $RenderLinkRow = {
        param($LinkData, $ParentList, $CurrentTreeItem)
        if ($null -eq $ParentList) { return }
        
        $row = New-Object System.Windows.Controls.Grid; $row.Margin = "0,0,0,5"
        $row.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{Width = "1*" }))
        $row.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{Width = "2*" }))
        $row.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{Width = "Auto" }))

        $tName = New-Object System.Windows.Controls.TextBox -Property @{Text = $LinkData.Name; Style = $Window.FindResource("StandardTextBoxStyle"); Margin = "0,0,5,0" }; $tName.Add_TextChanged({ $LinkData.Name = $this.Text }.GetNewClosure())
        $tUrl = New-Object System.Windows.Controls.TextBox -Property @{Text = $LinkData.Url; Style = $Window.FindResource("StandardTextBoxStyle"); Margin = "0,0,5,0" }; $tUrl.Add_TextChanged({ $LinkData.Url = $this.Text }.GetNewClosure())

        # SUPPRESSION
        $b1 = New-Object System.Windows.Controls.Button -Property @{Content = "🗑️"; Style = $Window.FindResource("IconButtonStyle"); Width = 34; Height = 34; Foreground = $Window.FindResource("DangerBrush") }
        $b1.Add_Click({
                $sel = $CurrentTreeItem # Capture
            
                if ($sel -and $sel.Tag.Links) { 
                    if ($sel.Tag.Links -is [System.Array]) {
                        $sel.Tag.Links = [System.Collections.Generic.List[psobject]]::new($sel.Tag.Links)
                    }
                    $sel.Tag.Links.Remove($LinkData)
                    Update-EditorBadges -TreeItem $sel
                }
                $ParentList.Items.Remove($row)
            }.GetNewClosure())

        [System.Windows.Controls.Grid]::SetColumn($tName, 0); $row.Children.Add($tName) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($tUrl, 1); $row.Children.Add($tUrl) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($b1, 2); $row.Children.Add($b1) | Out-Null
        $ParentList.Items.Add($row) | Out-Null
    }

    # ==========================================================================
    # 2. GESTION SÉLECTION & MODIFICATION
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

                # ON PASSE $selectedItem A CHAQUE APPEL DE RENDU
                if ($Ctrl.EdPermissionsListBox) { 
                    $Ctrl.EdPermissionsListBox.Items.Clear()
                    if ($data.Permissions) { foreach ($p in $data.Permissions) { & $RenderPermissionRow -PermData $p -ParentList $Ctrl.EdPermissionsListBox -CurrentTreeItem $selectedItem } } 
                }
                if ($Ctrl.EdTagsListBox) { 
                    $Ctrl.EdTagsListBox.Items.Clear()
                    if ($data.Tags) { foreach ($t in $data.Tags) { & $RenderTagRow -TagData $t -ParentList $Ctrl.EdTagsListBox -CurrentTreeItem $selectedItem } } 
                }
                if ($Ctrl.EdLinksListBox) { 
                    $Ctrl.EdLinksListBox.Items.Clear()
                    if ($data.Links) { foreach ($l in $data.Links) { & $RenderLinkRow -LinkData $l -ParentList $Ctrl.EdLinksListBox -CurrentTreeItem $selectedItem } } 
                }
            }
        }.GetNewClosure())

    $Ctrl.EdNameBox.Add_TextChanged({
            $sel = $Ctrl.EdTree.SelectedItem
            if ($sel -and $sel.Tag) {
                $newName = $Ctrl.EdNameBox.Text
                $sel.Tag.Name = $newName
                if ($sel.Header -is [System.Windows.Controls.StackPanel]) { $sel.Header.Children[1].Text = if ([string]::IsNullOrWhiteSpace($newName)) { "(Sans nom)" } else { $newName } }
            }
        }.GetNewClosure())

    # ==========================================================================
    # 3. ACTIONS ARBRE
    # ==========================================================================
    $Ctrl.EdBtnNew.Add_Click({
            if ([System.Windows.MessageBox]::Show("Tout effacer ?", "Confirmation", "YesNo", "Warning") -eq 'Yes') {
                $Ctrl.EdTree.Items.Clear(); $Ctrl.EdNameBox.Text = ""; if ($Ctrl.EdPermissionsListBox) { $Ctrl.EdPermissionsListBox.Items.Clear() }; if ($Ctrl.EdTagsListBox) { $Ctrl.EdTagsListBox.Items.Clear() }; if ($Ctrl.EdLinksListBox) { $Ctrl.EdLinksListBox.Items.Clear() }
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
    # 4. ACTIONS PROPRIÉTÉS (AJOUT)
    # ==========================================================================
    
    if ($Ctrl.EdBtnAddPerm) {
        $Ctrl.EdBtnAddPerm.Add_Click({
                $sel = $Ctrl.EdTree.SelectedItem; if (-not $sel) { return }
                $obj = [PSCustomObject]@{ Email = "user@domaine.com"; Level = "Read" }
                if ($null -eq $sel.Tag.Permissions) { $sel.Tag.Permissions = [System.Collections.Generic.List[psobject]]::new() }
                elseif ($sel.Tag.Permissions -is [System.Array]) { $sel.Tag.Permissions = [System.Collections.Generic.List[psobject]]::new($sel.Tag.Permissions) }
                $sel.Tag.Permissions.Add($obj)
            
                # PASSAGE DE $sel ICI
                if ($Ctrl.EdPermissionsListBox) { & $RenderPermissionRow -PermData $obj -ParentList $Ctrl.EdPermissionsListBox -CurrentTreeItem $sel }
            
                Update-EditorBadges -TreeItem $sel
            }.GetNewClosure())
    }

    if ($Ctrl.EdBtnAddTag) {
        $Ctrl.EdBtnAddTag.Add_Click({
                $sel = $Ctrl.EdTree.SelectedItem; if (-not $sel) { return }
                $obj = [PSCustomObject]@{ Name = "NomColonne"; Value = "Valeur" }
                if ($null -eq $sel.Tag.Tags) { $sel.Tag.Tags = [System.Collections.Generic.List[psobject]]::new() }
                elseif ($sel.Tag.Tags -is [System.Array]) { $sel.Tag.Tags = [System.Collections.Generic.List[psobject]]::new($sel.Tag.Tags) }
                $sel.Tag.Tags.Add($obj)
            
                # PASSAGE DE $sel ICI
                if ($Ctrl.EdTagsListBox) { & $RenderTagRow -TagData $obj -ParentList $Ctrl.EdTagsListBox -CurrentTreeItem $sel }
            
                Update-EditorBadges -TreeItem $sel
            }.GetNewClosure())
    }

    if ($Ctrl.EdBtnAddLink) {
        $Ctrl.EdBtnAddLink.Add_Click({
                $sel = $Ctrl.EdTree.SelectedItem; if (-not $sel) { return }
                $obj = [PSCustomObject]@{ Name = "Google"; Url = "https://google.com" }
                if ($null -eq $sel.Tag.Links) { $sel.Tag.Links = [System.Collections.Generic.List[psobject]]::new() }
                elseif ($sel.Tag.Links -is [System.Array]) { $sel.Tag.Links = [System.Collections.Generic.List[psobject]]::new($sel.Tag.Links) }
                $sel.Tag.Links.Add($obj)
            
                # PASSAGE DE $sel ICI
                if ($Ctrl.EdLinksListBox) { & $RenderLinkRow -LinkData $obj -ParentList $Ctrl.EdLinksListBox -CurrentTreeItem $sel }
            
                Update-EditorBadges -TreeItem $sel
            }.GetNewClosure())
    }

    # ==========================================================================
    # 5. PERSISTANCE (LOAD / SAVE / NEW / DELETE)
    # ==========================================================================
    # (Copiez ici le bloc persistance existant s'il n'est pas déjà présent dans votre version locale)
    # Je ne le répète pas pour éviter la surcharge, mais il doit être présent à la fin du fichier.
    
    # ... BLOC PERSISTANCE ...
    
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

    $Ctrl.EdBtnSave.Add_Click({
            if ($Ctrl.EdTree.Items.Count -eq 0) { [System.Windows.MessageBox]::Show("L'arbre est vide.", "Erreur", "OK", "Warning"); return }

            $json = Convert-EditorTreeToJson -TreeView $Ctrl.EdTree
            $cleanJson = $json.Replace("'", "''")
            $currentId = $Ctrl.EdLoadCb.Tag
            $currentName = if ($Ctrl.EdLoadCb.SelectedItem) { $Ctrl.EdLoadCb.SelectedItem.DisplayName } else { "" }

            if ($currentId) {
                $msg = "Le modèle '$currentName' est actuellement chargé.`n`nVoulez-vous écraser les modifications ?`n`nOUI : Écraser l'existant`nNON : Créer une copie (Enregistrer sous)`nANNULER : Ne rien faire"
                $choice = [System.Windows.MessageBox]::Show($msg, "Sauvegarde", [System.Windows.MessageBoxButton]::YesNoCancel, [System.Windows.MessageBoxImage]::Question)
                switch ($choice) {
                    'Cancel' { return }
                    'No' {
                        $currentId = $null
                        Add-Type -AssemblyName Microsoft.VisualBasic
                        $newName = [Microsoft.VisualBasic.Interaction]::InputBox("Nom du nouveau modèle :", "Enregistrer une copie", "$currentName - Copie")
                        if ([string]::IsNullOrWhiteSpace($newName)) { return }
                        $currentName = $newName
                    }
                }
            }

            if (-not $currentId) {
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
                $newItem = $Ctrl.EdLoadCb.ItemsSource | Where-Object { $_.TemplateId -eq $currentId } | Select-Object -First 1
                if ($newItem) { $Ctrl.EdLoadCb.SelectedItem = $newItem; $Ctrl.EdLoadCb.Tag = $currentId }
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