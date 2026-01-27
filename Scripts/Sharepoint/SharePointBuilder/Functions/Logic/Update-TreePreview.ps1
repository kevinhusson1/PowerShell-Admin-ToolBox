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

        # 3. Utilisation de la logique UNIFIÉE (via New-BuilderTreeItem)
        # Plus besoin de fonction locale New-VisuItem, on appelle directement la globale.

        foreach ($rootNode in $rootList) {
            # On passe les remplacements pour qu'ils soient appliqués
            $tvItem = New-BuilderTreeItem -NodeData $rootNode -Replacements $replacements
            if ($tvItem) {
                $TreeView.Items.Add($tvItem) | Out-Null
            }
        }

    }
    catch {
        Write-Verbose "Erreur Preview TreeView : $_"
    }
}