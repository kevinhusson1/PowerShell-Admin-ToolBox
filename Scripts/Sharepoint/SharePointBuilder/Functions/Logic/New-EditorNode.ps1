# Scripts/SharePoint/SharePointBuilder/Functions/Logic/New-EditorNode.ps1

<#
.SYNOPSIS
    Crée un nouvel élément visuel (Node) pour l'arbre d'édition.

.DESCRIPTION
    Génère un TreeViewItem stylisé contenant un dossier, un libellé, et des badges invisibles par défaut.
    Initialise également l'objet Tag avec des listes vides pour les Permissions, Tags et Liens.

.PARAMETER Name
    Le nom par défaut du dossier.

.OUTPUTS
    [TreeViewItem] L'élément prêt à être ajouté au TreeView.
#>
function Global:New-EditorNode {
    param(
        [string]$Name = "Nouveau dossier"
    )

    $item = New-Object System.Windows.Controls.TreeViewItem
    $item.SetResourceReference([System.Windows.Controls.TreeViewItem]::StyleProperty, "ModernTreeViewItemStyle")
    # Note : Le Style "ModernTreeViewItemStyle" est désormais appliqué via le Style Implicite XAML
    
    # Conteneur Horizontal
    $stack = New-Object System.Windows.Controls.StackPanel -Property @{ Orientation = "Horizontal" }
    
    # 1. Icône Dossier
    $icon = New-Object System.Windows.Controls.TextBlock
    $icon.Text = "📁"
    
    # Style Icône
    $styleFound = $false
    if ($app) {
        $s = $app.TryFindResource("TreeItemIconStyle")
        if ($s) { $icon.Style = $s; $styleFound = $true }
    }
    if (-not $styleFound) {
        $icon.SetResourceReference([System.Windows.Controls.TextBlock]::StyleProperty, "TreeItemIconStyle")
    }
    
    # 2. Nom du Dossier
    $text = New-Object System.Windows.Controls.TextBlock -Property @{ Text = $Name; VerticalAlignment = "Center"; Margin = "0,0,10,0" }
    
    # 3. Badge Permissions (Violet)
    $bdgPerm = New-Object System.Windows.Controls.Border -Property @{ Background = "#E0E7FF"; CornerRadius = 4; Padding = "6,1"; Margin = "0,0,5,0"; Visibility = "Collapsed" }
    $bdgPerm.Child = New-Object System.Windows.Controls.TextBlock -Property @{ Text = "👤"; FontSize = 10; Foreground = "#4F46E5"; FontWeight = "SemiBold" }

    # 4. Badge Tags (Cyan)
    $bdgTag = New-Object System.Windows.Controls.Border -Property @{ Background = "#E0F2FE"; CornerRadius = 4; Padding = "6,1"; Margin = "0,0,5,0"; Visibility = "Collapsed" }
    $bdgTag.Child = New-Object System.Windows.Controls.TextBlock -Property @{ Text = "🏷️"; FontSize = 10; Foreground = "#0284C7"; FontWeight = "SemiBold" }

    # 5. Badge Liens (Orange) - NOUVEAU
    $bdgLink = New-Object System.Windows.Controls.Border -Property @{ Background = "#FEF3C7"; CornerRadius = 4; Padding = "6,1"; Visibility = "Collapsed" }
    $bdgLink.Child = New-Object System.Windows.Controls.TextBlock -Property @{ Text = "🔗"; FontSize = 10; Foreground = "#D97706"; FontWeight = "SemiBold" }

    # Assemblage
    $stack.Children.Add($icon) | Out-Null
    $stack.Children.Add($text) | Out-Null
    $stack.Children.Add($bdgPerm) | Out-Null
    $stack.Children.Add($bdgTag) | Out-Null
    $stack.Children.Add($bdgLink) | Out-Null # Ajout
    
    $item.Header = $stack
    $item.IsExpanded = $true

    # Données
    $dataObject = [PSCustomObject]@{
        Name        = $Name
        Permissions = [System.Collections.Generic.List[psobject]]::new()
        Tags        = [System.Collections.Generic.List[psobject]]::new()
        Links       = [System.Collections.Generic.List[psobject]]::new()
    }
    $item.Tag = $dataObject

    return $item
}

<#
.SYNOPSIS
    Met à jour les indicateurs visuels (Badges) d'un noeud.

.DESCRIPTION
    Analyse les métadonnées (Permissions, Tags, Links) stockées dans la propriété Tag de l'item,
    et met à jour les icônes et compteurs affichés à côté du nom du dossier.
    Gère également le rafraîchissement des sous-éléments de métadonnées dans l'arbre.

.PARAMETER TreeItem
    Le TreeViewItem à mettre à jour.
#>
function Global:Update-EditorBadges {
    param([System.Windows.Controls.TreeViewItem]$TreeItem)

    if (-not $TreeItem -or -not $TreeItem.Tag) { 
        # Write-Host "⚠️ Update-EditorBadges: TreeItem ou Tag NULL" -ForegroundColor Red
        return 
    }
    
    $data = $TreeItem.Tag
    $header = $TreeItem.Header
    
    if ($header -isnot [System.Windows.Controls.StackPanel]) { 
        # Write-Host "⚠️ Update-EditorBadges: Header n'est pas un StackPanel" -ForegroundColor Red
        return 
    }

    # Write-Host "🔄 Update-EditorBadges pour: $($data.Name)" -ForegroundColor Cyan

    # Compter les éléments
    $cntP = if ($data.Permissions) { $data.Permissions.Count } else { 0 }
    $cntT = if ($data.Tags) { $data.Tags.Count } else { 0 }
    $cntL = if ($data.Links) { $data.Links.Count } else { 0 }
    
    # Write-Host "  ↳ Permissions: $cntP | Tags: $cntT | Links: $cntL" -ForegroundColor Magenta

    # ⭐ MÉTHODE ROBUSTE : Supprimer tous les badges existants (indices 2+)
    $toRemove = @()
    for ($i = $header.Children.Count - 1; $i -ge 2; $i--) {
        $toRemove += $header.Children[$i]
    }
    foreach ($item in $toRemove) {
        $header.Children.Remove($item)
    }
    # Write-Host "  ↳ $($toRemove.Count) badges supprimés" -ForegroundColor Yellow

    # ⭐ RECRÉER les badges (comme dans New-EditorNode)
    
    # Badge Permissions
    if ($cntP -gt 0) {
        $bdgPerm = New-Object System.Windows.Controls.Border -Property @{
            Background        = "#E3F2FD"
            CornerRadius      = 3
            Padding           = "4,2"
            Margin            = "5,0,0,0"
            VerticalAlignment = "Center"
        }
        $txtPerm = New-Object System.Windows.Controls.TextBlock -Property @{
            Text       = "👤 $cntP"
            FontSize   = 10
            Foreground = "#1976D2"
        }
        $bdgPerm.Child = $txtPerm
        $header.Children.Add($bdgPerm) | Out-Null
        # Write-Host "  ↳ Badge Permission créé: 👤 $cntP" -ForegroundColor Green
    }
    
    # Badge Tags
    if ($cntT -gt 0) {
        $bdgTag = New-Object System.Windows.Controls.Border -Property @{
            Background        = "#F1F8E9"
            CornerRadius      = 3
            Padding           = "4,2"
            Margin            = "5,0,0,0"
            VerticalAlignment = "Center"
        }
        $txtTag = New-Object System.Windows.Controls.TextBlock -Property @{
            Text       = "🏷️ $cntT"
            FontSize   = 10
            Foreground = "#689F38"
        }
        $bdgTag.Child = $txtTag
        $header.Children.Add($bdgTag) | Out-Null
        # Write-Host "  ↳ Badge Tag créé: 🏷️ $cntT" -ForegroundColor Green
    }
    
    # Badge Links
    if ($cntL -gt 0) {
        $bdgLink = New-Object System.Windows.Controls.Border -Property @{
            Background        = "#FFF3E0"
            CornerRadius      = 3
            Padding           = "4,2"
            Margin            = "5,0,0,0"
            VerticalAlignment = "Center"
        }
        $txtLink = New-Object System.Windows.Controls.TextBlock -Property @{
            Text       = "🔗 $cntL"
            FontSize   = 10
            Foreground = "#F57C00"
        }
        $bdgLink.Child = $txtLink
        $header.Children.Add($bdgLink) | Out-Null
        # Write-Host "  ↳ Badge Link créé: 🔗 $cntL" -ForegroundColor Green
    }
    
    # Write-Host "  ✅ Badges reconstruits avec succès!" -ForegroundColor Green
    
    # ==========================================================================
    # GESTION DES SOUS-ÉLÉMENTS (Metadata : Permissions, Tags, Links)
    # ==========================================================================
    
    # 1. Nettoyage des anciens items metadata (identifiés par Name="MetaItem")
    $metaItems = @()
    foreach ($child in $TreeItem.Items) {
        if ($child.Name -eq "MetaItem") { $metaItems += $child }
    }
    foreach ($m in $metaItems) { $TreeItem.Items.Remove($m) }

    # Helper pour la création d'items
    $fnAddMeta = {
        param($StyleKey, $Text, $Data, $Italic = $false)
        $mItem = New-Object System.Windows.Controls.TreeViewItem
        $mItem.SetResourceReference([System.Windows.Controls.TreeViewItem]::StyleProperty, "ModernTreeViewItemStyle")
        $mItem.Name = "MetaItem"
        $mItem.Tag = $Data
        
        # Note : Le Style "ModernTreeViewItemStyle" est désormais appliqué via le Style Implicite XAML
        
        $mStack = New-Object System.Windows.Controls.StackPanel -Property @{ Orientation = "Horizontal" }
        
        # Icône typée via Style
        $mIcon = New-Object System.Windows.Controls.TextBlock 
        
        $styleFound = $false
        if ($app) {
            $s = $app.TryFindResource($StyleKey)
            if ($s) { $mIcon.Style = $s; $styleFound = $true }
        }
        if (-not $styleFound) {
            $mIcon.SetResourceReference([System.Windows.Controls.TextBlock]::StyleProperty, $StyleKey)
        }

        $mText = New-Object System.Windows.Controls.TextBlock -Property @{ Text = $Text; FontSize = 11; VerticalAlignment = "Center" }
        if ($Italic) { $mText.FontStyle = "Italic" }
        
        $mStack.Children.Add($mIcon) | Out-Null
        $mStack.Children.Add($mText) | Out-Null
        $mItem.Header = $mStack
        
        return $mItem
    }

    $idx = 0

    # 2. Permissions
    if ($data.Permissions) {
        foreach ($p in $data.Permissions) {
            $pName = ""
            if ($p.PSObject.Properties['Identity']) { $pName = "$($p.Identity) ($($p.Level))" }
            elseif ($p.PSObject.Properties['User']) { $pName = "$($p.User) ($($p.Level))" }
            elseif ($p.PSObject.Properties['Email']) { $pName = "$($p.Email) ($($p.Level))" }
            else { $pName = [string]$p } # Fallback

            $newItem = & $fnAddMeta -StyleKey "PermIconStyle" -Text $pName -Data $p
            $TreeItem.Items.Insert($idx, $newItem)
            $idx++
        }
    }

    # 3. Tags
    if ($data.Tags) {
        foreach ($t in $data.Tags) {
            $tName = ""
            if ($t.PSObject.Properties['Name'] -and $t.PSObject.Properties['Value']) { $tName = "$($t.Name) : $($t.Value)" }
            elseif ($t.PSObject.Properties['Column'] -and $t.PSObject.Properties['Term']) { $tName = "$($t.Column) : $($t.Term)" }
            else { $tName = [string]$t }

            $newItem = & $fnAddMeta -StyleKey "TagIconStyle" -Text $tName -Data $t
            $TreeItem.Items.Insert($idx, $newItem)
            $idx++
        }
    }

    # 4. Liens
    if ($data.Links) {
        foreach ($l in $data.Links) {
            $lName = if ($l.PSObject.Properties['Name']) { $l.Name } else { $l.Url }
            $newItem = & $fnAddMeta -StyleKey "LinkIconStyle" -Text $lName -Data $l -Italic $true

            $TreeItem.Items.Insert($idx, $newItem)
            $idx++
        }
    }

    # ⭐ Force le refresh visuel
    try {
        $header.InvalidateVisual()
        $TreeItem.InvalidateVisual()
        $header.UpdateLayout()
        $TreeItem.UpdateLayout()
    }
    catch { }
}