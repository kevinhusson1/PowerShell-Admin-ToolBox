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
    [scriptblock] Le bloc de code à exécuter pour rafraîchir la preview.
#>

function Get-PreviewLogic {
    param(
        $Ctrl,
        [System.Windows.Window]$Window
    )

    return {
        param($sender, $e)
        
        # 1. Récupération Robuste depuis la Hashtable $Ctrl (déjà indexée)
        $cSite = $Ctrl.CbSites
        $cLib = $Ctrl.CbLibs
        $cTpl = $Ctrl.CbTemplates
        $cChk = $Ctrl.ChkCreateFolder
        $cPreview = $Ctrl.TxtPreview
        $cBtn = $Ctrl.BtnDeploy
        $cBtnValidate = $Ctrl.BtnValidate
        $cPanel = $Ctrl.PanelForm
        $cTree = $Ctrl.TreeView
        $cMeta = $Window.FindName("FolderNameMetaPreview") # Pas dans Ctrl
        $cFormScroll = $Ctrl.FormScrollViewer

        if (-not $cBtn) { 
            Write-Verbose "[PreviewLogic] DeployButton non trouvé dans Ctrl."
            return 
        }

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
        $isApplyMeta = [bool]($Window.FindName("DeployApplyMetaChk").IsChecked)

        # 4. Visibilité des Zones (Enums WPF requis pour la robustesse)
        $cFormScroll = $Ctrl.FormScrollViewer
        $cNameCont   = $Ctrl.PreviewContainer
        $cMetaCont   = $Ctrl.MetaPreviewContainer
        $cMeta       = $Ctrl.MetaPreviewText

        $vVisible = [System.Windows.Visibility]::Visible
        $vCollapsed = [System.Windows.Visibility]::Collapsed

        if ($isCreateFolder) {
            Write-Verbose "[PreviewLogic] Mode Création Dossier ACTIF"
            if ($cFormScroll) { $cFormScroll.Visibility = $vVisible }
            if ($cNameCont)   { $cNameCont.Visibility   = $vVisible }
            if ($cMetaCont)   { $cMetaCont.Visibility   = ($isApplyMeta ? $vVisible : $vCollapsed) }
        } else {
            Write-Verbose "[PreviewLogic] Mode Racine ACTIF"
            if ($cFormScroll) { $cFormScroll.Visibility = $vCollapsed }
            if ($cNameCont) { $cNameCont.Visibility = $vCollapsed }
            if ($cMetaCont) { $cMetaCont.Visibility = $vCollapsed }
        }

        # 5. Mise à jour Visuelle (Preview Texte)
        if ($cPreview -and $isCreateFolder) {
            if (-not [string]::IsNullOrWhiteSpace($finalName)) {
                $cPreview.Text = $finalName
                $cPreview.Foreground = $Window.FindResource("PrimaryBrush")
            } else {
                $cPreview.Text = "En attente de saisie..."
                $cPreview.Foreground = [System.Windows.Media.Brushes]::Orange
            }
            
            # Update Meta
            if ($cMeta) {
                if ($metaParts.Count -gt 0) {
                    $cMeta.Text = $metaParts -join " | "
                    $cMeta.Foreground = [System.Windows.Media.Brushes]::Teal
                }
                else {
                    $cMeta.Text = "(Aucune métadonnée à appliquer)"
                    $cMeta.Foreground = $Window.FindResource("TextSecondaryBrush")
                }
            }
        }

        # 6. Mise à jour de l'Arbre Visuel (TreeView)
        if ($cTpl.SelectedItem) {
            $structJson = ""
            if ($cTpl.SelectedItem.PSObject.Properties.Match('StructureJson').Count -gt 0) {
                $structJson = $cTpl.SelectedItem.StructureJson
            }
            Write-Verbose "[PreviewLogic] Refresh TreeView... (JSON: $($structJson.Length ?? 0) chars)"
            Update-TreePreview -TreeView $cTree -JsonStructure $structJson -FormPanel $cPanel
        }

        # 7. Matrice de Validation
        $hasSite = ($null -ne $cSite.SelectedItem -and $cSite.SelectedItem -isnot [string])
        $hasLib = ($null -ne $cLib.SelectedItem -and $cLib.SelectedItem -isnot [string] -and $cLib.SelectedItem -ne "Chargement...")
        $hasTpl = ($null -ne $cTpl.SelectedItem)
        
        # Invalider le bouton Déployer en cas de changement
        if ($cBtn.IsEnabled) { $cBtn.IsEnabled = $false }

        $isValid = if ($isCreateFolder) {
            $hasSite -and $hasLib -and $hasTpl -and (-not [string]::IsNullOrWhiteSpace($finalName))
        } else {
            $hasSite -and $hasLib -and $hasTpl
        }

        if ($cBtnValidate) {
            $cBtnValidate.IsEnabled = $isValid
        }

    }.GetNewClosure()
}