<#
.SYNOPSIS
    Crée un nouvel élément TreeViewItem représentant un Fichier à copier.
    
.DESCRIPTION
    Structure du Tag :
    - Id (Guid)
    - Name (String) : Nom du fichier cible
    - Type (String) : "File"
    - SourceUrl (String) : URL du fichier à copier
    - Permissions (List) : Liste des droits
    - Tags (List) : Liste des métadonnées
#>
function Global:New-EditorFileNode {
    param(
        [string]$Name = "Nouveau Fichier",
        [string]$SourceUrl = ""
    )
    
    $item = New-Object System.Windows.Controls.TreeViewItem
    
    # --- HEADER VISUEL ---
    $stack = New-Object System.Windows.Controls.StackPanel
    $stack.Orientation = "Horizontal"
    
    # Icone Fichier
    $icon = New-Object System.Windows.Controls.TextBlock
    $icon.Text = "📄"  # Page/File Emoji
    $icon.Margin = "0,0,5,0"
    $icon.VerticalAlignment = "Center"
    $icon.Foreground = "#3F51B5" # Indigo
    
    # Texte (Nom)
    $textBlock = New-Object System.Windows.Controls.TextBlock
    $textBlock.Text = $Name
    $textBlock.VerticalAlignment = "Center"
    
    $stack.Children.Add($icon) | Out-Null
    $stack.Children.Add($textBlock) | Out-Null
    
    $item.Header = $stack
    $item.IsExpanded = $true
    
    # --- DATA OBJECT (TAG) ---
    $tag = [PSCustomObject]@{
        Id          = [Guid]::NewGuid().ToString()
        Name        = $Name
        Type        = "File"
        SourceUrl   = $SourceUrl
        Permissions = [System.Collections.Generic.List[psobject]]::new()
        Tags        = [System.Collections.Generic.List[psobject]]::new()
    }
    
    $item.Tag = $tag
    
    return $item
}
