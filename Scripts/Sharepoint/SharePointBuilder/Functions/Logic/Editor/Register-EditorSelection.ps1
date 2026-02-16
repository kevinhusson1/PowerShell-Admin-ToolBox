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

    $Script:PubPathHandler = {
        if ($Ctrl.EdTree.SelectedItem) {
            $Ctrl.EdTree.SelectedItem.Tag.SourceUrl = $Ctrl.EdPubPathBox.Text # Re-use property
        }
    }

    $Script:FileNameHandler = {
        if ($Ctrl.EdTree.SelectedItem) {
            $Ctrl.EdTree.SelectedItem.Tag.Name = $Ctrl.EdFileNameBox.Text
            Update-EditorChildNode -ParentItem $Ctrl.EdTree.SelectedItem.Parent -DataObject $Ctrl.EdTree.SelectedItem.Tag
        }
    }

    $Script:FileUrlHandler = {
        if ($Ctrl.EdTree.SelectedItem) {
            $Ctrl.EdTree.SelectedItem.Tag.SourceUrl = $Ctrl.EdFileUrlBox.Text
        }
    }
    
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
                if ($Ctrl.EdPanelFile) { $Ctrl.EdPanelFile.Visibility = "Collapsed" }
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
                    
                    if ($data.IsDynamic) {
                        # --- DYNAMIC PANEL ---
                        if ($Ctrl.EdPropPanelDynamicTag) {
                            $Ctrl.EdPropPanelDynamicTag.Visibility = "Visible"
                            $Ctrl.EdPropPanelDynamicTag.DataContext = $selectedItem
                            
                            # Name (Removed Box)
                            # if ($Ctrl.EdDynamicTagNameBox) { $Ctrl.EdDynamicTagNameBox.Text = $data.Name }
                            
                            # Source Form (Rule)
                            if ($Ctrl.EdDynamicTagSourceFormBox) {
                                $rules = Get-AppNamingRules
                                
                                # RELOAD IF EMPTY (Data Sync Fix)
                                if ($rules.Count -eq 0 -and (Get-Command "Get-AppNamingRule" -ErrorAction SilentlyContinue)) {
                                    # Try fetching from DB directly if Global is empty
                                    try { 
                                        $rules = @(Get-AppNamingRule) 
                                        if ($Global:AppConfig) {
                                            if ($Global:AppConfig.PSObject.Properties.Match("namingRules").Count -eq 0) {
                                                $Global:AppConfig | Add-Member -MemberType NoteProperty -Name "namingRules" -Value $rules -Force
                                            }
                                            else {
                                                $Global:AppConfig.namingRules = $rules
                                            }
                                        }
                                    }
                                    catch {}
                                }
                                
                                # --- INITIALIZATION (Safe Populating) ---
                                $Script:IsPopulating = $true
                                
                                # 1. Populate Form List (Filtered)
                                $filteredRules = [System.Collections.Generic.List[psobject]]::new()
                                if ($rules) {
                                    foreach ($r in $rules) {
                                        try {
                                            if (-not [string]::IsNullOrWhiteSpace($r.DefinitionJson)) {
                                                $j = $r.DefinitionJson | ConvertFrom-Json
                                                if ($j.Layout) {
                                                    $hasMeta = $j.Layout | Where-Object { $_.IsMetadata -eq $true } | Select-Object -First 1
                                                    if ($hasMeta) { $filteredRules.Add($r) }
                                                }
                                            }
                                        }
                                        catch {}
                                    }
                                }
                                $Ctrl.EdDynamicTagSourceFormBox.DisplayMemberPath = "RuleId"
                                $Ctrl.EdDynamicTagSourceFormBox.ItemsSource = $filteredRules
                                
                                # 2. Select Current Form
                                if ($data.SourceForm) {
                                    $found = $filteredRules | Where-Object { $_.RuleId -eq $data.SourceForm } | Select-Object -First 1
                                    $Ctrl.EdDynamicTagSourceFormBox.SelectedItem = $found
                                }
                                else {
                                    $Ctrl.EdDynamicTagSourceFormBox.SelectedItem = $null
                                }

                                # 3. Populate Variable List (Cascading)
                                $Ctrl.EdDynamicTagSourceVarBox.ItemsSource = $null
                                if ($found) {
                                    try {
                                        $json = $found.DefinitionJson | ConvertFrom-Json
                                        $vars = @($json.Layout | Where-Object { $_.IsMetadata -eq $true } | Select-Object -ExpandProperty Name)
                                        $Ctrl.EdDynamicTagSourceVarBox.ItemsSource = $vars
                                        
                                        # 4. Select Current Variable
                                        if ($data.SourceVar) {
                                            $Ctrl.EdDynamicTagSourceVarBox.SelectedItem = $data.SourceVar
                                        }
                                    }
                                    catch {}
                                }
                                
                                $Script:IsPopulating = $false
                            }
                        }
                        # Hide Static
                        if ($Ctrl.EdPropPanelTag) { $Ctrl.EdPropPanelTag.Visibility = "Collapsed" }
                    }
                    else {
                        # --- STATIC PANEL ---
                        if ($Ctrl.EdPropPanelTag) {
                            $Ctrl.EdPropPanelTag.Visibility = "Visible"
                            $Ctrl.EdPropPanelTag.DataContext = $selectedItem
                            if ($Ctrl.EdTagNameBox) { $Ctrl.EdTagNameBox.Text = $data.Name }
                            if ($Ctrl.EdTagValueBox) { $Ctrl.EdTagValueBox.Text = $data.Value }
                        }
                        # Hide Dynamic
                        if ($Ctrl.EdPropPanelDynamicTag) { $Ctrl.EdPropPanelDynamicTag.Visibility = "Collapsed" }
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
                    if ($Ctrl.EdPropPanelDynamicTag) { $Ctrl.EdPropPanelDynamicTag.Visibility = "Collapsed" }
                }
                # D. INTERNAL LINK
                elseif ($data.Type -eq "InternalLink") {
                    if ($Ctrl.EdPropPanelInternalLink) {
                        $Ctrl.EdPropPanelInternalLink.Visibility = "Visible"
                        $Ctrl.EdPropPanelInternalLink.DataContext = $selectedItem
                        if ($Ctrl.EdInternalLinkNameBox) { $Ctrl.EdInternalLinkNameBox.Text = $data.Name }
                        if ($Ctrl.EdInternalLinkIdBox) { $Ctrl.EdInternalLinkIdBox.Text = $data.TargetNodeId }
                    }
                    if ($Ctrl.EdPropPanelDynamicTag) { $Ctrl.EdPropPanelDynamicTag.Visibility = "Collapsed" }
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
                        if ($Ctrl.EdPubUseFormMetaChk) { 
                            $Ctrl.EdPubUseFormMetaChk.IsChecked = if ($data.UseFormMetadata) { $true } else { $false } 
                            # FIX: Metadata only allowed if creating a folder (UseModelName = true)
                            $Ctrl.EdPubUseFormMetaChk.IsEnabled = [bool]$data.UseModelName
                        }
                    

                    }
                    if ($Ctrl.EdPropPanelDynamicTag) { $Ctrl.EdPropPanelDynamicTag.Visibility = "Collapsed" }
                }
                # F. FILE
                elseif ($data.Type -eq "File") {
                    if ($Ctrl.EdPanelFile) { 
                        $Ctrl.EdPanelFile.Visibility = "Visible" 
                        $Ctrl.EdPanelFile.DataContext = $selectedItem
                    }
                    if ($Ctrl.EdFileNameBox) { $Ctrl.EdFileNameBox.Text = $data.Name }
                    if ($Ctrl.EdFileUrlBox) { $Ctrl.EdFileUrlBox.Text = $data.SourceUrl }
                    
                    if ($Ctrl.EdPropPanelDynamicTag) { $Ctrl.EdPropPanelDynamicTag.Visibility = "Collapsed" }
                }
                # G. FOLDER (Standard)
                else {
                    if ($Ctrl.EdPropPanel) { $Ctrl.EdPropPanel.Visibility = "Visible" }
                    if ($data -and $Ctrl.EdNameBox) { $Ctrl.EdNameBox.Text = $data.Name }
                    if ($data -and $Ctrl.EdFolderIdBox) { $Ctrl.EdFolderIdBox.Text = $data.Id }
                
                    # Note: No longer populating ListBoxes for Permissions/Tags here.
                    if ($Ctrl.EdPropPanelDynamicTag) { $Ctrl.EdPropPanelDynamicTag.Visibility = "Collapsed" }
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
    # 2b. DYNAMIC TAG HANDLERS
    if ($Ctrl.EdTagDynamicCheck) {
        $Ctrl.EdTagDynamicCheck.Add_Click({
                if ($Script:IsPopulating) { return }
                $sel = $Ctrl.EdTree.SelectedItem
                if ($sel -and $sel.Tag.Type -eq "Tag") {
                    $isDyn = [bool]$this.IsChecked
                    $sel.Tag.IsDynamic = $isDyn
                
                    # Switch Visibility
                    if ($isDyn) {
                        if ($Ctrl.EdTagDynamicPanel) { $Ctrl.EdTagDynamicPanel.Visibility = "Visible" }
                        if ($Ctrl.EdTagStaticPanel) { $Ctrl.EdTagStaticPanel.Visibility = "Collapsed" }
                    
                        # Force Load Rules if Empty
                        if ($Ctrl.EdTagSourceFormBox.Items.Count -eq 0) {
                            $rules = Get-AppNamingRules
                            $Ctrl.EdTagSourceFormBox.ItemsSource = $rules
                        }
                    }
                    else {
                        if ($Ctrl.EdTagDynamicPanel) { $Ctrl.EdTagDynamicPanel.Visibility = "Collapsed" }
                        if ($Ctrl.EdTagStaticPanel) { $Ctrl.EdTagStaticPanel.Visibility = "Visible" }
                    }
                }
            }.GetNewClosure())
    }
    
    if ($Ctrl.EdTagSourceFormBox) {
        $Ctrl.EdTagSourceFormBox.Add_SelectionChanged({
                if ($Script:IsPopulating) { return }
                $sel = $Ctrl.EdTree.SelectedItem
                $rule = $this.SelectedItem
                if ($sel -and $sel.Tag.Type -eq "Tag" -and $rule) {
                    $sel.Tag.SourceForm = $rule.RuleId
                
                    # Load Variables
                    try {
                        $json = $rule.DefinitionJson | ConvertFrom-Json
                        $vars = $json.Layout | Where-Object { $_.Type -ne "Label" } | Select-Object -ExpandProperty Name
                        if ($Ctrl.EdTagSourceVarBox) {
                            $Ctrl.EdTagSourceVarBox.ItemsSource = $vars
                            $Ctrl.EdTagSourceVarBox.SelectedIndex = -1
                        }
                    }
                    catch { }
                }
            }.GetNewClosure())
    }
    
    if ($Ctrl.EdTagSourceVarBox) {
        $Ctrl.EdTagSourceVarBox.Add_SelectionChanged({
                if ($Script:IsPopulating) { return }
                $sel = $Ctrl.EdTree.SelectedItem
                if ($sel -and $sel.Tag.Type -eq "Tag" -and $this.SelectedItem) {
                    $sel.Tag.SourceVar = $this.SelectedItem
                
                    # Update visual text
                    $tName = "$($sel.Tag.Name) : [$($sel.Tag.SourceVar)]"
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
                if ($Script:IsPopulating) { return }
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
                if ($Script:IsPopulating) { return }
                $sel = $Ctrl.EdTree.SelectedItem
                if ($sel -and $sel.Tag -and $sel.Tag.Type -eq "Link") {
                    $newName = $Ctrl.EdLinkNameBox.Text
                    $sel.Tag.Name = $newName
                    if ($sel.Header -is [System.Windows.Controls.StackPanel] -and $sel.Header.Children.Count -ge 2) { 
                        $txtBlock = $sel.Header.Children[1]
                        if ($txtBlock -is [System.Windows.Controls.TextBlock]) {
                            $txtBlock.Text = if ([string]::IsNullOrWhiteSpace($newName)) { "(Sans nom)" } else { $newName }
                        }
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
                    
                    # Update Visual
                    $tName = $this.Text
                    if ($sel.Tag.UseFormMetadata) { $tName += " [META]" }
                    
                    if ($sel.Header -is [System.Windows.Controls.StackPanel] -and $sel.Header.Children.Count -ge 2) { 
                        $txtBlock = $sel.Header.Children[1]
                        if ($txtBlock) { $txtBlock.Text = $tName }
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
                if ($sel -and $sel.Tag.Type -eq "Publication") { 
                    $isChecked = [bool]$this.IsChecked
                    $sel.Tag.UseModelName = $isChecked 
                    
                    # FIX: Enforce dependency on Metadata Checkbox
                    if ($Ctrl.EdPubUseFormMetaChk) {
                        $Ctrl.EdPubUseFormMetaChk.IsEnabled = $isChecked
                        if (-not $isChecked) {
                            $Ctrl.EdPubUseFormMetaChk.IsChecked = $false
                            $sel.Tag.UseFormMetadata = $false
                            
                            # Update Visual (Remove [META] badge)
                            if ($sel.Header -is [System.Windows.Controls.StackPanel] -and $sel.Header.Children.Count -ge 2) { 
                                $txtBlock = $sel.Header.Children[1]
                                $txtBlock.Text = $sel.Tag.Name
                                $txtBlock.Foreground = [System.Windows.Media.Brushes]::Black
                            }
                        }
                    }
                }
            }.GetNewClosure())
    }
    if ($Ctrl.EdPubUseFormMetaChk) {
        $Ctrl.EdPubUseFormMetaChk.Add_Click({
                if ($Script:IsPopulating) { return }
                $sel = $Ctrl.EdTree.SelectedItem
                if ($sel -and $sel.Tag.Type -eq "Publication") { 
                    $sel.Tag.UseFormMetadata = [bool]$this.IsChecked 
                    
                    # Update Visual
                    $tName = $sel.Tag.Name
                    $color = [System.Windows.Media.Brushes]::Black
                    
                    if ($sel.Tag.UseFormMetadata) { 
                        $tName += " [META]" 
                        $color = [System.Windows.Media.Brushes]::Teal
                    }
                    
                    if ($sel.Header -is [System.Windows.Controls.StackPanel] -and $sel.Header.Children.Count -ge 2) { 
                        $txtBlock = $sel.Header.Children[1]
                        if ($txtBlock) { 
                            $txtBlock.Text = $tName 
                            $txtBlock.Foreground = $color
                        }
                    }
                }
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
                    if ($sel.Header -is [System.Windows.Controls.StackPanel] -and $sel.Header.Children.Count -ge 3) { 
                        # FIX: Target Index 2 (Name) - Index 0=Icon, 1=Arrow, 2=Name
                        $sel.Header.Children[2].Text = $this.Text 
                    }
                } 
            }.GetNewClosure())
    }

    # File URL Handler
    if ($Ctrl.EdFileUrlBox) {
        $Ctrl.EdFileUrlBox.Add_TextChanged({
                if ($Script:IsPopulating) { return }
                $sel = $Ctrl.EdTree.SelectedItem
                if ($sel -and $sel.Tag.Type -eq "File") {
                    $sel.Tag.SourceUrl = $this.Text
                } 
            }.GetNewClosure())
    }

    # File Name Handler
    if ($Ctrl.EdFileNameBox) {
        $Ctrl.EdFileNameBox.Add_TextChanged({
                if ($Script:IsPopulating) { return }
                $sel = $Ctrl.EdTree.SelectedItem
                if ($sel -and $sel.Tag.Type -eq "File") {
                    $sel.Tag.Name = $this.Text
                    if ($sel.Header -is [System.Windows.Controls.StackPanel] -and $sel.Header.Children.Count -ge 2) { 
                        # Index 1 is TextBlock (Name)
                        $sel.Header.Children[1].Text = $this.Text 
                    }
                } 
            }.GetNewClosure())
    }
    # ==================================================================================
    # NEW: DYNAMIC TAG HANDLERS
    # ==================================================================================
    # REMOVED: Name Box logic (User request)

    if ($Ctrl.EdDynamicTagSourceFormBox) {
        # EVENT: Selection Changed (Logic)
        $Ctrl.EdDynamicTagSourceFormBox.Add_SelectionChanged({
                if ($Script:IsPopulating) { return }
                $sel = $Ctrl.EdTree.SelectedItem
                if ($sel -and $sel.Tag.Type -eq "Tag") { 
                    if ($this.SelectedItem) {
                        # Save ID (Stable) instead of Name
                        $sel.Tag.SourceForm = $this.SelectedItem.RuleId 
                    
                        # Trigger Cascading Update for Variable Box
                        if ($Ctrl.EdDynamicTagSourceVarBox) {
                            $Ctrl.EdDynamicTagSourceVarBox.ItemsSource = $null
                            try {
                                $json = $this.SelectedItem.DefinitionJson | ConvertFrom-Json
                                $vars = @($json.Layout | Where-Object { $_.IsMetadata -eq $true } | Select-Object -ExpandProperty Name)
                                $Ctrl.EdDynamicTagSourceVarBox.ItemsSource = $vars
                            }
                            catch {}
                        }
                    }
                }
            }.GetNewClosure())

        # EVENT: DropDownOpened (Refresh List)
        $Ctrl.EdDynamicTagSourceFormBox.Add_DropDownOpened({
                # Explicit Log for User Debugging (WARNING = Visible)
                Write-Warning "[DynamicTag] Opening DropDown - Fetching Naming Rules from Database..."
                
                # Fetch directly from DB (Module)
                $rules = @()
                if (Get-Command "Get-AppNamingRules" -ErrorAction SilentlyContinue) {
                    $rules = @(Get-AppNamingRules)
                }
                else {
                    Write-Warning "[DynamicTag] ERROR: Command 'Get-AppNamingRules' not found! Check Database module."
                }
                
                Write-Warning "[DynamicTag] Found $($rules.Count) raw rules. Starting analysis..."

                # FILTER: Only Forms containing Metadata Variables
                $filteredRules = [System.Collections.Generic.List[psobject]]::new()
                foreach ($r in $rules) {
                    try {
                        Write-Warning " > Analyzing Rule: $($r.RuleId)"
                        if (-not [string]::IsNullOrWhiteSpace($r.DefinitionJson)) {
                            # Log JSON start
                            $sub = if ($r.DefinitionJson.Length -gt 50) { $r.DefinitionJson.Substring(0, 50) + "..." } else { $r.DefinitionJson }
                            Write-Warning "   JSON: $sub"

                            $j = $r.DefinitionJson | ConvertFrom-Json
                            
                            # Log Object Type
                            Write-Warning "   Type: $($j.GetType().Name)"
                            if ($j.PSObject.Properties['Layout']) {
                                # FIX: Property Name is "IsMetadata" in FormEditor, not "IsMeta"
                                $hasMeta = $j.Layout | Where-Object { $_.IsMetadata -eq $true } | Select-Object -First 1
                                if ($hasMeta) { 
                                    $filteredRules.Add($r)
                                    Write-Warning "   [KEEP] Contains IsMetadata=true."
                                }
                                else {
                                    Write-Warning "   [SKIP] No IsMetadata=true in Layout tags."
                                }
                            }
                            else {
                                Write-Warning "   [SKIP] JSON property 'Layout' missing."
                            }
                        }
                        else {
                            Write-Warning "   [SKIP] DefinitionJson is empty."
                        }
                    }
                    catch {
                        Write-Warning "   [ERROR] Parsing failed: $($_.Exception.Message)"
                    }
                }
                Write-Warning "[DynamicTag] Filtered result: $($filteredRules.Count) rules retained."

                $this.DisplayMemberPath = "RuleId"
                $this.ItemsSource = $filteredRules
            }.GetNewClosure())
    }


    if ($Ctrl.EdDynamicTagSourceVarBox) {
        $Ctrl.EdDynamicTagSourceVarBox.Add_SelectionChanged({
                if ($Script:IsPopulating) { return }
                $sel = $Ctrl.EdTree.SelectedItem
                if ($sel -and $sel.Tag.Type -eq "Tag") { 
                    if ($this.SelectedItem) {
                        $sel.Tag.SourceVar = $this.SelectedItem 
                        
                        # UPDATE: Auto-set Name = SourceVar
                        $sel.Tag.Name = $this.SelectedItem

                        # Update Visual Value to "Dynamic: [VarName]"
                        $sel.Tag.Value = "🎯 $($this.SelectedItem)"
                        
                        # Update Visual Text (Header)
                        # Re-using Update-EditorChildNode logic or direct visual update
                        if ($sel.Header -is [System.Windows.Controls.StackPanel]) {
                            # Index 1 is TextBlock
                            if ($sel.Header.Children.Count -ge 2) {
                                # FIX: User requests removing redundant "Black Bolt" and Value
                                # Result: [YellowIcon] [Name]
                                $sel.Header.Children[1].Text = $sel.Tag.Name
                            }
                        }
                    }
                }
            }.GetNewClosure())
    }

    if ($Ctrl.EdDynamicTagDeleteButton) {
        $Ctrl.EdDynamicTagDeleteButton.Add_Click({
                $sel = $Ctrl.EdTree.SelectedItem
                if ($sel -and $sel.Tag.Type -eq "Tag") {
                    $parent = $sel.Parent
                    if ($parent -is [System.Windows.Controls.TreeViewItem]) {
                        $parent.Items.Remove($sel)
                        Update-EditorBadges -TreeItem $parent
                    }
                    if ($Ctrl.EdPropPanelDynamicTag) { $Ctrl.EdPropPanelDynamicTag.Visibility = "Collapsed" }
                    if ($Ctrl.EdNoSelPanel) { $Ctrl.EdNoSelPanel.Visibility = "Visible" }
                }
            }.GetNewClosure())
    }
}
