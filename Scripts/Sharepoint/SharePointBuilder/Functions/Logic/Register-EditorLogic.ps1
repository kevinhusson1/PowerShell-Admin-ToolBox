# Scripts/SharePoint/SharePointBuilder/Functions/Logic/Register-EditorLogic.ps1

<#
.SYNOPSIS
    Gère toute la logique de l'éditeur graphique de modèles (onglet "Éditeur de Modèles").

.DESCRIPTION
    Contrôle l'interaction avec le TreeView d'édition :
    - Création, suppression, modification de dossiers.
    - Gestion des panneaux de propriétés contextuels (Dossier vs Métadonnée).
    - Ajout/Suppression de Permissions, Tags et Liens.
    - Chargement et Sauvegarde des templates JSON depuis/vers la base de données SQLite.
    - Mise à jour visuelle des badges.

.PARAMETER Ctrl
    La Hashtable des contrôles UI.

.PARAMETER Window
    La fenêtre WPF principale.
#>
function Register-EditorLogic {
    param(
        [hashtable]$Ctrl,
        [System.Windows.Window]$Window
    )

    # ==========================================================================
    # 0. HELPER : STATUS
    # ==========================================================================
    $SetStatus = {
        param([string]$Msg, [string]$Type = "Normal")
        if ($Ctrl.EdStatusText) {
            $Ctrl.EdStatusText.Text = $Msg
            $brushKey = switch ($Type) {
                "Success" { "SuccessBrush" }
                "Error" { "DangerBrush" }
                "Warning" { "WarningBrush" }
                Default { "TextSecondaryBrush" }
            }
            # Fallback simple si la ressource n'existe pas, sinon on prend la ressource du thème
            try { $Ctrl.EdStatusText.Foreground = $Window.FindResource($brushKey) } catch { }
        }
    }.GetNewClosure()

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



    # ==========================================================================
    # 2. GESTION SÉLECTION & MODIFICATION
    # ==========================================================================
    
    $Script:IsPopulating = $false

    if ($Ctrl.EdTree) {
        $Ctrl.EdTree.Add_SelectedItemChanged({
                $selectedItem = $Ctrl.EdTree.SelectedItem
                $Script:IsPopulating = $true
                
                if ($null -eq $selectedItem) {
                    # HIDE ALL + SHOW NO SEL
                    if ($Ctrl.EdPropPanel) { $Ctrl.EdPropPanel.Visibility = "Collapsed" }
                    if ($Ctrl.EdPropPanelPerm) { $Ctrl.EdPropPanelPerm.Visibility = "Collapsed" }
                    if ($Ctrl.EdPropPanelTag) { $Ctrl.EdPropPanelTag.Visibility = "Collapsed" }
                    if ($Ctrl.EdPropPanelLink) { $Ctrl.EdPropPanelLink.Visibility = "Collapsed" }
                    if ($Ctrl.EdNoSelPanel) { $Ctrl.EdNoSelPanel.Visibility = "Visible" }
                }
                elseif ($selectedItem.Name -eq "MetaItem") {
                    # C'EST UN ATTRIBUT (Permission ou Tag)
                    
                    # 1. Hide Main Panels first
                    if ($Ctrl.EdNoSelPanel) { $Ctrl.EdNoSelPanel.Visibility = "Collapsed" }
                    if ($Ctrl.EdPropPanel) { $Ctrl.EdPropPanel.Visibility = "Collapsed" }
                    # Others we hide unless needed
                    if ($Ctrl.EdPropPanelPerm) { $Ctrl.EdPropPanelPerm.Visibility = "Collapsed" }
                    if ($Ctrl.EdPropPanelTag) { $Ctrl.EdPropPanelTag.Visibility = "Collapsed" }
                    if ($Ctrl.EdPropPanelLink) { $Ctrl.EdPropPanelLink.Visibility = "Collapsed" }

                    $data = $selectedItem.Tag

                    # PERMISSION
                    if ($data.PSObject.Properties['Email'] -or $data.PSObject.Properties['Identity']) {
                        if ($Ctrl.EdPropPanelPerm) { 
                            $Ctrl.EdPropPanelPerm.Visibility = "Visible" 
                            $Ctrl.EdPropPanelPerm.DataContext = $selectedItem 
                            $val = if ($data.PSObject.Properties['Identity']) { $data.Identity } else { $data.Email }
                            if ($Ctrl.EdPermIdentityBox) { $Ctrl.EdPermIdentityBox.Text = $val }
                            if ($Ctrl.EdPermLevelBox) { 
                                $Ctrl.EdPermLevelBox.ItemsSource = @("Read", "Contribute", "Full Control")
                                $Ctrl.EdPermLevelBox.SelectedItem = $data.Level
                            }
                        }
                    }
                    # TAG
                    else {
                        if ($Ctrl.EdPropPanelTag) {
                            $Ctrl.EdPropPanelTag.Visibility = "Visible"
                            $Ctrl.EdPropPanelTag.DataContext = $selectedItem
                            if ($Ctrl.EdTagNameBox) { $Ctrl.EdTagNameBox.Text = if ($data.PSObject.Properties['Name']) { $data.Name } else { $data.Column } }
                            if ($Ctrl.EdTagValueBox) { $Ctrl.EdTagValueBox.Text = if ($data.PSObject.Properties['Value']) { $data.Value } else { $data.Term } }
                        }
                    }
                }
                else {
                    # C'EST UN NOEUD (Dossier ou Lien)
                    $data = $selectedItem.Tag
                    
                    if ($data.Type -eq "Link") {
                        # MODE LIEN
                        if ($Ctrl.EdNoSelPanel) { $Ctrl.EdNoSelPanel.Visibility = "Collapsed" }
                        if ($Ctrl.EdPropPanel) { $Ctrl.EdPropPanel.Visibility = "Collapsed" }
                        if ($Ctrl.EdPropPanelPerm) { $Ctrl.EdPropPanelPerm.Visibility = "Collapsed" }
                        if ($Ctrl.EdPropPanelTag) { $Ctrl.EdPropPanelTag.Visibility = "Collapsed" }

                        if ($Ctrl.EdPropPanelLink) {
                            $Ctrl.EdPropPanelLink.Visibility = "Visible"
                            $Ctrl.EdPropPanelLink.DataContext = $selectedItem
                            if ($Ctrl.EdLinkNameBox) { $Ctrl.EdLinkNameBox.Text = $data.Name }
                            if ($Ctrl.EdLinkUrlBox) { $Ctrl.EdLinkUrlBox.Text = $data.Url }
                        }
                    }
                    else {
                        # MODE DOSSIER
                        # Hide others
                        if ($Ctrl.EdNoSelPanel) { $Ctrl.EdNoSelPanel.Visibility = "Collapsed" }
                        if ($Ctrl.EdPropPanelPerm) { $Ctrl.EdPropPanelPerm.Visibility = "Collapsed" }
                        if ($Ctrl.EdPropPanelTag) { $Ctrl.EdPropPanelTag.Visibility = "Collapsed" }
                        if ($Ctrl.EdPropPanelLink) { $Ctrl.EdPropPanelLink.Visibility = "Collapsed" }
                        
                        # Show Folder Panel
                        if ($Ctrl.EdPropPanel) { $Ctrl.EdPropPanel.Visibility = "Visible" }
                        
                        if ($data -and $Ctrl.EdNameBox) { $Ctrl.EdNameBox.Text = $data.Name }
                        
                        if ($Ctrl.EdPermissionsListBox) { 
                            $Ctrl.EdPermissionsListBox.Items.Clear() 
                            if ($data.Permissions) { 
                                foreach ($p in $data.Permissions) {
                                    & $RenderPermissionRow -PermData $p -ParentList $Ctrl.EdPermissionsListBox -CurrentTreeItem $selectedItem
                                }
                            }
                        }
                        
                        if ($Ctrl.EdTagsListBox) { 
                            $Ctrl.EdTagsListBox.Items.Clear() 
                            if ($data.Tags) { 
                                foreach ($t in $data.Tags) {
                                    & $RenderTagRow -TagData $t -ParentList $Ctrl.EdTagsListBox -CurrentTreeItem $selectedItem
                                }
                            }
                        }
                    }
                }
                
                $Script:IsPopulating = $false
            }.GetNewClosure())
    }
        
    # --- HANDLERS POUR PERMISSIONS ---
    if ($Ctrl.EdPermIdentityBox) {
        $Ctrl.EdPermIdentityBox.Add_TextChanged({
                if ($Script:IsPopulating) { return }
                $sel = $Ctrl.EdTree.SelectedItem
                if ($sel -and $sel.Name -eq "MetaItem") {
                    if (-not $sel.Tag.PSObject.Properties['Identity']) {
                        $sel.Tag | Add-Member -MemberType NoteProperty -Name "Identity" -Value $this.Text -Force
                    }
                    else {
                        $sel.Tag.Identity = $this.Text
                    }
                    $lvl = if ($sel.Tag.PSObject.Properties['Level']) { $sel.Tag.Level } else { "" }
                    $pName = "$($this.Text) ($lvl)"
                    if ($sel.Header -is [System.Windows.Controls.StackPanel]) { $sel.Header.Children[1].Text = $pName }
                }
            }.GetNewClosure())
    }
    if ($Ctrl.EdPermLevelBox) {
        $Ctrl.EdPermLevelBox.Add_SelectionChanged({
                if ($Script:IsPopulating) { return }
                $sel = $Ctrl.EdTree.SelectedItem
                if ($sel -and $sel.Name -eq "MetaItem" -and $this.SelectedItem) {
                    if (-not $sel.Tag.PSObject.Properties['Level']) {
                        $sel.Tag | Add-Member -MemberType NoteProperty -Name "Level" -Value $this.SelectedItem -Force
                    }
                    else {
                        $sel.Tag.Level = $this.SelectedItem
                    }
                    $id = if ($sel.Tag.PSObject.Properties['Identity']) { $sel.Tag.Identity } else { $sel.Tag.Email }
                    $pName = "$id ($($this.SelectedItem))"
                    if ($sel.Header -is [System.Windows.Controls.StackPanel]) { $sel.Header.Children[1].Text = $pName }
                }
            }.GetNewClosure())
    }
    if ($Ctrl.EdPermDeleteButton) {
        $Ctrl.EdPermDeleteButton.Add_Click({
                $sel = $Ctrl.EdTree.SelectedItem
                if ($sel -and $sel.Name -eq "MetaItem") {
                    $parent = $sel.Parent
                    if ($parent -is [System.Windows.Controls.TreeViewItem]) {
                        $parent.Tag.Permissions.Remove($sel.Tag)
                        $parent.Items.Remove($sel)
                        Update-EditorBadges -TreeItem $parent
                    
                        # Reset UI (Inline Hide)
                        if ($Ctrl.EdPropPanel) { $Ctrl.EdPropPanel.Visibility = "Collapsed" }
                        if ($Ctrl.EdPropPanelPerm) { $Ctrl.EdPropPanelPerm.Visibility = "Collapsed" }
                        if ($Ctrl.EdPropPanelTag) { $Ctrl.EdPropPanelTag.Visibility = "Collapsed" }
                        if ($Ctrl.EdPropPanelLink) { $Ctrl.EdPropPanelLink.Visibility = "Collapsed" }
                        if ($Ctrl.EdNoSelPanel) { $Ctrl.EdNoSelPanel.Visibility = "Visible" }
                    }
                }
            }.GetNewClosure())
    }
    
    # --- HANDLERS POUR TAGS ---
    if ($Ctrl.EdTagNameBox) {
        $Ctrl.EdTagNameBox.Add_TextChanged({
                if ($Script:IsPopulating) { return }
                $sel = $Ctrl.EdTree.SelectedItem
                if ($sel -and $sel.Name -eq "MetaItem") {
                    if (-not $sel.Tag.PSObject.Properties['Name']) { $sel.Tag | Add-Member -MemberType NoteProperty -Name "Name" -Value $this.Text -Force }
                    else { $sel.Tag.Name = $this.Text }
                    $val = if ($sel.Tag.PSObject.Properties['Value']) { $sel.Tag.Value } else { "" }
                    $tName = "$($this.Text) : $val"
                    if ($sel.Header -is [System.Windows.Controls.StackPanel]) { $sel.Header.Children[1].Text = $tName }
                }
            }.GetNewClosure())
    }
    if ($Ctrl.EdTagValueBox) {
        $Ctrl.EdTagValueBox.Add_TextChanged({
                if ($Script:IsPopulating) { return }
                $sel = $Ctrl.EdTree.SelectedItem
                if ($sel -and $sel.Name -eq "MetaItem") {
                    if (-not $sel.Tag.PSObject.Properties['Value']) { $sel.Tag | Add-Member -MemberType NoteProperty -Name "Value" -Value $this.Text -Force }
                    else { $sel.Tag.Value = $this.Text }
                    $name = if ($sel.Tag.PSObject.Properties['Name']) { $sel.Tag.Name } else { "" }
                    $tName = "$name : $($this.Text)"
                    if ($sel.Header -is [System.Windows.Controls.StackPanel]) { $sel.Header.Children[1].Text = $tName }
                }
            }.GetNewClosure())
    }
    if ($Ctrl.EdTagDeleteButton) {
        $Ctrl.EdTagDeleteButton.Add_Click({
                $sel = $Ctrl.EdTree.SelectedItem
                if ($sel -and $sel.Name -eq "MetaItem") {
                    $parent = $sel.Parent
                    if ($parent -is [System.Windows.Controls.TreeViewItem]) {
                        $parent.Tag.Tags.Remove($sel.Tag)
                        $parent.Items.Remove($sel)
                        Update-EditorBadges -TreeItem $parent
                    
                        if ($Ctrl.EdPropPanel) { $Ctrl.EdPropPanel.Visibility = "Collapsed" }
                        if ($Ctrl.EdPropPanelPerm) { $Ctrl.EdPropPanelPerm.Visibility = "Collapsed" }
                        if ($Ctrl.EdPropPanelTag) { $Ctrl.EdPropPanelTag.Visibility = "Collapsed" }
                        if ($Ctrl.EdPropPanelLink) { $Ctrl.EdPropPanelLink.Visibility = "Collapsed" }
                        if ($Ctrl.EdNoSelPanel) { $Ctrl.EdNoSelPanel.Visibility = "Visible" }
                    }
                }
            }.GetNewClosure())
    }

    # --- HANDLERS POUR LINKS ---
    if ($Ctrl.EdLinkNameBox) {
        $Ctrl.EdLinkNameBox.Add_TextChanged({
                if ($Script:IsPopulating) { return }
                $sel = $Ctrl.EdTree.SelectedItem
                if ($sel -and $sel.Name -eq "MetaItem") {
                    $sel.Tag.Name = $this.Text
                    $lName = $sel.Tag.Name
                    if ($sel.Header -is [System.Windows.Controls.StackPanel]) { $sel.Header.Children[1].Text = $lName }
                }
            }.GetNewClosure())
    }
    if ($Ctrl.EdLinkUrlBox) {
        $Ctrl.EdLinkUrlBox.Add_TextChanged({
                if ($Script:IsPopulating) { return }
                $sel = $Ctrl.EdTree.SelectedItem
                if ($sel -and $sel.Name -eq "MetaItem") {
                    if (-not $sel.Tag.PSObject.Properties['Url']) { $sel.Tag | Add-Member -MemberType NoteProperty -Name "Url" -Value $this.Text -Force }
                    else { $sel.Tag.Url = $this.Text }
                }
            }.GetNewClosure())
    }
    if ($Ctrl.EdLinkDeleteButton) {
        $Ctrl.EdLinkDeleteButton.Add_Click({
                $sel = $Ctrl.EdTree.SelectedItem
                if ($sel -and $sel.Name -eq "MetaItem") {
                    $parent = $sel.Parent
                    
                    # Cas 1 : Lien dans un dossier
                    if ($parent -is [System.Windows.Controls.TreeViewItem]) {
                        # Remove Data
                        $parent.Tag.Links.Remove($sel.Tag)
                        # Remove UI
                        $parent.Items.Remove($sel)
                        # Update Badges on Parent
                        Update-EditorBadges -TreeItem $parent
                    }
                    # Cas 2 : Lien à la racine
                    elseif ($parent -is [System.Windows.Controls.TreeView]) {
                        $parent.Items.Remove($sel)
                    }

                    # Hide Panel (Commun)
                    if ($Ctrl.EdPropPanel) { $Ctrl.EdPropPanel.Visibility = "Collapsed" }
                    if ($Ctrl.EdPropPanelPerm) { $Ctrl.EdPropPanelPerm.Visibility = "Collapsed" }
                    if ($Ctrl.EdPropPanelTag) { $Ctrl.EdPropPanelTag.Visibility = "Collapsed" }
                    if ($Ctrl.EdPropPanelLink) { $Ctrl.EdPropPanelLink.Visibility = "Collapsed" }
                    if ($Ctrl.EdNoSelPanel) { $Ctrl.EdNoSelPanel.Visibility = "Visible" }
                }
            }.GetNewClosure())
    }

    if ($Ctrl.EdNameBox) {
        $Ctrl.EdNameBox.Add_TextChanged({
                $sel = $Ctrl.EdTree.SelectedItem
                if ($sel -and $sel.Tag -and $sel.Name -ne "MetaItem") {
                    $newName = $Ctrl.EdNameBox.Text
                    $sel.Tag.Name = $newName
                    if ($sel.Header -is [System.Windows.Controls.StackPanel]) { $sel.Header.Children[1].Text = if ([string]::IsNullOrWhiteSpace($newName)) { "(Sans nom)" } else { $newName } }
                }
            }.GetNewClosure())
    }

    # HANDLERS POUR LIENS (Name & URL)
    if ($Ctrl.EdLinkNameBox) {
        $Ctrl.EdLinkNameBox.Add_TextChanged({
                $sel = $Ctrl.EdTree.SelectedItem
                # Vérif si c'est un Noeud Lien (Type="Link")
                if ($sel -and $sel.Tag -and $sel.Tag.Type -eq "Link") {
                    $newName = $Ctrl.EdLinkNameBox.Text
                    $sel.Tag.Name = $newName
                    if ($sel.Header -is [System.Windows.Controls.StackPanel]) { 
                        # Texte est au Children[1]
                        $sel.Header.Children[1].Text = if ([string]::IsNullOrWhiteSpace($newName)) { "(Sans nom)" } else { $newName } 
                    }
                }
            }.GetNewClosure())
    }

    if ($Ctrl.EdLinkUrlBox) {
        $Ctrl.EdLinkUrlBox.Add_TextChanged({
                $sel = $Ctrl.EdTree.SelectedItem
                if ($sel -and $sel.Tag -and $sel.Tag.Type -eq "Link") {
                    $newUrl = $Ctrl.EdLinkUrlBox.Text
                    $sel.Tag.Url = $newUrl
                    # Pas de changement visuel direct sur l'arbre pour l'URL, mais le Tag est à jour
                }
            }.GetNewClosure())
    }

    # ==========================================================================
    # 3. ACTIONS ARBRE
    # ==========================================================================
    if ($Ctrl.EdBtnNew) {
        $Ctrl.EdBtnNew.Add_Click({
                if ($Ctrl.EdTree -and $Ctrl.EdTree.Items.Count -gt 0) {
                    if ([System.Windows.MessageBox]::Show("Tout effacer ?", "Confirmation", "YesNo", "Warning") -eq 'No') { return }
                }
                if ($Ctrl.EdTree) { $Ctrl.EdTree.Items.Clear() }
                if ($Ctrl.EdPermissionsListBox) { $Ctrl.EdPermissionsListBox.Items.Clear() }
                if ($Ctrl.EdTagsListBox) { $Ctrl.EdTagsListBox.Items.Clear() }
                & $SetStatus -Msg "Nouvel espace de travail vierge prêt."
            }.GetNewClosure())
    }

    if ($Ctrl.EdBtnRoot) {
        $Ctrl.EdBtnRoot.Add_Click({ 
                $newItem = New-EditorNode -Name "Racine"
                if ($Ctrl.EdTree) { $Ctrl.EdTree.Items.Add($newItem) | Out-Null; $newItem.IsSelected = $true }
            }.GetNewClosure())
    }

    if ($Ctrl.EdBtnRootLink) {
        $Ctrl.EdBtnRootLink.Add_Click({
                $newItem = New-EditorLinkNode -Name "Nouveau Lien" -Url "https://pnp.github.io/"
                if ($Ctrl.EdTree) { $Ctrl.EdTree.Items.Add($newItem) | Out-Null; $newItem.IsSelected = $true }
            }.GetNewClosure())
    }

    if ($Ctrl.EdBtnChild) {
        $Ctrl.EdBtnChild.Add_Click({
                $p = if ($Ctrl.EdTree) { $Ctrl.EdTree.SelectedItem }
                if ($null -eq $p) { [System.Windows.MessageBox]::Show("Sélectionnez un dossier.", "Info", "OK", "Information"); return }
                $n = New-EditorNode -Name "Nouveau dossier"; $p.Items.Add($n) | Out-Null; $p.IsExpanded = $true; $n.IsSelected = $true
            }.GetNewClosure())
    }

    if ($Ctrl.EdBtnChildLink) {
        $Ctrl.EdBtnChildLink.Add_Click({
                $p = if ($Ctrl.EdTree) { $Ctrl.EdTree.SelectedItem }
                if ($null -eq $p) { [System.Windows.MessageBox]::Show("Sélectionnez un dossier.", "Info", "OK", "Information"); return }
                # Verif si c'est un dossier (pas un lien)
                if ($p.Tag.Type -eq "Link") { [System.Windows.MessageBox]::Show("Impossible d'ajouter un lien dans un lien.", "Info", "OK", "Warning"); return }
                
                $n = New-EditorLinkNode -Name "Nouveau lien" -Url "https://pnp.github.io/"
                $p.Items.Add($n) | Out-Null; $p.IsExpanded = $true; $n.IsSelected = $true
            }.GetNewClosure())
    }

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

    # ==========================================================================
    # 5. PERSISTANCE (LOAD / SAVE / NEW / DELETE)
    # ==========================================================================
    # ... BLOC PERSISTANCE ...
    
    $ResetUI = {
        $Ctrl.EdTree.Items.Clear()
        $Ctrl.EdNameBox.Text = ""
        # Reset new inputs
        if ($Ctrl.EdPermIdentityBox) { $Ctrl.EdPermIdentityBox.Text = "" }
        if ($Ctrl.EdTagNameBox) { $Ctrl.EdTagNameBox.Text = "" }
        if ($Ctrl.EdLinkNameBox) { $Ctrl.EdLinkNameBox.Text = "" }
        
        # Hide all panels
        $Ctrl.EdNoSelPanel.Visibility = "Visible"
        $Ctrl.EdPropPanel.Visibility = "Collapsed"
        if ($Ctrl.EdPropPanelPerm) { $Ctrl.EdPropPanelPerm.Visibility = "Collapsed" }
        if ($Ctrl.EdPropPanelTag) { $Ctrl.EdPropPanelTag.Visibility = "Collapsed" }
        if ($Ctrl.EdPropPanelLink) { $Ctrl.EdPropPanelLink.Visibility = "Collapsed" }
        
        $Ctrl.EdLoadCb.Tag = $null; $Ctrl.EdLoadCb.SelectedIndex = -1
        & $SetStatus -Msg "Interface réinitialisée."
    }.GetNewClosure()

    $LoadTemplateList = {
        try {
            $tpls = @(Get-AppSPTemplates)
            $Ctrl.EdLoadCb.ItemsSource = $tpls
            $Ctrl.EdLoadCb.DisplayMemberPath = "DisplayName"
        }
        catch { }
    }.GetNewClosure()
    & $LoadTemplateList

    $Ctrl.EdBtnNew.Add_Click({
            if ($Ctrl.EdTree.Items.Count -gt 0) {
                if ([System.Windows.MessageBox]::Show("Tout effacer et créer un nouveau modèle ?", "Confirmation", "YesNo", "Warning") -eq 'No') { return }
            }
            & $ResetUI
            & $SetStatus -Msg "Nouveau modèle vierge prêt."
        }.GetNewClosure())

    $Ctrl.EdBtnLoad.Add_Click({
            $selectedTpl = $Ctrl.EdLoadCb.SelectedItem
            if (-not $selectedTpl) { & $SetStatus -Msg "Aucun modèle sélectionné." -Type "Warning"; return }
            
            if ($Ctrl.EdTree.Items.Count -gt 0) { if ([System.Windows.MessageBox]::Show("Charger va écraser le modèle actuel. Continuer ?", "Attention", "YesNo", "Warning") -ne 'Yes') { return } }
            
            if ($Ctrl.EdTree) { Convert-JsonToEditorTree -Json $selectedTpl.StructureJson -TreeView $Ctrl.EdTree }
                
            # Use Helper to hide all -> avoid null ref on missing panels
            # Use Helper to hide all -> avoid null ref on missing panels
            if ($Ctrl.EdPropPanel) { $Ctrl.EdPropPanel.Visibility = "Collapsed" }
            if ($Ctrl.EdPropPanelPerm) { $Ctrl.EdPropPanelPerm.Visibility = "Collapsed" }
            if ($Ctrl.EdPropPanelTag) { $Ctrl.EdPropPanelTag.Visibility = "Collapsed" }
            if ($Ctrl.EdPropPanelLink) { $Ctrl.EdPropPanelLink.Visibility = "Collapsed" }
                
            if ($Ctrl.EdNoSelPanel) { $Ctrl.EdNoSelPanel.Visibility = "Visible" }
                
            $Ctrl.EdLoadCb.Tag = $selectedTpl.TemplateId
            
            & $SetStatus -Msg "Modèle '$($selectedTpl.DisplayName)' chargé." -Type "Success"
        }.GetNewClosure())

    $Ctrl.EdBtnSave.Add_Click({
            if ($Ctrl.EdTree.Items.Count -eq 0) { [System.Windows.MessageBox]::Show("L'arbre est vide.", "Erreur", "OK", "Warning"); return }

            $json = Convert-EditorTreeToJson -TreeView $Ctrl.EdTree
            # Note : Plus besoin de faire le .Replace("'", "''") ici, c'est géré par le module Database
        
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
                # APPEL PROPRE AU MODULE DATABASE
                Set-AppSPTemplate -TemplateId $currentId -DisplayName $currentName -Description "Modèle personnalisé" -StructureJson $json
            
                # [System.Windows.MessageBox]::Show("Modèle '$currentName' sauvegardé !", "Succès", "OK", "Information")
                & $SetStatus -Msg "Modèle '$currentName' sauvegardé avec succès." -Type "Success"
            
                & $LoadTemplateList
                $newItem = $Ctrl.EdLoadCb.ItemsSource | Where-Object { $_.TemplateId -eq $currentId } | Select-Object -First 1
                if ($newItem) { $Ctrl.EdLoadCb.SelectedItem = $newItem; $Ctrl.EdLoadCb.Tag = $currentId }

            }
            catch { & $SetStatus -Msg "Erreur lors de la sauvegarde : $($_.Exception.Message)" -Type "Error" }

        }.GetNewClosure())

    if ($Ctrl.EdBtnDeleteTpl) {
        $Ctrl.EdBtnDeleteTpl.Add_Click({
                $currentId = $Ctrl.EdLoadCb.Tag
                if (-not $currentId -and $Ctrl.EdLoadCb.SelectedItem) { $currentId = $Ctrl.EdLoadCb.SelectedItem.TemplateId }
                if (-not $currentId) { [System.Windows.MessageBox]::Show("Aucun modèle sélectionné.", "Info", "OK", "Information"); return }
            
                $nom = if ($Ctrl.EdLoadCb.SelectedItem) { $Ctrl.EdLoadCb.SelectedItem.DisplayName } else { "ce modèle" }
            
                if ([System.Windows.MessageBox]::Show("Supprimer définitivement '$nom' ?", "Suppression", "YesNo", "Error") -eq 'Yes') {
                    try {
                        # APPEL PROPRE AU MODULE DATABASE
                        Remove-AppSPTemplate -TemplateId $currentId
                    
                        & $SetStatus -Msg "Modèle '$nom' supprimé." -Type "Normal"
                        & $LoadTemplateList; & $ResetUI
                    }
                    catch { & $SetStatus -Msg "Erreur suppression : $($_.Exception.Message)" -Type "Error" }
                }
            }.GetNewClosure())
    }
}