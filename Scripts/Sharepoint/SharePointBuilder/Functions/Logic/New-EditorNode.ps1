# Scripts/SharePoint/SharePointBuilder/Functions/Logic/New-EditorNode.ps1

function Global:New-EditorNode {
    param(
        [string]$Name = "Nouveau dossier"
    )

    $item = New-Object System.Windows.Controls.TreeViewItem
    
    # A. Le Header Visuel (Dossier Jaune + Texte)
    $stack = New-Object System.Windows.Controls.StackPanel -Property @{ Orientation = "Horizontal" }
    $icon = New-Object System.Windows.Controls.TextBlock -Property @{ Text = "📁"; Margin = "0,0,5,0"; Foreground = "#FFC107"; FontSize = 14 }
    $text = New-Object System.Windows.Controls.TextBlock -Property @{ Text = $Name; VerticalAlignment = "Center" }
    
    # CORRECTION ICI : On jette le résultat (index) dans le néant
    $stack.Children.Add($icon) | Out-Null
    $stack.Children.Add($text) | Out-Null
    
    $item.Header = $stack
    $item.IsExpanded = $true

    # B. L'Objet de Données (Stocké dans le Tag)
    $dataObject = [PSCustomObject]@{
        Name        = $Name
        Permissions = [System.Collections.Generic.List[psobject]]::new()
        Tags        = [System.Collections.Generic.List[psobject]]::new()
        Links       = [System.Collections.Generic.List[psobject]]::new()
    }
    $item.Tag = $dataObject

    return $item
}