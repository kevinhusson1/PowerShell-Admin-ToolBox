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
    
    # ⭐ Force le refresh visuel
    try {
        $header.InvalidateVisual()
        $TreeItem.InvalidateVisual()
        $header.UpdateLayout()
        $TreeItem.UpdateLayout()
    }
    catch {
        # Write-Host "  ⚠️ Erreur UpdateLayout: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}