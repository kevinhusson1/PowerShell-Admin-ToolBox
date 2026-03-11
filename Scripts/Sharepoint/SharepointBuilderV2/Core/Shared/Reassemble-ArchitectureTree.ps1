<#
.SYNOPSIS
    Reconstruit une hiérarchie de TreeViewItems à partir d'un JSON à plat.
    
.DESCRIPTION
    Cette fonction unifie le chargement des modèles entre l'Éditeur et l'onglet Déploiement.
    Elle gère le format "Flat" (Collections à la racine avec ParentId).
    
    Processus en deux passes :
    1. Reconstruction du squelette des dossiers (Folders).
    2. Attachement des autres éléments (Publications, Files, Links) à leurs parents via ParentId.

.PARAMETER Structure
    L'objet déserialisé (PSCustomObject) contenant Folders, Publications, Files, etc.
    
.PARAMETER TreeViewItems
    La collection d'items où ajouter les racines (ex: $TreeView.Items).
    
.PARAMETER Replacements
    [Optionnel] Hashtable pour le remplacement des variables (Preview Mode).
#>
function Global:Invoke-AppSPReassembleTree {
    param(
        [psobject]$Structure,
        [System.Windows.Controls.ItemCollection]$TreeViewItems,
        [hashtable]$Replacements = $null
    )

    if (-not $Structure) { return }
    $TreeViewItems.Clear()

    # Dictionnaire pour mapper ID -> TreeViewItem Visuel (Nécessaire pour le format FLAT legacy)
    $nodeMap = @{}

    # --- ÉTAPE 1 : NOEUDS RACINES (UNIFIÉ OU FOLDERS) ---
    $roots = if ($Structure.Children) { $Structure.Children } else { $Structure.Folders }
    
    foreach ($rData in $roots) {
        $rootNode = New-BuilderTreeItem -NodeData $rData -Replacements $Replacements
        if ($rootNode) {
            $TreeViewItems.Add($rootNode) | Out-Null
            
            # Pour le format FLAT, on indexe récursivement les dossiers créés
            if ($null -ne $Structure.Links -or $null -ne $Structure.Files -or $null -ne $Structure.Publications) {
                function Get-AppSPChildrenRecursive {
                    param($parentItem)
                    if ($parentItem.Tag.Id) { $nodeMap[$parentItem.Tag.Id] = $parentItem }
                    foreach ($child in $parentItem.Items) {
                        if ($child.Tag.Type -eq "Folder") { Get-AppSPChildrenRecursive -parentItem $child }
                    }
                }
                Get-AppSPChildrenRecursive -parentItem $rootNode
            }
        }
    }

    # --- ÉTAPE 2 : HABILLAGE (COMPATIBILITÉ FLAT LEGACY) ---
    # Si des collections plates existent, on les rattache à leurs parents via ParentId
    $flatCollections = @($Structure.Publications, $Structure.Links, $Structure.InternalLinks, $Structure.Files)
    foreach ($collection in $flatCollections) {
        if ($null -ne $collection) {
            foreach ($itemData in $collection) {
                $leafNode = New-BuilderTreeItem -NodeData $itemData -Replacements $Replacements
                if ($leafNode) {
                    $parentId = $itemData.ParentId
                    if ([string]::IsNullOrWhiteSpace($parentId)) {
                        $TreeViewItems.Add($leafNode) | Out-Null
                    }
                    elseif ($nodeMap.ContainsKey($parentId)) {
                        $nodeMap[$parentId].Items.Add($leafNode) | Out-Null
                        if (Get-Command Update-EditorBadges -ErrorAction SilentlyContinue) {
                            Update-EditorBadges -TreeItem $nodeMap[$parentId]
                        }
                    }
                }
            }
        }
    }
}
