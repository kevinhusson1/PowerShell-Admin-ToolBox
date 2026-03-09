# scripts/SharePoint/SharePointBuilder/Functions/Logic/New-EditorInternalLinkNode.ps1

<#
.SYNOPSIS
    Crée un nouvel élément visuel (Node) de type "Lien Interne" pour l'arbre d'édition.

.DESCRIPTION
    Génère un TreeViewItem stylisé représentant une navigation interne.
    Le lien interne pointe vers un autre noeud de l'arborescence via son ID.

.PARAMETER Name
    Le nom d'affichage du lien.

.PARAMETER TargetNodeId
    L'ID unique du noeud cible (Dossier) vers lequel ce lien pointe.

.OUTPUTS
    [TreeViewItem] L'élément prêt à être ajouté au TreeView.
#>
function Global:New-EditorInternalLinkNode {
    param(
        [string]$Name = "Nouveau lien interne",
        [string]$TargetNodeId = ""
    )

    # 1. Création de l'objet UI
    $node = New-Object System.Windows.Controls.TreeViewItem
    $node.IsExpanded = $true
    
    # 2. Header (StackPanel avec Icône + Nom)
    $headerStack = New-Object System.Windows.Controls.StackPanel
    $headerStack.Orientation = "Horizontal"
    
    # Icône Lien (Chain)
    $icon = New-Object System.Windows.Controls.TextBlock
    $icon.Text = "🔗" # Chain Link
    $icon.Margin = "0,0,5,0"
    $icon.VerticalAlignment = "Center"
    
    # Badge (Fleche)
    $badge = New-Object System.Windows.Controls.TextBlock
    $badge.Text = "↪️" 
    $badge.FontSize = 10
    $badge.Margin = "0,0,5,0"
    $badge.Foreground = [System.Windows.Media.Brushes]::DarkCyan
    $badge.VerticalAlignment = "Center"

    # Texte
    $textBlock = New-Object System.Windows.Controls.TextBlock
    $textBlock.Text = $Name
    $textBlock.VerticalAlignment = "Center"
    
    $headerStack.Children.Add($icon) | Out-Null
    $headerStack.Children.Add($badge) | Out-Null
    $headerStack.Children.Add($textBlock) | Out-Null
    
    $node.Header = $headerStack
    
    # 3. Tag (Données Métier)
    $node.Tag = [PSCustomObject]@{
        Type         = "InternalLink"
        Name         = $Name
        Id           = [Guid]::NewGuid().ToString()
        TargetNodeId = $TargetNodeId
        RelativePath = ""
        Tags         = [System.Collections.Generic.List[psobject]]::new()
    }

    return $node
}
