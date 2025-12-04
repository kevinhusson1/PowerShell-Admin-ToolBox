# Scripts/SharePoint/SharePointBuilder/Functions/Logic/New-EditorNode.ps1

function Global:New-EditorNode {
    param(
        [string]$Name = "Nouveau dossier"
    )

    $item = New-Object System.Windows.Controls.TreeViewItem
    
    # Conteneur Horizontal
    $stack = New-Object System.Windows.Controls.StackPanel -Property @{ Orientation = "Horizontal" }
    
    # 1. Icône Dossier
    $icon = New-Object System.Windows.Controls.TextBlock -Property @{ Text = "📁"; Margin = "0,0,5,0"; Foreground = "#FFC107"; FontSize = 14 }
    
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

function Global:Update-EditorBadges {
    param([System.Windows.Controls.TreeViewItem]$TreeItem)

    if (-not $TreeItem -or -not $TreeItem.Tag) { return }
    $data = $TreeItem.Tag
    $header = $TreeItem.Header
    
    if ($header -isnot [System.Windows.Controls.StackPanel]) { return }

    # Rappel structure : [0]Icon [1]Name [2]BadgePerm [3]BadgeTag [4]BadgeLink

    # Perms
    $bdgPerm = $header.Children[2]
    $cntP = if ($data.Permissions) { $data.Permissions.Count } else { 0 }
    if ($cntP -gt 0) { $bdgPerm.Visibility = "Visible"; $bdgPerm.Child.Text = "👤 $cntP" } else { $bdgPerm.Visibility = "Collapsed" }

    # Tags
    $bdgTag = $header.Children[3]
    $cntT = if ($data.Tags) { $data.Tags.Count } else { 0 }
    if ($cntT -gt 0) { $bdgTag.Visibility = "Visible"; $bdgTag.Child.Text = "🏷️ $cntT" } else { $bdgTag.Visibility = "Collapsed" }

    # Liens
    $bdgLink = $header.Children[4]
    $cntL = if ($data.Links) { $data.Links.Count } else { 0 }
    if ($cntL -gt 0) { $bdgLink.Visibility = "Visible"; $bdgLink.Child.Text = "🔗 $cntL" } else { $bdgLink.Visibility = "Collapsed" }
}