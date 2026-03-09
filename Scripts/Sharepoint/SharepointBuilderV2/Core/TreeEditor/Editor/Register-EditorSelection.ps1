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
                if ($Ctrl.EdPropPanelDynamicTag) { $Ctrl.EdPropPanelDynamicTag.Visibility = "Collapsed" }
                if ($Ctrl.EdPropPanelLink) { $Ctrl.EdPropPanelLink.Visibility = "Collapsed" }
                if ($Ctrl.EdPropPanelInternalLink) { $Ctrl.EdPropPanelInternalLink.Visibility = "Collapsed" }
                if ($Ctrl.EdPropPanelPub) { $Ctrl.EdPropPanelPub.Visibility = "Collapsed" }
                if ($Ctrl.EdPanelFile) { $Ctrl.EdPanelFile.Visibility = "Collapsed" }

                if ($null -eq $selectedItem) {
                    if ($Ctrl.EdNoSelPanel) { $Ctrl.EdNoSelPanel.Visibility = "Visible" }
                    
                    # Toolbar States if no selection
                    if ($Ctrl.EdBtnChild) { $Ctrl.EdBtnChild.IsEnabled = $false }
                    if ($Ctrl.EdBtnChildLink) { $Ctrl.EdBtnChildLink.IsEnabled = $false }
                    if ($Ctrl.EdBtnChildInternalLink) { $Ctrl.EdBtnChildInternalLink.IsEnabled = $false }
                    if ($Ctrl.EdBtnAddPub) { $Ctrl.EdBtnAddPub.IsEnabled = $false }
                    if ($Ctrl.EdBtnAddFile) { $Ctrl.EdBtnAddFile.IsEnabled = $false }
                    if ($Ctrl.EdBtnGlobalAddPerm) { $Ctrl.EdBtnGlobalAddPerm.IsEnabled = $false }
                    if ($Ctrl.EdBtnGlobalAddTag) { $Ctrl.EdBtnGlobalAddTag.IsEnabled = $false }
                    if ($Ctrl.EdBtnGlobalAddDynamicTag) { $Ctrl.EdBtnGlobalAddDynamicTag.IsEnabled = $false }
                    if ($Ctrl.EdBtnDel) { $Ctrl.EdBtnDel.IsEnabled = $false }

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
                        if ($Ctrl.EdPermLevelBox -and -not $Ctrl.EdPermLevelBox.ItemsSource) {
                            $Ctrl.EdPermLevelBox.ItemsSource = @("Read", "Contribute", "Full Control")
                        }
                        if ($Ctrl.EdPermLevelBox) { 
                            $idx = switch ($data.Level) {
                                "Read" { 0 }
                                "Contribute" { 1 }
                                "Full Control" { 2 }
                                Default { 0 }
                            }
                            $Ctrl.EdPermLevelBox.SelectedIndex = $idx
                        }
                        
                        # Set Parent ID (Attachement)
                        $pNode = $selectedItem.Parent
                        if ($pNode -is [System.Windows.Controls.TreeViewItem] -and $Ctrl.EdPermParentIdBox) {
                            $Ctrl.EdPermParentIdBox.Text = $pNode.Tag.Id
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
                                $currentSchemaId = if ($Ctrl.EdTargetSchemaDisplay) { $Ctrl.EdTargetSchemaDisplay.Tag } else { "" }
                                
                                if ($rules) {
                                    foreach ($r in $rules) {
                                        try {
                                            if (-not [string]::IsNullOrWhiteSpace($r.DefinitionJson)) {
                                                $j = $r.DefinitionJson | ConvertFrom-Json
                                                
                                                # Filtrage Phase 3 : même Schéma
                                                if ($currentSchemaId -and $j.TargetSchemaId -ne $currentSchemaId) { continue }
                                                
                                                if ($j.Layout) {
                                                    $hasMeta = @($j.Layout) | Where-Object { $_.IsMetadata -eq $true } | Select-Object -First 1
                                                    if ($hasMeta) { 
                                                        # FIX: Create clean object for WPF Binding
                                                        $displayName = if ($r.DisplayName) { $r.DisplayName } elseif ($j.FormName) { $j.FormName } else { $r.RuleId }
                                                        $description = if ($r.Description) { $r.Description } else { $j.Description }
                                                        
                                                        $filteredRules.Add([PSCustomObject]@{
                                                                RuleId         = $r.RuleId
                                                                DisplayName    = $displayName
                                                                Description    = $description
                                                                DefinitionJson = $r.DefinitionJson
                                                            })
                                                    }
                                                }
                                            }
                                        }
                                        catch {}
                                    }
                                }
                                $Ctrl.EdDynamicTagSourceFormBox.DisplayMemberPath = "DisplayName"
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
                            
                            $pNode = $selectedItem.Parent
                            if ($pNode -is [System.Windows.Controls.TreeViewItem] -and $Ctrl.EdDynamicTagParentIdBox) {
                                $Ctrl.EdDynamicTagParentIdBox.Text = $pNode.Tag.Id
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
                            
                            $Script:IsPopulating = $true
                            try {
                                # Populating Column names from Schema
                                $schemaId = if ($Ctrl.EdTargetSchemaDisplay) { $Ctrl.EdTargetSchemaDisplay.Tag } else { $null }
                                if ($schemaId) {
                                    $schemaObj = Get-AppSPFolderSchema | Where-Object { $_.SchemaId -eq $schemaId } | Select-Object -First 1
                                    if ($schemaObj -and $schemaObj.ColumnsJson) {
                                        $cols = @($schemaObj.ColumnsJson | ConvertFrom-Json)
                                        $Ctrl.EdTagColumnBox.DisplayMemberPath = "Name"
                                        $Ctrl.EdTagColumnBox.ItemsSource = $cols
                                        
                                        # Select current
                                        if ($data.Name) {
                                            $foundCol = $cols | Where-Object { $_.Name -eq $data.Name } | Select-Object -First 1
                                            if ($foundCol) { $Ctrl.EdTagColumnBox.SelectedItem = $foundCol }
                                            else { $Ctrl.EdTagColumnBox.SelectedIndex = -1 }
                                        }
                                    }
                                }
                                
                                if ($Ctrl.EdTagValueBox) { $Ctrl.EdTagValueBox.Text = $data.Value }
                                
                                $pNode = $selectedItem.Parent
                                if ($pNode -is [System.Windows.Controls.TreeViewItem] -and $Ctrl.EdTagParentIdBox) {
                                    $Ctrl.EdTagParentIdBox.Text = $pNode.Tag.Id
                                }
                            }
                            finally { $Script:IsPopulating = $false }
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
                        if ($Ctrl.EdLinkIdBox) { $Ctrl.EdLinkIdBox.Text = $data.Id }
                        if ($Ctrl.EdLinkRelativePathBox) { $Ctrl.EdLinkRelativePathBox.Text = $data.RelativePath }
                    }
                }
                # D. INTERNAL LINK
                elseif ($data.Type -eq "InternalLink") {
                    if ($Ctrl.EdPropPanelInternalLink) {
                        $Ctrl.EdPropPanelInternalLink.Visibility = "Visible"
                        $Ctrl.EdPropPanelInternalLink.DataContext = $selectedItem
                        if ($Ctrl.EdInternalLinkNameBox) { $Ctrl.EdInternalLinkNameBox.Text = $data.Name }
                        if ($Ctrl.EdInternalLinkIdBox) { $Ctrl.EdInternalLinkIdBox.Text = $data.TargetNodeId }
                        if ($Ctrl.EdInternalLinkObjIdBox) { $Ctrl.EdInternalLinkObjIdBox.Text = $data.Id }
                        if ($Ctrl.EdInternalLinkRelativePathBox) { $Ctrl.EdInternalLinkRelativePathBox.Text = $data.RelativePath }
                    }
                    if ($Ctrl.EdPropPanelDynamicTag) { $Ctrl.EdPropPanelDynamicTag.Visibility = "Collapsed" }
                }
                # E. PUBLICATION
                elseif ($data.Type -eq "Publication") {
                    if ($Ctrl.EdPropPanelPub) {
                        $Ctrl.EdPropPanelPub.Visibility = "Visible"
                        $Ctrl.EdPropPanelPub.DataContext = $selectedItem
                    
                        if ($Ctrl.EdPubNameBox) { $Ctrl.EdPubNameBox.Text = $data.Name }
                        if ($Ctrl.EdPubIdBox) { $Ctrl.EdPubIdBox.Text = $data.Id }
                        if ($Ctrl.EdPubRelativePathBox) { $Ctrl.EdPubRelativePathBox.Text = $data.RelativePath }
                        
                        if ($Ctrl.EdPubSiteModeBox) { $Ctrl.EdPubSiteModeBox.SelectedIndex = if ($data.TargetSiteMode -eq "Auto") { 0 } else { 1 } }
                    
                        if ($Ctrl.EdPubSiteUrlBox) { 
                            $Ctrl.EdPubSiteUrlBox.Text = $data.TargetSiteUrl 
                            $Ctrl.EdPubSiteUrlBox.Visibility = if ($data.TargetSiteMode -eq "Url") { "Visible" } else { "Collapsed" }
                        }
                        if ($Ctrl.EdPubPathBox) { $Ctrl.EdPubPathBox.Text = $data.TargetFolderPath }
                        if ($Ctrl.EdPubUseFormNameChk) { $Ctrl.EdPubUseFormNameChk.IsChecked = $data.UseFormName }
                        if ($Ctrl.EdPubUseFormMetaChk) { 
                            $Ctrl.EdPubUseFormMetaChk.IsChecked = if ($data.UseFormMetadata) { $true } else { $false } 
                            # FIX: Metadata only allowed if creating a folder (UseFormName = true)
                            $Ctrl.EdPubUseFormMetaChk.IsEnabled = [bool]$data.UseFormName
                        }
                    

                    }
                    if ($Ctrl.EdPropPanelDynamicTag) { $Ctrl.EdPropPanelDynamicTag.Visibility = "Collapsed" }
                }
                # F. FILE
                elseif ($data.Type -eq "File") {
                    # Cacher EdPropPanel (Dossier) ici car on est sur le tag File, pas dossier
                    if ($Ctrl.EdPropPanel) { $Ctrl.EdPropPanel.Visibility = "Collapsed" }
                    
                    if ($Ctrl.EdPanelFile) { 
                        $Ctrl.EdPanelFile.Visibility = "Visible" 
                        $Ctrl.EdPanelFile.DataContext = $selectedItem
                    }
                    if ($Ctrl.EdFileNameBox) { $Ctrl.EdFileNameBox.Text = $data.Name }
                    if ($Ctrl.EdFileUrlBox) { $Ctrl.EdFileUrlBox.Text = $data.SourceUrl }
                    if ($Ctrl.EdFileIdBox) { $Ctrl.EdFileIdBox.Text = $data.Id }
                    if ($Ctrl.EdFileRelativePathBox) { $Ctrl.EdFileRelativePathBox.Text = $data.RelativePath }
                    
                    if ($Ctrl.EdPropPanelDynamicTag) { $Ctrl.EdPropPanelDynamicTag.Visibility = "Collapsed" }
                }
                # G. FOLDER (Standard)
                elseif ($data.Type -eq "Folder") {
                    if ($Ctrl.EdPropPanel) { $Ctrl.EdPropPanel.Visibility = "Visible" }
                    if ($data -and $Ctrl.EdNameBox) { $Ctrl.EdNameBox.Text = $data.Name }
                    if ($data -and $Ctrl.EdFolderIdBox) { $Ctrl.EdFolderIdBox.Text = $data.Id }
                    if ($data -and $Ctrl.EdFolderRelativePathBox) { $Ctrl.EdFolderRelativePathBox.Text = $data.RelativePath }
                }
                else {
                    # Safety Fallback
                    if ($Ctrl.EdNoSelPanel) { $Ctrl.EdNoSelPanel.Visibility = "Visible" }
                }
            
                # --- BUTTON STATES (Restored & Refined V3) ---
                $hasSelection = ($null -ne $selectedItem)
                $type = if ($hasSelection) { $data.Type } else { "None" }
                
                $isFolder = ($type -eq "Folder")
                $isLink = ($type -eq "Link" -or $type -eq "InternalLink")
                $isPub = ($type -eq "Publication")
                $isFile = ($type -eq "File")
                $isMeta = ($type -eq "Tag" -or $type -eq "Permission") # Static or Dynamic Tag, and Permission

                # 1. ROOT BUTTONS (Creation of top-level items)
                # Strategy: Disable Roots when an item is selected to avoid confusion with child creation
                $rootEnabled = (-not $hasSelection)
                if ($Ctrl.EdBtnRoot) { $Ctrl.EdBtnRoot.IsEnabled = $rootEnabled }
                if ($Ctrl.EdBtnRootLink) { $Ctrl.EdBtnRootLink.IsEnabled = $rootEnabled }
            
                # 2. STRUCTURAL BUTTONS (Child creation)
                # Only folders can contain child folders/links/pubs/files
                $canAddChild = $isFolder
                if ($Ctrl.EdBtnChild) { $Ctrl.EdBtnChild.IsEnabled = $canAddChild }
                if ($Ctrl.EdBtnChildLink) { $Ctrl.EdBtnChildLink.IsEnabled = $canAddChild }
                if ($Ctrl.EdBtnChildInternalLink) { $Ctrl.EdBtnChildInternalLink.IsEnabled = $canAddChild }
                if ($Ctrl.EdBtnAddPub) { $Ctrl.EdBtnAddPub.IsEnabled = $canAddChild }
                if ($Ctrl.EdBtnAddFile) { $Ctrl.EdBtnAddFile.IsEnabled = $canAddChild }

                # 3. METADATA BUTTONS (Perms & Tags)
                # Enabled if selecting a container (Child mode) OR selecting a meta item (Sibling mode)
                $canAddMeta = ($isFolder -or $isPub -or $isLink -or $isFile -or $isMeta)
                
                if ($Ctrl.EdBtnGlobalAddPerm) { $Ctrl.EdBtnGlobalAddPerm.IsEnabled = ($isFolder -or $isPub -or $isFile -or $isMeta) }
                if ($Ctrl.EdBtnGlobalAddTag) { $Ctrl.EdBtnGlobalAddTag.IsEnabled = $canAddMeta }
                if ($Ctrl.EdBtnGlobalAddDynamicTag) { $Ctrl.EdBtnGlobalAddDynamicTag.IsEnabled = $canAddMeta }

                # 4. TRASH (Contextual Deletion)
                if ($Ctrl.EdBtnDel) { $Ctrl.EdBtnDel.IsEnabled = $hasSelection }

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
    if ($Ctrl.EdTagColumnBox) {
        $Ctrl.EdTagColumnBox.Add_SelectionChanged({
                if ($Script:IsPopulating) { return }
                $sel = $Ctrl.EdTree.SelectedItem
                $col = $this.SelectedItem
                if ($sel -and $sel.Tag.Type -eq "Tag" -and $col) {
                    $sel.Tag.Name = $col.Name
                    $tName = "$($col.Name) : $($sel.Tag.Value)"
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
    # 2b. DYNAMIC TAG HANDLERS (OLD - MOVED/CLEANED)
    
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
    if ($Ctrl.EdPubUseFormNameChk) {
        $Ctrl.EdPubUseFormNameChk.Add_Click({
                if ($Script:IsPopulating) { return }
                $sel = $Ctrl.EdTree.SelectedItem
                if ($sel -and $sel.Tag.Type -eq "Publication") { 
                    $isChecked = [bool]$Ctrl.EdPubUseFormNameChk.IsChecked
                    $sel.Tag.UseFormName = $isChecked 
                    
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
                $currentSchemaId = if ($Ctrl.EdTargetSchemaDisplay) { $Ctrl.EdTargetSchemaDisplay.Tag } else { "" }

                foreach ($r in $rules) {
                    try {
                        if (-not [string]::IsNullOrWhiteSpace($r.DefinitionJson)) {
                            $j = $r.DefinitionJson | ConvertFrom-Json
                            
                            # Filtrage par Schéma
                            if ($currentSchemaId -and $j.TargetSchemaId -ne $currentSchemaId) {
                                continue
                            }
                            
                            if ($j.PSObject.Properties['Layout']) {
                                $hasMeta = @($j.Layout) | Where-Object { $_.IsMetadata -eq $true } | Select-Object -First 1
                                if ($hasMeta) { 
                                    # FIX: Create clean object for WPF Binding
                                    $displayName = if (-not [string]::IsNullOrWhiteSpace($r.DisplayName)) { $r.DisplayName } elseif ($j.PSObject.Properties['FormName'] -and $j.FormName) { $j.FormName } else { $r.RuleId }
                                    $description = if (-not [string]::IsNullOrWhiteSpace($r.Description)) { $r.Description } else { $j.Description }
                                    
                                    $filteredRules.Add([PSCustomObject]@{
                                            RuleId         = $r.RuleId
                                            DisplayName    = $displayName
                                            Description    = $description
                                            DefinitionJson = $r.DefinitionJson
                                        })
                                }
                            }
                        }
                    }
                    catch {
                        Write-Warning "[DynamicTag] Parsing failed for Rule $($r.RuleId): $($_.Exception.Message)"
                    }
                }
                Write-Warning "[DynamicTag] Filtered result: $($filteredRules.Count) rules retained."

                if ($this) {
                    $this.DisplayMemberPath = "DisplayName"
                    $this.ItemsSource = $filteredRules
                }
            }.GetNewClosure())
    }

    # INFO BUTTON (Show Description)
    if ($Ctrl.EdDynamicTagInfoButton) {
        $Ctrl.EdDynamicTagInfoButton.Add_Click({
                $rule = $Ctrl.EdDynamicTagSourceFormBox.SelectedItem
                if ($rule) {
                    $msg = if ($rule.Description) { $rule.Description } else { "Aucune description disponible." }
                    [System.Windows.MessageBox]::Show($msg, "Description du Formulaire ($($rule.DisplayName))", "OK", "Information")
                }
                else {
                    [System.Windows.MessageBox]::Show("Veuillez sélectionner un formulaire d'abord.", "Info", "OK", "Information")
                }
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

    # --- SUPPRESSION DOSSIER ---
    if ($Ctrl.EdFolderDeleteButton) {
        $Ctrl.EdFolderDeleteButton.Add_Click({
                $sel = $Ctrl.EdTree.SelectedItem
                if ($sel -and $sel.Tag.Type -eq "Folder") {
                    if ([System.Windows.MessageBox]::Show("Supprimer ce dossier ?", "Confirmation", "YesNo", "Question") -ne 'Yes') { return }
                    $p = $sel.Parent
                    if ($p -is [System.Windows.Controls.TreeViewItem]) { $p.Items.Remove($sel) }
                    elseif ($Ctrl.EdTree.Items.Contains($sel)) { $Ctrl.EdTree.Items.Remove($sel) }
                    
                    if ($Ctrl.EdPropPanel) { $Ctrl.EdPropPanel.Visibility = "Collapsed" }
                    if ($Ctrl.EdNoSelPanel) { $Ctrl.EdNoSelPanel.Visibility = "Visible" }
                }
            }.GetNewClosure())
    }

    # --- SUPPRESSION PUBLICATION ---
    if ($Ctrl.EdPubDeleteButton) {
        $Ctrl.EdPubDeleteButton.Add_Click({
                $sel = $Ctrl.EdTree.SelectedItem
                if ($sel -and $sel.Tag.Type -eq "Publication") {
                    $parent = $sel.Parent
                    if ($parent -is [System.Windows.Controls.TreeViewItem]) { $parent.Items.Remove($sel) }
                    
                    if ($Ctrl.EdPropPanelPub) { $Ctrl.EdPropPanelPub.Visibility = "Collapsed" }
                    if ($Ctrl.EdNoSelPanel) { $Ctrl.EdNoSelPanel.Visibility = "Visible" }
                }
            }.GetNewClosure())
    }

    # --- SUPPRESSION LIEN INTERNE ---
    if ($Ctrl.EdInternalLinkDeleteButton) {
        $Ctrl.EdInternalLinkDeleteButton.Add_Click({
                $sel = $Ctrl.EdTree.SelectedItem
                if ($sel -and $sel.Tag.Type -eq "InternalLink") {
                    $p = $sel.Parent
                    if ($p -is [System.Windows.Controls.TreeViewItem]) { $p.Items.Remove($sel) }
                    elseif ($Ctrl.EdTree.Items.Contains($sel)) { $Ctrl.EdTree.Items.Remove($sel) }
                    
                    if ($Ctrl.EdPropPanelInternalLink) { $Ctrl.EdPropPanelInternalLink.Visibility = "Collapsed" }
                    if ($Ctrl.EdNoSelPanel) { $Ctrl.EdNoSelPanel.Visibility = "Visible" }
                }
            }.GetNewClosure())
    }

    # --- SUPPRESSION LIEN EXTERNE ---
    if ($Ctrl.EdLinkDeleteButton) {
        $Ctrl.EdLinkDeleteButton.Add_Click({
                $sel = $Ctrl.EdTree.SelectedItem
                if ($sel -and $sel.Tag.Type -eq "Link") {
                    $parent = $sel.Parent
                    if ($parent -is [System.Windows.Controls.TreeViewItem]) { $parent.Items.Remove($sel) }
                    else { $Ctrl.EdTree.Items.Remove($sel) }
                    
                    if ($Ctrl.EdPropPanelLink) { $Ctrl.EdPropPanelLink.Visibility = "Collapsed" }
                    if ($Ctrl.EdNoSelPanel) { $Ctrl.EdNoSelPanel.Visibility = "Visible" }
                }
            }.GetNewClosure())
    }

    # --- SUPPRESSION FICHIER ---
    if ($Ctrl.EdFileDeleteButton) {
        $Ctrl.EdFileDeleteButton.Add_Click({
                $sel = $Ctrl.EdTree.SelectedItem
                if ($sel -and $sel.Tag.Type -eq "File") {
                    $parent = $sel.Parent
                    if ($parent -is [System.Windows.Controls.TreeViewItem]) { $parent.Items.Remove($sel) }
                    
                    if ($Ctrl.EdPanelFile) { $Ctrl.EdPanelFile.Visibility = "Collapsed" }
                    if ($Ctrl.EdNoSelPanel) { $Ctrl.EdNoSelPanel.Visibility = "Visible" }
                }
            }.GetNewClosure())
    }
    
    # --- FETCH FILE INFO ---
    if ($Ctrl.EdFileFetchInfoButton) {
        $Ctrl.EdFileFetchInfoButton.Add_Click({
                $url = $Ctrl.EdFileUrlBox.Text
                if (-not [string]::IsNullOrWhiteSpace($url)) {
                    try {
                        $uri = [System.Uri]$url
                        $fileName = [System.IO.Path]::GetFileName($uri.LocalPath)
                        if (-not [string]::IsNullOrWhiteSpace($fileName)) {
                            $Ctrl.EdFileNameBox.Text = $fileName
                            # Trigger update in tree
                            $sel = $Ctrl.EdTree.SelectedItem
                            if ($sel -and $sel.Tag -and $sel.Tag.Type -eq "File") {
                                $sel.Tag.Name = $fileName
                                if ($sel.Header -is [System.Windows.Controls.StackPanel] -and $sel.Header.Children.Count -ge 2) {
                                    $sel.Header.Children[1].Text = $fileName
                                }
                            }
                        }
                    }
                    catch {
                        [System.Windows.MessageBox]::Show("URL invalide ou impossible d'extraire le nom.", "Erreur", "OK", "Error")
                    }
                }
            }.GetNewClosure())
    }
}
