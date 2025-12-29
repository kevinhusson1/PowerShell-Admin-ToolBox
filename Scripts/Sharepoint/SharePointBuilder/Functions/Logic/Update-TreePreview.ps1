# Scripts/SharePoint/SharePointBuilder/Functions/Logic/Update-TreePreview.ps1

<#
.SYNOPSIS
    Génère une prévisualisation en lecture seule de la structure de dossiers.

.DESCRIPTION
    Utilisé dans l'onglet principal pour montrer à l'utilisateur ce qui sera déployé.
    Remplace dynamiquement les variables (ex: {ProjectCode}) par les valeurs saisies dans le formulaire.
    Affiche également les badges de permissions/tags/liens.

.PARAMETER TreeView
    Le TreeView de prévisualisation (lecture seule).

.PARAMETER JsonStructure
    Le JSON du template sélectionné.

.PARAMETER FormPanel
    Le panneau contenant les contrôles du formulaire dynamique (pour récupérer les valeurs).
#>
function Global:Update-TreePreview {
    param(
        [System.Windows.Controls.TreeView]$TreeView,
        [string]$JsonStructure,
        [System.Windows.Controls.Panel]$FormPanel
    )

    if (-not $TreeView) { return }
    $TreeView.Items.Clear()

    if ([string]::IsNullOrWhiteSpace($JsonStructure)) { return }

    try {
        # 1. Récupération des valeurs du formulaire
        $replacements = @{}
        if ($FormPanel) {
            foreach ($ctrl in $FormPanel.Children) {
                $val = ""
                if ($ctrl -is [System.Windows.Controls.TextBox]) { $val = $ctrl.Text }
                elseif ($ctrl -is [System.Windows.Controls.ComboBox]) { $val = $ctrl.SelectedItem }
                
                if ($ctrl.Name -like "Input_*") {
                    $key = $ctrl.Name.Replace("Input_", "")
                    $replacements[$key] = $val
                }
            }
        }

        # 2. Parsing du JSON (Sécurisé)
        $structure = $JsonStructure | ConvertFrom-Json
        
        # Gestion intelligente : soit c'est un tableau de dossiers à la racine, soit un objet Root avec Folders
        $rootList = @()
        if ($structure.Folders) {
            $rootList = $structure.Folders
        }
        elseif ($structure.Root) {
            $rootList = @($structure.Root)
        }
        else {
            # Cas où le JSON est directement un tableau
            $rootList = $structure
        }

        # 3. Fonction récursive
        function New-VisuItem {
            param($Node)

            # Cast en string
            $rawName = if ($Node.Name) { [string]$Node.Name } else { "Dossier sans nom" }
            
            # Remplacement variables
            $finalName = $rawName
            foreach ($key in $replacements.Keys) {
                if ($finalName -match "\{$key\}") {
                    $finalName = $finalName -replace "\{$key\}", $replacements[$key]
                }
            }

            $item = New-Object System.Windows.Controls.TreeViewItem
            $item.SetResourceReference([System.Windows.Controls.TreeViewItem]::StyleProperty, "ModernTreeViewItemStyle")
            
            $stack = New-Object System.Windows.Controls.StackPanel -Property @{ Orientation = "Horizontal" }
            $icon = New-Object System.Windows.Controls.TextBlock 
            $icon.Text = "📁"
            $icon.SetResourceReference([System.Windows.Controls.TextBlock]::StyleProperty, "TreeItemIconStyle")
            $text = New-Object System.Windows.Controls.TextBlock -Property @{ Text = $finalName; VerticalAlignment = "Center" }
            
            $stack.Children.Add($icon) | Out-Null
            $stack.Children.Add($text) | Out-Null
            
            # --- BADGES (Header) ---
            $cntP = if ($Node.Permissions) { $Node.Permissions.Count } else { 0 }
            $cntT = if ($Node.Tags) { $Node.Tags.Count } else { 0 }
            $cntL = if ($Node.Links) { $Node.Links.Count } else { 0 }

            # Badge Permissions
            if ($cntP -gt 0) {
                $bdgPerm = New-Object System.Windows.Controls.Border -Property @{ Background = "#E3F2FD"; CornerRadius = 3; Padding = "4,2"; Margin = "5,0,0,0"; VerticalAlignment = "Center" }
                $bdgPerm.Child = New-Object System.Windows.Controls.TextBlock -Property @{ Text = "👤 $cntP"; FontSize = 10; Foreground = "#1976D2" }
                $stack.Children.Add($bdgPerm) | Out-Null
            }
            # Badge Tags
            if ($cntT -gt 0) {
                $bdgTag = New-Object System.Windows.Controls.Border -Property @{ Background = "#F1F8E9"; CornerRadius = 3; Padding = "4,2"; Margin = "5,0,0,0"; VerticalAlignment = "Center" }
                $bdgTag.Child = New-Object System.Windows.Controls.TextBlock -Property @{ Text = "🏷️ $cntT"; FontSize = 10; Foreground = "#689F38" }
                $stack.Children.Add($bdgTag) | Out-Null
            }
            # Badge Links
            if ($cntL -gt 0) {
                $bdgLink = New-Object System.Windows.Controls.Border -Property @{ Background = "#FFF3E0"; CornerRadius = 3; Padding = "4,2"; Margin = "5,0,0,0"; VerticalAlignment = "Center" }
                $bdgLink.Child = New-Object System.Windows.Controls.TextBlock -Property @{ Text = "🔗 $cntL"; FontSize = 10; Foreground = "#F57C00" }
                $stack.Children.Add($bdgLink) | Out-Null
            }

            $item.Header = $stack
            $item.IsExpanded = $true

            # --- SOUS-ÉLÉMENTS METADATA (Permissions, Tags, Links) ---
            
            # 1. Permissions
            if ($Node.Permissions) {
                foreach ($perm in $Node.Permissions) {
                    $pItem = New-Object System.Windows.Controls.TreeViewItem
                    $pItem.SetResourceReference([System.Windows.Controls.TreeViewItem]::StyleProperty, "ModernTreeViewItemStyle")
                    $pStack = New-Object System.Windows.Controls.StackPanel -Property @{ Orientation = "Horizontal" }
                    $pIcon = New-Object System.Windows.Controls.TextBlock
                    $pIcon.SetResourceReference([System.Windows.Controls.TextBlock]::StyleProperty, "PermIconStyle")
                    
                    # Logique d'affichage : "Groupe (Niveau)"
                    $pName = ""
                    if ($perm.Identity) { 
                        $pName = "$($perm.Identity) ($($perm.Level))" 
                    } 
                    elseif ($perm.User) {
                        # Compatibilité ancien format
                        $pName = "$($perm.User) ($($perm.Level))" 
                    }
                    else { 
                        # Cas string simple check
                        $pName = [string]$perm
                    }

                    $pText = New-Object System.Windows.Controls.TextBlock -Property @{ Text = $pName; FontSize = 11; VerticalAlignment = "Center" }
                    
                    $pStack.Children.Add($pIcon) | Out-Null
                    $pStack.Children.Add($pText) | Out-Null
                    $pItem.Header = $pStack
                    $item.Items.Add($pItem) | Out-Null
                }
            }

            # 2. Tags
            if ($Node.Tags) {
                foreach ($tag in $Node.Tags) {
                    $tItem = New-Object System.Windows.Controls.TreeViewItem
                    $tItem.SetResourceReference([System.Windows.Controls.TreeViewItem]::StyleProperty, "ModernTreeViewItemStyle")
                    $tStack = New-Object System.Windows.Controls.StackPanel -Property @{ Orientation = "Horizontal" }
                    $tIcon = New-Object System.Windows.Controls.TextBlock
                    $tIcon.SetResourceReference([System.Windows.Controls.TextBlock]::StyleProperty, "TagIconStyle")
                    
                    # Logique d'affichage : "Colonne : Valeur"
                    $tagName = ""
                    if ($tag.Name -and $tag.Value) {
                        $tagName = "$($tag.Name) : $($tag.Value)"
                    }
                    elseif ($tag.Column -and $tag.Term) {
                        # Compatibilité ancien format
                        $tagName = "$($tag.Column) : $($tag.Term)"
                    }
                    else {
                        $tagName = [string]$tag
                    }

                    $tText = New-Object System.Windows.Controls.TextBlock -Property @{ Text = $tagName; FontSize = 11; VerticalAlignment = "Center" }

                    $tStack.Children.Add($tIcon) | Out-Null
                    $tStack.Children.Add($tText) | Out-Null
                    $tItem.Header = $tStack
                    $item.Items.Add($tItem) | Out-Null
                }
            }

            # 3. Liens (Links)
            if ($Node.Links) {
                foreach ($link in $Node.Links) {
                    $lItem = New-Object System.Windows.Controls.TreeViewItem
                    $lItem.SetResourceReference([System.Windows.Controls.TreeViewItem]::StyleProperty, "ModernTreeViewItemStyle")
                    $lStack = New-Object System.Windows.Controls.StackPanel -Property @{ Orientation = "Horizontal" }
                    $lIcon = New-Object System.Windows.Controls.TextBlock
                    $lIcon.SetResourceReference([System.Windows.Controls.TextBlock]::StyleProperty, "LinkIconStyle")
                    
                    $lName = if ($link.Name) { [string]$link.Name } else { [string]$link.Url }
                    $lText = New-Object System.Windows.Controls.TextBlock -Property @{ Text = $lName; FontStyle = "Italic"; FontSize = 11; VerticalAlignment = "Center" }
                    
                    $lStack.Children.Add($lIcon) | Out-Null
                    $lStack.Children.Add($lText) | Out-Null
                    $lItem.Header = $lStack
                    $item.Items.Add($lItem) | Out-Null
                }
            }

            # --- SOUS-DOSSIERS ---
            if ($Node.Folders) {
                foreach ($subNode in $Node.Folders) {
                    $subItem = New-VisuItem -Node $subNode
                    $item.Items.Add($subItem) | Out-Null
                }
            }
            
            return $item
        }

        # 4. Boucle principale
        foreach ($rootNode in $rootList) {
            $tvItem = New-VisuItem -Node $rootNode
            $TreeView.Items.Add($tvItem)
        }

    }
    catch {
        Write-Verbose "Erreur Preview TreeView : $_"
    }
}