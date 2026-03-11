# Scripts/SharePoint/SharePointBuilder/Functions/Logic/Editor/Register-EditorHelpers.ps1

<#
.SYNOPSIS
    Fonctions utilitaires pour le rendu visuel et le tri de l'éditeur.
#>

# --- TRI ARBORESCENCE ---
function Global:Sort-EditorTreeRecursive {
    param(
        $ItemCollection,
        [int]$Level = 0
    )
    if ($null -eq $ItemCollection -or $ItemCollection.Count -eq 0) { return }

    $items = @($ItemCollection)
    $ItemCollection.Clear()

    # ROOT LEVEL (Level 0): Folders Top, Root Links Bottom
    # CHILD LEVEL (Level > 0): Meta Top, Content Middle, SubFolders Bottom
    
    $sortedItems = $items | Sort-Object `
    @{Expression     = { 
            $t = if ($_.Tag.Type) { $_.Tag.Type } else { "Folder" }
            
            if ($Level -eq 0) {
                # ROOT
                if ($t -eq "Folder") { 10 }
                else { 90 } # Root Links at Bottom
            }
            else {
                # CHILDREN
                if ($t -eq "Permission") { 10 }
                elseif ($t -eq "Tag") { if ($_.Tag.IsDynamic) { 21 } else { 20 } }
                elseif ($t -eq "Link" -or $t -eq "InternalLink") { 30 }
                elseif ($t -eq "Publication") { 40 }
                elseif ($t -eq "Folder") { 50 } # SubFolders at Bottom
                elseif ($t -eq "File") { 110 } # Files at very bottom
                else { 100 }
            }
        }; Ascending = $true
    }, 
    @{Expression = { $_.Tag.Name }; Ascending = $true }
        
    foreach ($item in $sortedItems) {
        $ItemCollection.Add($item) | Out-Null
        if ($item -is [System.Windows.Controls.TreeViewItem]) {
            # Recurse with Level + 1
            Sort-EditorTreeRecursive -ItemCollection $item.Items -Level ($Level + 1)
        }
    }
}


# --- HELPER DE MISE À JOUR VISUELLE ENFANT (SYNC UI) ---
function Global:Update-EditorChildNode {
    param($ParentItem, $DataObject)
    
    if (-not $ParentItem -or -not $ParentItem.Items) { return }
    
    # Chercher l'enfant qui porte ce DataObject (Tag)
    foreach ($child in $ParentItem.Items) {
        if ($child.Tag -eq $DataObject) {
            # C'est lui ! Mise à jour du Header
           
            # Cas Permission
            if ($DataObject.PSObject.Properties['Email'] -or $DataObject.PSObject.Properties['Identity']) {
                $id = if ($DataObject.PSObject.Properties['Identity']) { $DataObject.Identity } else { $DataObject.Email }
                $lvl = if ($DataObject.PSObject.Properties['Level']) { $DataObject.Level } else { "" }
                $txt = "$id ($lvl)"
                if ($child.Header -is [System.Windows.Controls.StackPanel]) { $child.Header.Children[1].Text = $txt }
            }
            # Cas Tag
            elseif ($DataObject.PSObject.Properties['Name'] -or $DataObject.PSObject.Properties['Value']) {
                $n = if ($DataObject.PSObject.Properties['Name']) { $DataObject.Name } else { "" }
                $v = if ($DataObject.PSObject.Properties['Value']) { $DataObject.Value } else { "" }
                $txt = "$n : $v"
                if ($child.Header -is [System.Windows.Controls.StackPanel]) { $child.Header.Children[1].Text = $txt }
            }
            break
        }
    }
}

# --- RENDU LIGNES PERMISSIONS ---
function Global:New-EditorPermissionRow {
    param(
        $PermData, 
        $ParentList, 
        $CurrentTreeItem, 
        [System.Windows.Window]$Window
    )
    if ($null -eq $ParentList) { return }
    
    $row = New-Object System.Windows.Controls.Grid; $row.Margin = "0,0,0,5"
    $row.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{Width = "*" }))
    $row.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{Width = "120" }))
    $row.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{Width = "Auto" }))
    
    $t1 = New-Object System.Windows.Controls.TextBox -Property @{Text = $PermData.Email; Style = $Window.FindResource("StandardTextBoxStyle"); Margin = "0,0,5,0" }
    $t1.Add_TextChanged({ 
            $PermData.Email = $this.Text 
            Update-EditorChildNode -ParentItem $CurrentTreeItem -DataObject $PermData
        }.GetNewClosure())

    $c1 = New-Object System.Windows.Controls.ComboBox -Property @{ItemsSource = @("Read", "Contribute", "Full Control"); SelectedItem = $PermData.Level; Style = $Window.FindResource("StandardComboBoxStyle"); Margin = "0,0,5,0"; Height = 34 }
    $c1.Add_SelectionChanged({ 
            if ($this.SelectedItem) { 
                $PermData.Level = $this.SelectedItem 
                Update-EditorChildNode -ParentItem $CurrentTreeItem -DataObject $PermData
            } 
        }.GetNewClosure())
    
    # SUPPRESSION
    $b1 = New-Object System.Windows.Controls.Button -Property @{Content = "🗑️"; Style = $Window.FindResource("IconButtonStyle"); Width = 34; Height = 34; Foreground = $Window.FindResource("DangerBrush") }
    $b1.Add_Click({ 
            # Capture explicite du TreeItem passé en paramètre
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

# --- RENDU LIGNES TAGS ---
function Global:New-EditorTagRow {
    param(
        $TagData, 
        $ParentList, 
        $CurrentTreeItem,
        [System.Windows.Window]$Window
    )
    if ($null -eq $ParentList) { return }
    
    $row = New-Object System.Windows.Controls.Grid; $row.Margin = "0,0,0,5"
    $row.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{Width = "*" }))
    $row.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{Width = "*" }))
    $row.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{Width = "Auto" }))
    
    
    $t1 = New-Object System.Windows.Controls.TextBox -Property @{Text = $TagData.Name; Style = $Window.FindResource("StandardTextBoxStyle"); Margin = "0,0,5,0" }
    $t1.Add_TextChanged({ 
            $TagData.Name = $this.Text 
            Update-EditorChildNode -ParentItem $CurrentTreeItem -DataObject $TagData
        }.GetNewClosure())

    $t2 = New-Object System.Windows.Controls.TextBox -Property @{Text = $TagData.Value; Style = $Window.FindResource("StandardTextBoxStyle"); Margin = "0,0,5,0" }
    $t2.Add_TextChanged({ 
            $TagData.Value = $this.Text 
            Update-EditorChildNode -ParentItem $CurrentTreeItem -DataObject $TagData
        }.GetNewClosure())
    
    # SUPPRESSION
    $b1 = New-Object System.Windows.Controls.Button -Property @{Content = "🗑️"; Style = $Window.FindResource("IconButtonStyle"); Width = 34; Height = 34; Foreground = $Window.FindResource("DangerBrush") }
    $b1.Add_Click({ 
            $sel = $CurrentTreeItem 
        
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


# --- CALCUL DU CHEMIN RELATIF (DYNAMIQUE) ---
function Global:Get-EditorItemPath {
    param($TreeItem)
    if (-not $TreeItem -or $TreeItem -isnot [System.Windows.Controls.TreeViewItem]) { return "" }
    
    $name = if ($TreeItem.Tag.Name) { $TreeItem.Tag.Name } else { "" }
    $parent = $TreeItem.Parent
    
    if ($parent -is [System.Windows.Controls.TreeViewItem]) {
        $parentPath = Get-EditorItemPath -TreeItem $parent
        
        # Cas spécifique Publication avec métadonnées : on injecte {formDestination}
        if ($TreeItem.Tag.Type -eq "Publication" -and $TreeItem.Tag.UseFormMetadata) {
            $p = if ($parentPath -eq "/") { "/{formDestination}/$name" } else { "$parentPath/{formDestination}/$name" }
        }
        else {
            $p = if ($parentPath -eq "/") { "/$name" } else { "$parentPath/$name" }
        }
    }
    else {
        # Racine du TreeView
        if ($TreeItem.Tag.Type -eq "Publication" -and $TreeItem.Tag.UseFormMetadata) {
            $p = "/{formDestination}/$name"
        }
        else {
            $p = "/$name"
        }
    }

    # Suffixe .url pour les types de fichiers/liens
    if ($TreeItem.Tag.Type -match "Link|Publication" -and $p -notmatch "\.url$") {
        $p += ".url"
    }
    return $p
}

# --- RECHERCHE DE NOEUD PAR ID ---
function Global:Find-EditorNodeById {
    param(
        $Collection,
        [string]$Id
    )
    if ($null -eq $Collection) { return $null }
    foreach ($item in $Collection) {
        if ($item.Tag -and $item.Tag.Id -eq $Id) { return $item }
        $found = Find-EditorNodeById -Collection $item.Items -Id $Id
        if ($found) { return $found }
    }
    return $null
}

# --- MISE À JOUR VISUELLE DU LIEN INTERNE ---
function Global:Update-EditorInternalLinkDisplay {
    param(
        $LinkItem,
        [hashtable]$Ctrl = $null
    )
    if (-not $LinkItem -or $LinkItem.Tag.Type -ne "InternalLink") { return }

    # Utiliser le $Ctrl fourni ou fallback sur le global
    $effectiveCtrl = if ($Ctrl) { $Ctrl } else { $Global:AppControls }
    if (-not $effectiveCtrl -or -not $effectiveCtrl.EdTree) { return }

    $targetId = $LinkItem.Tag.TargetNodeId
    $targetNode = Find-EditorNodeById -Collection $effectiveCtrl.EdTree.Items -Id $targetId
    
    $targetPath = if ($targetNode) { Get-EditorItemPath -TreeItem $targetNode } else { "(Cible inconnue)" }
    $displayText = "$($LinkItem.Tag.Name) -> $targetPath"

    # Mise à jour du header (StackPanel: Icon(0), Badge(1), Text(2))
    if ($LinkItem.Header -is [System.Windows.Controls.StackPanel] -and $LinkItem.Header.Children.Count -ge 3) {
        $LinkItem.Header.Children[2].Text = $displayText
    }
    
    return $targetPath
}

# --- MISE À JOUR VISUELLE DE LA PUBLICATION ---
function Global:Update-EditorPublicationDisplay {
    param(
        $PubItem,
        [hashtable]$Ctrl = $null
    )
    if (-not $PubItem -or $PubItem.Tag.Type -ne "Publication") { return }

    $data = $PubItem.Tag
    $sitePrefix = if ($data.TargetSiteMode -eq "Url" -and $data.TargetSiteUrl) { "[$($data.TargetSiteUrl)]" } else { "[Site Courant]" }
    
    $targetPath = if ($data.TargetFolderPath) { "/" + $data.TargetFolderPath.Trim("/") } else { "" }
    
    if ($data.UseFormMetadata) {
        $targetPath += "/{formDestination}"
    }
    
    if ($data.UseFormName) {
        $targetPath += "/$($data.Name)"
    }
    
    if ($targetPath -eq "") { $targetPath = "/" }
    
    $fullPath = "$sitePrefix $targetPath"
    $tName = $data.Name
    if ($data.UseFormMetadata) { $tName += " [META]" }
    $displayText = "$tName -> $fullPath"

    # Mise à jour du header (StackPanel: Icon(0), Text(1))
    if ($PubItem.Header -is [System.Windows.Controls.StackPanel] -and $PubItem.Header.Children.Count -ge 2) {
        $txtBlock = $PubItem.Header.Children[1]
        if ($txtBlock) { $txtBlock.Text = $displayText }
    }
    
    return $fullPath
}
