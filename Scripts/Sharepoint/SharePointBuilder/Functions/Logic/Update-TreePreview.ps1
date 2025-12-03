# Scripts/SharePoint/SharePointBuilder/Functions/Logic/Update-TreePreview.ps1

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
        } elseif ($structure.Root) {
            $rootList = @($structure.Root)
        } else {
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
            
            $stack = New-Object System.Windows.Controls.StackPanel -Property @{ Orientation = "Horizontal" }
            $icon = New-Object System.Windows.Controls.TextBlock -Property @{ Text = "📁"; Margin = "0,0,5,0"; Foreground = "#FFC107"; FontSize = 14 }
            $text = New-Object System.Windows.Controls.TextBlock -Property @{ Text = $finalName; VerticalAlignment = "Center" }
            
            if ($Node.Permissions) { 
                $text.Foreground = "#4CAF50"
                $text.ToolTip = "Permissions définies"
            }

            # CORRECTION : Ajout de | Out-Null pour ne pas polluer la sortie
            $stack.Children.Add($icon) | Out-Null
            $stack.Children.Add($text) | Out-Null
            
            $item.Header = $stack
            $item.IsExpanded = $true

            if ($Node.Folders) {
                foreach ($subNode in $Node.Folders) {
                    $subItem = New-VisuItem -Node $subNode
                    # CORRECTION ICI AUSSI
                    $item.Items.Add($subItem) | Out-Null
                }
            }
            
            if ($Node.Links) {
                foreach ($link in $Node.Links) {
                    $lItem = New-Object System.Windows.Controls.TreeViewItem
                    $lStack = New-Object System.Windows.Controls.StackPanel -Property @{ Orientation = "Horizontal" }
                    $lIcon = New-Object System.Windows.Controls.TextBlock -Property @{ Text = "🔗"; Margin = "0,0,5,0"; Foreground = "#2196F3" }
                    $lText = New-Object System.Windows.Controls.TextBlock -Property @{ Text = [string]$link.Name; FontStyle = "Italic"; FontSize = 11; VerticalAlignment = "Center" }
                    
                    # CORRECTION ICI AUSSI
                    $lStack.Children.Add($lIcon) | Out-Null
                    $lStack.Children.Add($lText) | Out-Null
                    
                    $lItem.Header = $lStack
                    $item.Items.Add($lItem) | Out-Null
                }
            }

            return $item
        }

        # 4. Boucle principale
        foreach ($rootNode in $rootList) {
            $tvItem = New-VisuItem -Node $rootNode
            $TreeView.Items.Add($tvItem)
        }

    } catch {
        Write-Verbose "Erreur Preview TreeView : $_"
    }
}