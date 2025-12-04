# Scripts/SharePoint/SharePointBuilder/Functions/Logic/Get-PreviewLogic.ps1

function Get-PreviewLogic {
    param(
        $Ctrl,
        [System.Windows.Window]$Window
    )

    return {
        param($sender, $e)
        
        # 1. Récupération Sûre des Contrôles
        $cSite = $Window.FindName("SiteComboBox")
        $cLib = $Window.FindName("LibraryComboBox")
        $cTpl = $Window.FindName("TemplateComboBox")
        $cChk = $Window.FindName("CreateFolderCheckBox")
        $cPreview = $Window.FindName("FolderNamePreviewText")
        $cBtn = $Window.FindName("DeployButton")
        $cPanel = $Window.FindName("DynamicFormPanel")
        $cTree = $Window.FindName("PreviewTreeView")

        if (-not $cBtn) { return }

        # 2. Calcul du Nom (Formulaire)
        $finalName = ""
        if ($cPanel -and $cPanel.Children) {
            foreach ($c in $cPanel.Children) {
                if ($c -is [System.Windows.Controls.TextBox]) { $finalName += $c.Text }
                elseif ($c -is [System.Windows.Controls.TextBlock] -and $c.Tag -eq "Static") { $finalName += $c.Text }
                elseif ($c -is [System.Windows.Controls.ComboBox]) { $finalName += $c.SelectedItem }
            }
        }

        # 3. État de la Case à Cocher
        $isCreateFolder = [bool]($cChk.IsChecked)

        # 4. Mise à jour Visuelle (Preview Texte)
        if ($cPreview) {
            if ($isCreateFolder) {
                $cPreview.Text = if ($finalName) { $finalName } else { "..." }
                $cPreview.Opacity = 1
                $cPreview.Foreground = $Window.FindResource("PrimaryBrush")
            }
            else {
                $cPreview.Text = "(Déploiement à la racine de la bibliothèque)"
                $cPreview.Opacity = 0.6
                $cPreview.Foreground = $Window.FindResource("TextSecondaryBrush")
            }
        }

        # 5. Mise à jour de l'Arbre Visuel (TreeView)
        # On récupère le JSON du template sélectionné
        if ($cTpl.SelectedItem) {
            Update-TreePreview -TreeView $cTree -JsonStructure $cTpl.SelectedItem.StructureJson -FormPanel $cPanel
        }

        # 6. Matrice de Validation
        $hasSite = $null -ne $cSite.SelectedItem
        $hasLib = $null -ne $cLib.SelectedItem
        $hasTpl = $null -ne $cTpl.SelectedItem
        
        if ($isCreateFolder) {
            # Cas Dossier : Tout + Nom valide
            $isValid = $hasSite -and $hasLib -and $hasTpl -and (-not [string]::IsNullOrWhiteSpace($finalName))
        }
        else {
            # Cas Racine : Tout sauf le nom
            $isValid = $hasSite -and $hasLib -and $hasTpl
        }
        
        $cBtn.IsEnabled = $isValid

    }.GetNewClosure()
}