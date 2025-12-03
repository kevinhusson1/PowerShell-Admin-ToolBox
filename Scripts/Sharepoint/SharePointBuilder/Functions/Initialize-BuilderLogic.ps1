function Initialize-BuilderLogic {
    param($Context)

    $Window = $Context.Window
    $ScriptRoot = $Context.ScriptRoot

    # 1. Chargement des sous-fonctions logiques
    $logicPath = Join-Path $ScriptRoot "Functions\Logic"
    if (Test-Path $logicPath) {
        Get-ChildItem -Path $logicPath -Filter "*.ps1" | ForEach-Object { 
            Write-Verbose "Chargement logique : $($_.Name)"
            . $_.FullName 
        }
    }

    # 2. Récupération centralisée des contrôles
    $Ctrl = Get-BuilderControls -Window $Window
    if (-not $Ctrl) { return }

    # 3. Initialisation UX
    $Ctrl.CbSites.IsEnabled = $false
    $Ctrl.CbLibs.IsEnabled = $false
    $Ctrl.BtnDeploy.IsEnabled = $false

    # ==============================================================================
    # 2. LOGIQUE DE PRÉVISUALISATION (Mise à jour Dossier + TreeView)
    # ==============================================================================
    $PreviewLogic = {
        param($sender, $e)
        
        # A. Récupération sécurisée
        $safePanel = if ($panelForm) { $panelForm } else { $Window.FindName("DynamicFormPanel") }
        $safePreview = if ($txtPreview) { $txtPreview } else { $Window.FindName("FolderNamePreviewText") }
        $safeTree = if ($TreeView) { $TreeView } else { $Window.FindName("PreviewTreeView") }
        $safeTplCb = if ($cbTemplates) { $cbTemplates } else { $Window.FindName("TemplateComboBox") }

        # B. Calcul du Nom du Dossier Racine
        $finalName = ""
        if ($safePanel.Children) {
            foreach ($c in $safePanel.Children) {
                if ($c -is [System.Windows.Controls.TextBox]) { $finalName += $c.Text }
                elseif ($c -is [System.Windows.Controls.TextBlock] -and $c.Tag -eq "Static") { $finalName += $c.Text }
                elseif ($c -is [System.Windows.Controls.ComboBox]) { $finalName += $c.SelectedItem }
            }
        }
        $safePreview.Text = if ($finalName) { $finalName } else { "..." }
        
        # C. Mise à jour de l'Arbre Visuel (NOUVEAU)
        # On récupère le JSON du template sélectionné
        $selectedTpl = $safeTplCb.SelectedItem
        if ($selectedTpl) {
            Update-TreePreview -TreeView $safeTree -JsonStructure $selectedTpl.StructureJson -FormPanel $safePanel
        }

        # D. Validation du Bouton
        $safeDeploy = if ($btnDeploy) { $btnDeploy } else { $Window.FindName("DeployButton") }
        $safeSite = if ($cbSites) { $cbSites } else { $Window.FindName("SiteComboBox") }
        $safeLib = if ($cbLibs) { $cbLibs } else { $Window.FindName("LibraryComboBox") }

        $isValid = (-not [string]::IsNullOrWhiteSpace($finalName)) -and ($null -ne $safeSite.SelectedItem) -and ($null -ne $safeLib.SelectedItem)
        $safeDeploy.IsEnabled = $isValid

    }.GetNewClosure()

    # 5. Câblage avec passage du CONTEXTE (pour Autopilot)
    Register-TemplateEvents -Ctrl $Ctrl -PreviewLogic $PreviewLogic -Window $Window -Context $Context
    Register-SiteEvents     -Ctrl $Ctrl -PreviewLogic $PreviewLogic -Window $Window -Context $Context
    Register-DeployEvents   -Ctrl $Ctrl -Window $Window
}