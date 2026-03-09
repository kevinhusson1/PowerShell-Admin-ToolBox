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

    # Dictionnaire pour mapper ID -> TreeViewItem Visuel (Passe 1)
    $nodeMap = @{}

    # --- PASSE 1 : Construction du Squelette (Folders) ---
    function Add-AppSPFolderToTree {
        param($NodeData, $ParentUICollection)
        
        $rootNode = New-BuilderTreeItem -NodeData $NodeData -Replacements $Replacements
        if ($rootNode) {
            $ParentUICollection.Add($rootNode) | Out-Null
            
            $nodeId = $rootNode.Tag.Id
            if ($nodeId) { $nodeMap[$nodeId] = $rootNode }

            function Get-AppSPChildrenRecursive {
                param($parentItem)
                foreach ($child in $parentItem.Items) {
                    if ($child.Tag.Type -eq "Folder" -and $child.Tag.Id) {
                        $nodeMap[$child.Tag.Id] = $child
                        Get-AppSPChildrenRecursive -parentItem $child
                    }
                }
            }
            Get-AppSPChildrenRecursive -parentItem $rootNode
        }
    }

    $folders = if ($Structure.Folders) { $Structure.Folders } else { @() }
    foreach ($f in $folders) {
        Add-AppSPFolderToTree -NodeData $f -ParentUICollection $TreeViewItems
    }

    # --- PASSE 2 : Habillage (Publications, Links, InternalLinks, Files) ---
    $flatCollections = @($Structure.Publications, $Structure.Links, $Structure.InternalLinks, $Structure.Files)
    
    foreach ($collection in $flatCollections) {
        if ($null -ne $collection) {
            foreach ($itemData in $collection) {
                $leafNode = New-BuilderTreeItem -NodeData $itemData -Replacements $Replacements
                if ($leafNode) {
                    $parentId = $itemData.ParentId
                    if ([string]::IsNullOrWhiteSpace($parentId)) {
                        # Racine
                        $TreeViewItems.Add($leafNode) | Out-Null
                    }
                    elseif ($nodeMap.ContainsKey($parentId)) {
                        # Ajout au parent correct
                        $parentNode = $nodeMap[$parentId]
                        $parentNode.Items.Add($leafNode) | Out-Null
                        
                        # Mise à jour des badges du parent (Important pour le visuel)
                        if (Get-Command Update-EditorBadges -ErrorAction SilentlyContinue) {
                            Update-EditorBadges -TreeItem $parentNode
                        }
                    }
                }
            }
        }
    }
}
