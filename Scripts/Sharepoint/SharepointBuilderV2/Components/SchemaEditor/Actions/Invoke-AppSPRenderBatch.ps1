# Scripts/Sharepoint/SharepointBuilderV2/Functions/Logic/Invoke-AppSPRenderBatch.ps1

<#
.SYNOPSIS
    Rendu graphique par lots (Pagination) pour l'explorateur SharePoint.
.DESCRIPTION
    Prend un ParentNode (TreeViewItem), vérifie ses données en cache, et génère le lot d'items suivant.
    Gère également l'ajout/suppression du bouton "Load More".
#>
function Global:Invoke-AppSPRenderBatch {
    param(
        [System.Windows.Controls.TreeViewItem]$ParentNode,
        [hashtable]$Ctrl
    )
    
    $v = "v4.17"
    Write-Verbose "[$v] Rendu par lot pour : $($ParentNode.Header)"
    
    try {
        $tag = $ParentNode.Tag
        if ($null -eq $tag) { return }
        
        # Vérification du cache
        if (-not $tag.CachedChildren) {
            Write-AppLog -Message "Erreur Pagination : Cache manquant pour $($ParentNode.Header)" -Level Warning -RichTextBox $Ctrl.LogBox
            return 
        }

        $children = $tag.CachedChildren
        $count = $children.Count
        $offset = if ($tag.RenderedCount -is [int]) { $tag.RenderedCount } else { 0 }
        $pageSize = 10
        
        # Calculer la fin du lot
        $endIndex = [Math]::Min($offset + $pageSize, $count)
        $parentName = if ($tag.Name) { $tag.Name } else { "Racine" }
        
        Write-AppLog -Message "Pagination ($parentName) [$v] : items $offset à $endIndex sur $count" -Level Info -RichTextBox $Ctrl.LogBox

        # 1. Retirer le bouton "Load More" s'il existe
        $toRemove = $null
        foreach ($it in $ParentNode.Items) {
            if ($it.Tag -eq "ACTION_LOAD_MORE") { $toRemove = $it; break }
        }
        if ($toRemove) { $ParentNode.Items.Remove($toRemove) }

        # 2. Rendu des items
        for ($i = $offset; $i -lt $endIndex; $i++) {
            $folder = $children[$i]
            if ($folder.Name -eq "Forms") { continue }

            $newItem = New-Object System.Windows.Controls.TreeViewItem
            $newItem.SetResourceReference([System.Windows.Controls.TreeViewItem]::StyleProperty, "ModernTreeViewItemStyle")
            
            $stack = New-Object System.Windows.Controls.StackPanel
            $stack.Orientation = "Horizontal"
            $txtIcon = New-Object System.Windows.Controls.TextBlock
            $txtIcon.Text = "📁"
            $txtIcon.SetResourceReference([System.Windows.Controls.TextBlock]::StyleProperty, "TreeItemIconStyle") 
            $stack.Children.Add($txtIcon)
            $txt = New-Object System.Windows.Controls.TextBlock
            $txt.Text = $folder.Name
            $stack.Children.Add($txt)
            $newItem.Header = $stack
            
            # Tag enrichi (Essentiel pour récursion)
            $parentPath = if ($tag.FullPath) { $tag.FullPath } else { "" }
            $currentFullPath = "$($parentPath)/$($folder.Name)".Replace("//", "/")
            $newItem.Tag = [PSCustomObject]@{
                Name              = $folder.Name
                DriveId           = $tag.DriveId
                ItemId            = $folder.id
                SiteId            = $tag.SiteId
                FullPath          = $currentFullPath
                ServerRelativeUrl = if ($folder.webUrl) { [System.Uri]::new($folder.webUrl).AbsolutePath.Replace("%20", " ") } else { "" }
            }
            
            # Ajout d'un dummy pour permettre l'expansion
            $dummy = New-Object System.Windows.Controls.TreeViewItem
            $dummy.Header = "Chargement..."
            $dummy.Tag = "DUMMY_TAG"
            $newItem.Items.Add($dummy) | Out-Null
            $ParentNode.Items.Add($newItem) | Out-Null
        }

        # 3. Mise à jour Offset
        $tag.RenderedCount = $endIndex

        # 4. Ajouter "Load More" si reste
        if ($endIndex -lt $count) {
            $remaining = $count - $endIndex
            $moreItem = New-Object System.Windows.Controls.TreeViewItem
            $moreItem.Header = "Charger la suite (+ $remaining) ..."
            $moreItem.Tag = "ACTION_LOAD_MORE"
            
            $style = New-Object System.Windows.Style -ArgumentList ([System.Windows.Controls.TreeViewItem])
            $style.Setters.Add((New-Object System.Windows.Setter -ArgumentList @([System.Windows.Controls.Control]::ForegroundProperty, [System.Windows.Media.Brushes]::DodgerBlue)))
            $style.Setters.Add((New-Object System.Windows.Setter -ArgumentList @([System.Windows.Controls.Control]::FontWeightProperty, [System.Windows.FontWeights]::SemiBold)))
            $style.Setters.Add((New-Object System.Windows.Setter -ArgumentList @([System.Windows.Controls.Control]::CursorProperty, [System.Windows.Input.Cursors]::Hand)))
            $trigger = New-Object System.Windows.Trigger
            $trigger.Property = [System.Windows.Controls.TreeViewItem]::IsSelectedProperty
            $trigger.Value = $true
            $trigger.Setters.Add((New-Object System.Windows.Setter -ArgumentList @([System.Windows.Controls.Control]::ForegroundProperty, [System.Windows.Media.Brushes]::White)))
            $style.Triggers.Add($trigger)
            $moreItem.Style = $style
            $ParentNode.Items.Add($moreItem) | Out-Null
        }
    } catch { 
        Write-Warning "[$v] Échec rendu par lot : $_" 
    }
}
