# Scripts/SharePoint/SharePointBuilder/Functions/Logic/Editor/Register-EditorSelection.ps1

<#
.SYNOPSIS
    Gère la sélection d'éléments dans le TreeView et l'affichage des propriétés.
#>
function Global:Register-EditorSelectionHandler {
    param(
        [hashtable]$Ctrl,
        [System.Windows.Window]$Window
    )

    $Script:IsPopulating = $false
    
    # INIT STATIC SOURCES
    if ($Ctrl.EdPubGrantLevelBox) { $Ctrl.EdPubGrantLevelBox.ItemsSource = @("Read", "Contribute"); $Ctrl.EdPubGrantLevelBox.SelectedIndex = 0 }

    if ($Ctrl.EdTree) {
        $Ctrl.EdTree.Add_SelectedItemChanged({
                $selectedItem = $Ctrl.EdTree.SelectedItem
                $Script:IsPopulating = $true
            
                # 1. HIDE ALL PANELS (Reset State)
                if ($Ctrl.EdNoSelPanel) { $Ctrl.EdNoSelPanel.Visibility = "Collapsed" }
                if ($Ctrl.EdPropPanel) { $Ctrl.EdPropPanel.Visibility = "Collapsed" }
                if ($Ctrl.EdPropPanelPerm) { $Ctrl.EdPropPanelPerm.Visibility = "Collapsed" }
                if ($Ctrl.EdPropPanelTag) { $Ctrl.EdPropPanelTag.Visibility = "Collapsed" }
                if ($Ctrl.EdPropPanelLink) { $Ctrl.EdPropPanelLink.Visibility = "Collapsed" }
                if ($Ctrl.EdPropPanelInternalLink) { $Ctrl.EdPropPanelInternalLink.Visibility = "Collapsed" }
                if ($Ctrl.EdPropPanelPub) { $Ctrl.EdPropPanelPub.Visibility = "Collapsed" }
                if ($Ctrl.EdPanelGlobalTags) { $Ctrl.EdPanelGlobalTags.Visibility = "Collapsed" } # Deprecated/Removed

                if ($null -eq $selectedItem) {
                    if ($Ctrl.EdNoSelPanel) { $Ctrl.EdNoSelPanel.Visibility = "Visible" }
                    $Script:IsPopulating = $false
                    return
                }

                # 2. DETERMINE TYPE
                $data = $selectedItem.Tag
            
                # --- TYPE SPECIFIC UI DISPLAY ---
            
                # A. PERMISSION
                if ($data.Type -eq "Permission") {
                    if ($Ctrl.EdPropPanelPerm) { 
                        $Ctrl.EdPropPanelPerm.Visibility = "Visible" 
                        $Ctrl.EdPropPanelPerm.DataContext = $selectedItem 
                        if ($Ctrl.EdPermIdentityBox) { $Ctrl.EdPermIdentityBox.Text = $data.Email }
                        if ($Ctrl.EdPermLevelBox) { 
                            $Ctrl.EdPermLevelBox.ItemsSource = @("Read", "Contribute", "Full Control")
                            $Ctrl.EdPermLevelBox.Text = $data.Level
                        }
                    }
                }
                # B. TAG
                elseif ($data.Type -eq "Tag") {
                    if ($Ctrl.EdPropPanelTag) {
                        $Ctrl.EdPropPanelTag.Visibility = "Visible"
                        $Ctrl.EdPropPanelTag.DataContext = $selectedItem
                        if ($Ctrl.EdTagNameBox) { $Ctrl.EdTagNameBox.Text = $data.Name }
                        if ($Ctrl.EdTagValueBox) { $Ctrl.EdTagValueBox.Text = $data.Value }
                    }
                }
                # C. LINK
                elseif ($data.Type -eq "Link") {
                    if ($Ctrl.EdPropPanelLink) {
                        $Ctrl.EdPropPanelLink.Visibility = "Visible"
                        $Ctrl.EdPropPanelLink.DataContext = $selectedItem
                        if ($Ctrl.EdLinkNameBox) { $Ctrl.EdLinkNameBox.Text = $data.Name }
                        if ($Ctrl.EdLinkUrlBox) { $Ctrl.EdLinkUrlBox.Text = $data.Url }
                    }
                }
                # D. INTERNAL LINK
                elseif ($data.Type -eq "InternalLink") {
                    if ($Ctrl.EdPropPanelInternalLink) {
                        $Ctrl.EdPropPanelInternalLink.Visibility = "Visible"
                        $Ctrl.EdPropPanelInternalLink.DataContext = $selectedItem
                        if ($Ctrl.EdInternalLinkNameBox) { $Ctrl.EdInternalLinkNameBox.Text = $data.Name }
                        if ($Ctrl.EdInternalLinkIdBox) { $Ctrl.EdInternalLinkIdBox.Text = $data.TargetNodeId }
                    }
                }
                # E. PUBLICATION
                elseif ($data.Type -eq "Publication") {
                    if ($Ctrl.EdPropPanelPub) {
                        $Ctrl.EdPropPanelPub.Visibility = "Visible"
                        $Ctrl.EdPropPanelPub.DataContext = $selectedItem
                    
                        if ($Ctrl.EdPubNameBox) { $Ctrl.EdPubNameBox.Text = $data.Name }
                        if ($Ctrl.EdPubSiteModeBox) { $Ctrl.EdPubSiteModeBox.SelectedIndex = if ($data.TargetSiteMode -eq "Auto") { 0 } else { 1 } }
                    
                        if ($Ctrl.EdPubSiteUrlBox) { 
                            $Ctrl.EdPubSiteUrlBox.Text = $data.TargetSiteUrl 
                            $Ctrl.EdPubSiteUrlBox.Visibility = if ($data.TargetSiteMode -eq "Url") { "Visible" } else { "Collapsed" }
                        }
                        if ($Ctrl.EdPubPathBox) { $Ctrl.EdPubPathBox.Text = $data.TargetFolderPath }
                        if ($Ctrl.EdPubUseModelNameChk) { $Ctrl.EdPubUseModelNameChk.IsChecked = $data.UseModelName }
                    
                        if ($Ctrl.EdPubGrantUserBox) { $Ctrl.EdPubGrantUserBox.Text = $data.GrantUser }
                        if ($Ctrl.EdPubGrantLevelBox) { $Ctrl.EdPubGrantLevelBox.Text = $data.GrantLevel }
                    }
                }
                # F. FOLDER (Standard)
                else {
                    if ($Ctrl.EdPropPanel) { $Ctrl.EdPropPanel.Visibility = "Visible" }
                    if ($data -and $Ctrl.EdNameBox) { $Ctrl.EdNameBox.Text = $data.Name }
                    if ($data -and $Ctrl.EdFolderIdBox) { $Ctrl.EdFolderIdBox.Text = $data.Id }
                
                    # Note: No longer populating ListBoxes for Permissions/Tags here.
                }
            
                # --- BUTTON STATES ---
                $hasSelection = ($null -ne $selectedItem)
                $isLink = ($hasSelection -and ($data.Type -eq "Link" -or $data.Type -eq "InternalLink"))
                $isMeta = ($hasSelection -and ($data.Type -eq "Permission" -or $data.Type -eq "Tag" -or $selectedItem.Name -eq "MetaItem"))
                $isPublication = ($hasSelection -and $data.Type -eq "Publication")
            
                $canHaveChildren = ($hasSelection -and -not $isLink -and -not $isMeta -and -not $isPublication)
            
                if ($Ctrl.EdBtnRoot) { $Ctrl.EdBtnRoot.IsEnabled = $true }
                if ($Ctrl.EdBtnRootLink) { $Ctrl.EdBtnRootLink.IsEnabled = $true }
            
                if ($Ctrl.EdBtnChild) { $Ctrl.EdBtnChild.IsEnabled = $canHaveChildren }
                if ($Ctrl.EdBtnChildLink) { $Ctrl.EdBtnChildLink.IsEnabled = $canHaveChildren }
                if ($Ctrl.EdBtnChildInternalLink) { $Ctrl.EdBtnChildInternalLink.IsEnabled = $canHaveChildren }
                if ($Ctrl.EdBtnAddPub) { $Ctrl.EdBtnAddPub.IsEnabled = $canHaveChildren }

                # Delete always enabled if selection
                if ($Ctrl.EdBtnDel) { $Ctrl.EdBtnDel.IsEnabled = $hasSelection }
            
                # Global Perm (Only on Containers)
                if ($Ctrl.EdBtnGlobalAddPerm) { $Ctrl.EdBtnGlobalAddPerm.IsEnabled = $canHaveChildren }
            
                # Global Tags (Containers + Publications + Links)
                # Allowed on Folder, Link, InternalLink, Publication. Not on Meta.
                $canHaveTags = ($hasSelection -and -not $isMeta)
                if ($Ctrl.EdBtnGlobalAddTag) { $Ctrl.EdBtnGlobalAddTag.IsEnabled = $canHaveTags }

                $Script:IsPopulating = $false
            }.GetNewClosure())
    }
    
    # ==================================================================================
    # PROPERTY CHANGE HANDLERS
    # ==================================================================================

    # 1. PERMISSIONS
    if ($Ctrl.EdPermIdentityBox) {
        $Ctrl.EdPermIdentityBox.Add_TextChanged({
                if ($Script:IsPopulating) { return }
                $sel = $Ctrl.EdTree.SelectedItem
                if ($sel -and $sel.Tag.Type -eq "Permission") {
                    $sel.Tag.Email = $this.Text
                    # Compatibility properties if needed exist in object creation
                    if ($sel.Tag.PSObject.Properties['User']) { $sel.Tag.User = $this.Text }
                
                    $pName = "$($this.Text) ($($sel.Tag.Level))"
                    # Update Header Text (TextBlock usually at index 1 or 2 depending on Icon)
                    # New-EditorPermNode: Icon(0), Text(1)
                    # FIX: Target Index 1 directly to skip Icon which is now a TextBlock
                    if ($sel.Header -is [System.Windows.Controls.StackPanel] -and $sel.Header.Children.Count -ge 2) { 
                        $sel.Header.Children[1].Text = $pName 
                    }
                }
            }.GetNewClosure())
    }
    if ($Ctrl.EdPermLevelBox) {
        $Ctrl.EdPermLevelBox.Add_SelectionChanged({
                if ($Script:IsPopulating) { return }
                $sel = $Ctrl.EdTree.SelectedItem
                if ($sel -and $sel.Tag.Type -eq "Permission" -and $this.SelectedItem) {
                    $sel.Tag.Level = $this.SelectedItem
                    $pName = "$($sel.Tag.Email) ($($this.SelectedItem))"
                    if ($sel.Header -is [System.Windows.Controls.StackPanel] -and $sel.Header.Children.Count -ge 2) { 
                        $sel.Header.Children[1].Text = $pName 
                    }
                }
            }.GetNewClosure())
    }
    if ($Ctrl.EdPermDeleteButton) {
        $Ctrl.EdPermDeleteButton.Add_Click({
                $sel = $Ctrl.EdTree.SelectedItem
                if ($sel -and $sel.Tag.Type -eq "Permission") {
                    $parent = $sel.Parent
                    if ($parent -is [System.Windows.Controls.TreeViewItem]) {
                        $parent.Items.Remove($sel)
                        Update-EditorBadges -TreeItem $parent
            
                        # Reset UI
                        if ($Ctrl.EdPropPanelPerm) { $Ctrl.EdPropPanelPerm.Visibility = "Collapsed" }
                        if ($Ctrl.EdNoSelPanel) { $Ctrl.EdNoSelPanel.Visibility = "Visible" }
                    }
                }
            }.GetNewClosure())
    }

    # 2. TAGS
    if ($Ctrl.EdTagNameBox) {
        $Ctrl.EdTagNameBox.Add_TextChanged({
                if ($Script:IsPopulating) { return }
                $sel = $Ctrl.EdTree.SelectedItem
                if ($sel -and $sel.Tag.Type -eq "Tag") {
                    $sel.Tag.Name = $this.Text
                    $tName = "$($this.Text) : $($sel.Tag.Value)"
                    # New-EditorTagNode: Icon(0), Text(1)
                    # FIX: Target Index 1 directly
                    if ($sel.Header -is [System.Windows.Controls.StackPanel] -and $sel.Header.Children.Count -ge 2) { 
                        $sel.Header.Children[1].Text = $tName 
                    }
                }
            }.GetNewClosure())
    }
    if ($Ctrl.EdTagValueBox) {
        $Ctrl.EdTagValueBox.Add_TextChanged({
                if ($Script:IsPopulating) { return }
                $sel = $Ctrl.EdTree.SelectedItem
                if ($sel -and $sel.Tag.Type -eq "Tag") {
                    $sel.Tag.Value = $this.Text
                    $tName = "$($sel.Tag.Name) : $($this.Text)"
                    if ($sel.Header -is [System.Windows.Controls.StackPanel] -and $sel.Header.Children.Count -ge 2) { 
                        $sel.Header.Children[1].Text = $tName 
                    } 
                }
            }.GetNewClosure())
    }
    if ($Ctrl.EdTagDeleteButton) {
        $Ctrl.EdTagDeleteButton.Add_Click({
                $sel = $Ctrl.EdTree.SelectedItem
                if ($sel -and $sel.Tag.Type -eq "Tag") {
                    $parent = $sel.Parent
                    if ($parent -is [System.Windows.Controls.TreeViewItem]) {
                        $parent.Items.Remove($sel)
                        Update-EditorBadges -TreeItem $parent
            
                        if ($Ctrl.EdPropPanelTag) { $Ctrl.EdPropPanelTag.Visibility = "Collapsed" }
                        if ($Ctrl.EdNoSelPanel) { $Ctrl.EdNoSelPanel.Visibility = "Visible" }
                    }
                }
            }.GetNewClosure())
    }

    # 3. OTHER TYPES (Name & URL)
    
    # Generic Name Box (Folder)
    if ($Ctrl.EdNameBox) {
        $Ctrl.EdNameBox.Add_TextChanged({
                $sel = $Ctrl.EdTree.SelectedItem
                # Only for Folder (No Permission, Tag, Link, etc.)
                if ($sel -and $sel.Tag -and $sel.Tag.Type -ne "Link" -and $sel.Tag.Type -ne "InternalLink" -and $sel.Tag.Type -ne "Publication" -and $sel.Tag.Type -ne "Permission" -and $sel.Tag.Type -ne "Tag" ) {
                    $newName = $Ctrl.EdNameBox.Text
                    $sel.Tag.Name = $newName
                    if ($sel.Header -is [System.Windows.Controls.StackPanel] -and $sel.Header.Children.Count -ge 2) { 
                        # FIX: Icon is [0], Text is [1]. Do not search for TextBlock type as Icon is now TextBlock too.
                        $txtBlock = $sel.Header.Children[1]
                        if ($txtBlock -is [System.Windows.Controls.TextBlock]) {
                            $txtBlock.Text = if ([string]::IsNullOrWhiteSpace($newName)) { "(Sans nom)" } else { $newName }
                        }
                    }
                } 
            }.GetNewClosure())
    }

    # Links
    if ($Ctrl.EdLinkNameBox) {
        $Ctrl.EdLinkNameBox.Add_TextChanged({
                $sel = $Ctrl.EdTree.SelectedItem
                if ($sel -and $sel.Tag -and $sel.Tag.Type -eq "Link") {
                    $newName = $Ctrl.EdLinkNameBox.Text
                    $sel.Tag.Name = $newName
                    if ($sel.Header -is [System.Windows.Controls.StackPanel]) { 
                        $txtBlock = $sel.Header.Children | Where-Object { $_ -is [System.Windows.Controls.TextBlock] } | Select-Object -First 1
                        if ($txtBlock) { $txtBlock.Text = if ([string]::IsNullOrWhiteSpace($newName)) { "(Sans nom)" } else { $newName } }
                    }
                }
            }.GetNewClosure())
    }
    if ($Ctrl.EdLinkUrlBox) {
        $Ctrl.EdLinkUrlBox.Add_TextChanged({
                $sel = $Ctrl.EdTree.SelectedItem
                if ($sel -and $sel.Tag -and $sel.Tag.Type -eq "Link") {
                    $sel.Tag.Url = $this.Text
                }
            }.GetNewClosure())
    }
    if ($Ctrl.EdLinkDeleteButton) {
        $Ctrl.EdLinkDeleteButton.Add_Click({
                $sel = $Ctrl.EdTree.SelectedItem
                if ($sel -and $sel.Tag.Type -eq "Link") {
                    $parent = $sel.Parent
                    if ($parent -is [System.Windows.Controls.TreeViewItem]) {
                        $parent.Items.Remove($sel)
                        Update-EditorBadges -TreeItem $parent
                    }
                    elseif ($parent -is [System.Windows.Controls.TreeView]) { $parent.Items.Remove($sel) }
                
                    if ($Ctrl.EdPropPanelLink) { $Ctrl.EdPropPanelLink.Visibility = "Collapsed" }
                    if ($Ctrl.EdNoSelPanel) { $Ctrl.EdNoSelPanel.Visibility = "Visible" }
                }
            }.GetNewClosure())
    }

    # Publications
    if ($Ctrl.EdPubNameBox) {
        $Ctrl.EdPubNameBox.Add_TextChanged({
                if ($Script:IsPopulating) { return }
                $sel = $Ctrl.EdTree.SelectedItem
                if ($sel -and $sel.Tag.Type -eq "Publication") {
                    $sel.Tag.Name = $this.Text
                    if ($sel.Header -is [System.Windows.Controls.StackPanel] -and $sel.Header.Children.Count -ge 2) { 
                        $txtBlock = $sel.Header.Children[1]
                        if ($txtBlock) { $txtBlock.Text = $this.Text }
                    }
                }
            }.GetNewClosure())
    }
    if ($Ctrl.EdPubSiteModeBox) {
        $Ctrl.EdPubSiteModeBox.Add_SelectionChanged({
                if ($Script:IsPopulating) { return }
                $sel = $Ctrl.EdTree.SelectedItem
                if ($sel -and $sel.Tag.Type -eq "Publication") {
                    $mode = if ($this.SelectedIndex -eq 0) { "Auto" } else { "Url" }
                    $sel.Tag.TargetSiteMode = $mode
                    if ($Ctrl.EdPubSiteUrlBox) {
                        $Ctrl.EdPubSiteUrlBox.Visibility = if ($mode -eq "Url") { "Visible" } else { "Collapsed" }
                    }
                }
            }.GetNewClosure())
    }
    if ($Ctrl.EdPubSiteUrlBox) {
        $Ctrl.EdPubSiteUrlBox.Add_TextChanged({
                if ($Script:IsPopulating) { return }
                $sel = $Ctrl.EdTree.SelectedItem
                if ($sel -and $sel.Tag.Type -eq "Publication") { $sel.Tag.TargetSiteUrl = $this.Text }
            }.GetNewClosure())
    }
    if ($Ctrl.EdPubPathBox) {
        $Ctrl.EdPubPathBox.Add_TextChanged({
                if ($Script:IsPopulating) { return }
                $sel = $Ctrl.EdTree.SelectedItem
                if ($sel -and $sel.Tag.Type -eq "Publication") { $sel.Tag.TargetFolderPath = $this.Text }
            }.GetNewClosure())
    }
    if ($Ctrl.EdPubUseModelNameChk) {
        $Ctrl.EdPubUseModelNameChk.Add_Click({
                if ($Script:IsPopulating) { return }
                $sel = $Ctrl.EdTree.SelectedItem
                if ($sel -and $sel.Tag.Type -eq "Publication") { $sel.Tag.UseModelName = [bool]$this.IsChecked }
            }.GetNewClosure())
    }
    if ($Ctrl.EdPubGrantUserBox) {
        $Ctrl.EdPubGrantUserBox.Add_TextChanged({
                if ($Script:IsPopulating) { return }
                $sel = $Ctrl.EdTree.SelectedItem
                if ($sel -and $sel.Tag.Type -eq "Publication") { $sel.Tag.GrantUser = $this.Text }
            }.GetNewClosure())
    }
    if ($Ctrl.EdPubGrantLevelBox) {
        $Ctrl.EdPubGrantLevelBox.Add_SelectionChanged({
                if ($Script:IsPopulating) { return }
                $sel = $Ctrl.EdTree.SelectedItem
                if ($sel -and $sel.Tag.Type -eq "Publication") { $sel.Tag.GrantLevel = $this.SelectedItem }
            }.GetNewClosure())
    }
    if ($Ctrl.EdPubDeleteButton) {
        $Ctrl.EdPubDeleteButton.Add_Click({
                $sel = $Ctrl.EdTree.SelectedItem
                if ($sel -and $sel.Tag.Type -eq "Publication") {
                    if ([System.Windows.MessageBox]::Show("Supprimer cette publication ?", "Confirmation", "YesNo", "Question") -eq 'No') { return }
                    $parent = $sel.Parent
                    if ($parent -is [System.Windows.Controls.TreeViewItem]) { 
                        $parent.Items.Remove($sel) 
                        Update-EditorBadges -TreeItem $parent
                    }
                    elseif ($parent -is [System.Windows.Controls.TreeView]) { $parent.Items.Remove($sel) }
        
                    if ($Ctrl.EdPropPanelPub) { $Ctrl.EdPropPanelPub.Visibility = "Collapsed" }
                    if ($Ctrl.EdNoSelPanel) { $Ctrl.EdNoSelPanel.Visibility = "Visible" }
                }
            }.GetNewClosure())
    }

    # Internal Links
    if ($Ctrl.EdInternalLinkNameBox) {
        $Ctrl.EdInternalLinkNameBox.Add_TextChanged({
                if ($Script:IsPopulating) { return }
                $sel = $Ctrl.EdTree.SelectedItem
                if ($sel -and $sel.Tag.Type -eq "InternalLink") {
                    $sel.Tag.Name = $this.Text
                    if ($sel.Header -is [System.Windows.Controls.StackPanel] -and $sel.Header.Children.Count -ge 2) { 
                        # FIX: Target Index 1
                        $sel.Header.Children[1].Text = $this.Text 
                    }
                } 
            }.GetNewClosure())
    }
}
