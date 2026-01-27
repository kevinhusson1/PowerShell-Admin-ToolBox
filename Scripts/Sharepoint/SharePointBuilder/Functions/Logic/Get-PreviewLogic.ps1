# Scripts/SharePoint/SharePointBuilder/Functions/Logic/Get-PreviewLogic.ps1

<#
.SYNOPSIS
    Génère le bloc de logique de prévisualisation et de validation.

.DESCRIPTION
    Retourne un ScriptBlock qui encapsule la logique de mise à jour de l'interface :
    - Calcul du nom final du dossier basé sur le formulaire dynamique.
    - Mise à jour du texte de prévisualisation.
    - Rafraîchissement de l'arbre visuel (TreeView) si un template est sélectionné.
    - Validation stricte des entrées pour activer/désactiver le bouton "Déployer".

.PARAMETER Ctrl
    La Hashtable des contrôles UI.

.PARAMETER Window
    La fenêtre WPF principale.

.OUTPUTS
    [ScriptBlock] Le bloc de code à exécuter lors des changements d'entrée.
#>
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
        $cBtnValidate = $Window.FindName("ValidateModelButton")
        $cPanel = $Window.FindName("DynamicFormPanel")
        $cBtnValidate = $Window.FindName("ValidateModelButton")
        $cPanel = $Window.FindName("DynamicFormPanel")
        $cTree = $Window.FindName("PreviewTreeView")
        $cMeta = $Window.FindName("FolderNameMetaPreview")

        if (-not $cBtn) { return }

        # 2. Calcul du Nom (Formulaire) & Metadonnées
        $finalName = ""
        $metaParts = @()
        
        if ($cPanel -and $cPanel.Children) {
            foreach ($c in $cPanel.Children) {
                if ($c -is [System.Windows.Controls.TextBox]) { 
                    $finalName += $c.Text 
                    if ($c.Tag -and $c.Tag.IsMeta) { $metaParts += "$($c.Tag.Key)=$($c.Text)" }
                }
                elseif ($c -is [System.Windows.Controls.TextBlock] -and ($c.Tag -eq "Static" -or $c.Tag.Type -eq "Static")) { 
                    $finalName += $c.Text 
                    if ($c.Tag -is [hashtable] -and $c.Tag.IsMeta) { $metaParts += "$($c.Tag.Key)=$($c.Text)" }
                }
                elseif ($c -is [System.Windows.Controls.ComboBox]) { 
                    $finalName += $c.SelectedItem 
                    if ($c.Tag -and $c.Tag.IsMeta) { $metaParts += "$($c.Tag.Key)=$($c.SelectedItem)" }
                }
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
                
                # Update Meta
                if ($cMeta) {
                    if ($metaParts.Count -gt 0) {
                        $cMeta.Text = $metaParts -join " | "
                        $cMeta.Foreground = [System.Windows.Media.Brushes]::Teal
                    }
                    else {
                        $cMeta.Text = "(Aucune métadonnée)"
                        $cMeta.Foreground = [System.Windows.Media.Brushes]::Gray
                    }
                }
            }
            else {
                $cPreview.Text = "(Déploiement à la racine de la bibliothèque)"
                $cPreview.Opacity = 0.6
                $cPreview.Foreground = $Window.FindResource("TextSecondaryBrush")
                
                if ($cMeta) { $cMeta.Text = "-" }
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
        
        # FIX: Ne JAMIAS activer le bouton Déployer directement depuis le formulaire.
        # Tout changement invalide la validation précédente et force une re-vérification.
        if ($cBtn.IsEnabled) { $cBtn.IsEnabled = $false }

        # On active le bouton de validation seulement si le formulaire est complet
        if ($cBtnValidate) {
            $cBtnValidate.IsEnabled = $isValid
        }

    }.GetNewClosure()
}