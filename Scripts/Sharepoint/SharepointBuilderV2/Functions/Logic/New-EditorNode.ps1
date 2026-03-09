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
    # Style Icône
    $icon.SetResourceReference([System.Windows.Controls.TextBlock]::StyleProperty, "TreeItemIconStyle")
    
    # 2. Nom du Dossier
    $text = New-Object System.Windows.Controls.TextBlock -Property @{ Text = $Name; VerticalAlignment = "Center"; Margin = "0,0,10,0" }
    
    # 3. Badge Permissions (Violet)
    $bdgPerm = New-Object System.Windows.Controls.Border -Property @{ Background = "#E0E7FF"; CornerRadius = 4; Padding = "6,1"; Margin = "0,0,5,0"; Visibility = "Collapsed" }
    $bdgPerm.Child = New-Object System.Windows.Controls.TextBlock -Property @{ Text = "👤"; FontSize = 10; Foreground = "#4F46E5"; FontWeight = "SemiBold" }

    # 4. Badge Tags (Cyan)
    $bdgTag = New-Object System.Windows.Controls.Border -Property @{ Background = "#E0F2FE"; CornerRadius = 4; Padding = "6,1"; Margin = "0,0,5,0"; Visibility = "Collapsed" }
    $bdgTag.Child = New-Object System.Windows.Controls.TextBlock -Property @{ Text = "🏷️"; FontSize = 10; Foreground = "#0284C7"; FontWeight = "SemiBold" }

    # Assemblage
    $stack.Children.Add($icon) | Out-Null
    $stack.Children.Add($text) | Out-Null
    $stack.Children.Add($bdgPerm) | Out-Null
    $stack.Children.Add($bdgTag) | Out-Null
    # $stack.Children.Add($bdgLink) | Out-Null # REMOVED: Liens sont des noeuds
    
    $item.Header = $stack
    $item.IsExpanded = $true

    # Données
    $dataObject = [PSCustomObject]@{
        Type         = "Folder"
        Name         = $Name
        Id           = [Guid]::NewGuid().ToString() # NOUVEAU : ID Unique pour Liens Internes
        RelativePath = ""
        Permissions  = [System.Collections.Generic.List[psobject]]::new()
        Tags         = [System.Collections.Generic.List[psobject]]::new()
    }
    $item.Tag = $dataObject

    return $item
}

function Global:New-EditorLinkNode {
    param(
        [string]$Name,
        [string]$Url
    )
    
    $mItem = New-Object System.Windows.Controls.TreeViewItem
    $mItem.SetResourceReference([System.Windows.Controls.TreeViewItem]::StyleProperty, "ModernTreeViewItemStyle")
    # Tag Typé
    $mItem.Tag = [PSCustomObject]@{ 
        Type         = "Link"
        Id           = [Guid]::NewGuid().ToString()
        Name         = $Name 
        Url          = $Url 
        RelativePath = ""
        Tags         = [System.Collections.Generic.List[psobject]]::new()
    }
    
    $mStack = New-Object System.Windows.Controls.StackPanel -Property @{ Orientation = "Horizontal" }
    
    # Icône
    $mIcon = New-Object System.Windows.Controls.TextBlock 
    $mIcon.SetResourceReference([System.Windows.Controls.TextBlock]::StyleProperty, "LinkIconStyle") # Utilisation du style existant
    
    $mText = New-Object System.Windows.Controls.TextBlock -Property @{ Text = $Name; FontSize = 12; VerticalAlignment = "Center"; FontStyle = "Normal" } # Plus "fixe" qu'un MetaItem
    
    $mStack.Children.Add($mIcon) | Out-Null
    $mStack.Children.Add($mText) | Out-Null
    $mItem.Header = $mStack
    
    return $mItem
}

function Global:New-EditorPubNode {
    param(
        [string]$Name = "Nouvelle publication"
    )
    
    $mItem = New-Object System.Windows.Controls.TreeViewItem
    $mItem.SetResourceReference([System.Windows.Controls.TreeViewItem]::StyleProperty, "ModernTreeViewItemStyle")
    
    # Tag Typé Publication
    $mItem.Tag = [PSCustomObject]@{ 
        Type             = "Publication"
        Id               = [Guid]::NewGuid().ToString()
        RelativePath     = ""
        Name             = $Name
        TargetSiteMode   = "Auto"       # Auto (=Current) or Url
        TargetSiteUrl    = ""
        TargetFolderPath = "/Partage"
        UseFormName      = $true
        UseFormMetadata  = $false
        Permissions      = [System.Collections.Generic.List[psobject]]::new()
        Tags             = [System.Collections.Generic.List[psobject]]::new()
    }
    
    $mStack = New-Object System.Windows.Controls.StackPanel -Property @{ Orientation = "Horizontal" }
    
    # Icône Fusée (Emoji ou Style si dispo)
    $mIcon = New-Object System.Windows.Controls.TextBlock 
    $mIcon.Text = "🚀"
    $mIcon.Foreground = [System.Windows.Media.Brushes]::OrangeRed
    $mIcon.Margin = "0,0,5,0"
    
    $mText = New-Object System.Windows.Controls.TextBlock -Property @{ Text = $Name; FontSize = 12; VerticalAlignment = "Center"; FontStyle = "Normal"; FontWeight = "SemiBold" }
    
    $mStack.Children.Add($mIcon) | Out-Null
    $mStack.Children.Add($mText) | Out-Null
    $mItem.Header = $mStack
    
    return $mItem
}


<#
.SYNOPSIS
    Met à jour les indicateurs visuels (Badges) d'un noeud.

.DESCRIPTION
    Analyse les métadonnées (Permissions, Tags) stockées dans la propriété Tag de l'item.
    Met à jour les icônes et compteurs affichés à côté du nom du dossier.
    Gère également le rafraîchissement des sous-éléments de métadonnées (qui restent pour Perms/Tags).

.PARAMETER TreeItem
    Le TreeViewItem à mettre à jour.
#>
function Global:Update-EditorBadges {
    param([System.Windows.Controls.TreeViewItem]$TreeItem)

    if (-not $TreeItem -or -not $TreeItem.Tag) { return }
    
    $header = $TreeItem.Header
    if ($header -isnot [System.Windows.Controls.StackPanel]) { return }

    # DÉTERMINATION DE L'INDEX DE DÉPART DES BADGES
    # La plupart des noeuds ont [Icone, Texte] (Index 0, 1) -> Start = 2
    # InternalLink a [Icone, BadgeArrow, Texte] (Index 0, 1, 2) -> Start = 3
    $badgeStartIndex = 2
    if ($TreeItem.Tag.Type -eq "InternalLink") {
        $badgeStartIndex = 3
    }

    # Compter les éléments (Enfants VISUELS)
    $cntP = 0
    $cntT = 0
    $cntPub = 0
    $cntLink = 0
    
    foreach ($child in $TreeItem.Items) {
        if ($child.Tag) {
            if ($child.Tag.Type -eq "Permission") { $cntP++ }
            elseif ($child.Tag.Type -eq "Tag") { $cntT++ }
            elseif ($child.Tag.Type -eq "Publication") { $cntPub++ }
            elseif ($child.Tag.Type -eq "Link" -or $child.Tag.Type -eq "InternalLink") { $cntLink++ }
        }
    }
    
    # ⭐ NETTOYAGE ROBUSTE : Supprimer tout ce qui est après le contenu fixe
    # On itère à l'envers pour ne pas casser les index
    for ($i = $header.Children.Count - 1; $i -ge $badgeStartIndex; $i--) {
        $header.Children.RemoveAt($i)
    }

    # ⭐ RECRÉER les badges
    
    # Badge Permissions
    if ($cntP -gt 0) {
        $bdgPerm = New-Object System.Windows.Controls.Border -Property @{
            Background        = "#E3F2FD"
            CornerRadius      = 3
            Padding           = "4,2"
            Margin            = "5,0,0,0"
            VerticalAlignment = "Center"
        }
        $txtPerm = New-Object System.Windows.Controls.TextBlock -Property @{ Text = "👤 $cntP"; FontSize = 10; Foreground = "#1976D2" }
        $bdgPerm.Child = $txtPerm
        $header.Children.Add($bdgPerm) | Out-Null
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
        $txtTag = New-Object System.Windows.Controls.TextBlock -Property @{ Text = "🏷️ $cntT"; FontSize = 10; Foreground = "#689F38" }
        $bdgTag.Child = $txtTag
        $header.Children.Add($bdgTag) | Out-Null
    }
    
    # Badge Publications (Dossiers enfants de type Pub)
    if ($cntPub -gt 0) {
        $bdgPub = New-Object System.Windows.Controls.Border -Property @{
            Background        = "#FFF3E0"
            CornerRadius      = 3
            Padding           = "4,2"
            Margin            = "5,0,0,0"
            VerticalAlignment = "Center"
        }
        $txtPub = New-Object System.Windows.Controls.TextBlock -Property @{ Text = "🚀 $cntPub"; FontSize = 10; Foreground = "#E65100" }
        $bdgPub.Child = $txtPub
        $header.Children.Add($bdgPub) | Out-Null
    }

    # ⭐ Force le refresh visuel
    try {
        $header.InvalidateVisual()
        $TreeItem.InvalidateVisual()
    }
    catch { }
}

function Global:New-EditorPermNode {
    param(
        [string]$Email = "user@domaine.com",
        [string]$Level = "Read"
    )

    $mItem = New-Object System.Windows.Controls.TreeViewItem
    $mItem.SetResourceReference([System.Windows.Controls.TreeViewItem]::StyleProperty, "ModernTreeViewItemStyle")
    
    $mItem.Tag = [PSCustomObject]@{
        Type        = "Permission"
        Email       = $Email
        Level       = $Level
        User        = $Email # Alias for compatibility
        Permissions = $null # Leaf node
        Tags        = $null # Leaf node
    }
    
    # Standard indentation
    $mStack = New-Object System.Windows.Controls.StackPanel -Property @{ Orientation = "Horizontal" }
    
    # Icon Key (EMOJI - Robust)
    $mIcon = New-Object System.Windows.Controls.TextBlock
    $mIcon.Text = "👤"
    $mIcon.SetResourceReference([System.Windows.Controls.TextBlock]::StyleProperty, "PermIconStyle")
    $mIcon.FontSize = 14
    $mIcon.Margin = "0,0,5,0"
    
    $display = "$Email ($Level)"
    $mText = New-Object System.Windows.Controls.TextBlock -Property @{ Text = $display; FontSize = 12; VerticalAlignment = "Center"; FontStyle = "Italic"; Foreground = "#555" }
    
    $mStack.Children.Add($mIcon) | Out-Null
    $mStack.Children.Add($mText) | Out-Null
    $mItem.Header = $mStack
    
    return $mItem
}

function Global:New-EditorTagNode {
    param(
        [string]$Name = "Nom",
        [string]$Value = "Valeur",
        [bool]$IsDynamic = $false
    )

    $mItem = New-Object System.Windows.Controls.TreeViewItem
    $mItem.SetResourceReference([System.Windows.Controls.TreeViewItem]::StyleProperty, "ModernTreeViewItemStyle")
    
    $mItem.Tag = [PSCustomObject]@{
        Type        = "Tag"
        Name        = $Name
        Value       = $Value
        IsDynamic   = $IsDynamic
        SourceForm  = ""
        SourceVar   = ""
        Permissions = $null
        Tags        = $null # Leaf node
    }
    
    # Standard indentation
    $mStack = New-Object System.Windows.Controls.StackPanel -Property @{ Orientation = "Horizontal" }
    
    # Icon Key (EMOJI - Robust)
    $mIcon = New-Object System.Windows.Controls.TextBlock
    
    if ($mItem.Tag.IsDynamic) {
        $mIcon.Text = "⚡"
        $mIcon.Foreground = [System.Windows.Media.Brushes]::Orange
    }
    else {
        $mIcon.Text = "🏷️"
        $mIcon.Foreground = "#689F38" # Green
    }

    $mIcon.FontSize = 14
    $mIcon.Margin = "0,0,5,0"
    
    if ($mItem.Tag.IsDynamic) {
        $display = "$Name"
    }
    else {
        $display = "$Name : $Value"
    }

    $mText = New-Object System.Windows.Controls.TextBlock -Property @{ Text = $display; VerticalAlignment = "Center"; Foreground = "#555" }
    
    $mStack.Children.Add($mIcon) | Out-Null
    $mStack.Children.Add($mText) | Out-Null
    $mItem.Header = $mStack
    
    return $mItem
}