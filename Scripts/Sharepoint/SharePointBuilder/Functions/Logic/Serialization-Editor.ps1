# Scripts/SharePoint/SharePointBuilder/Functions/Logic/Serialization-Editor.ps1

# 1. TREEVIEW -> JSON (Sauvegarde)
<#
.SYNOPSIS
    Sérialise le contenu du TreeView d'édition en JSON.

.DESCRIPTION
    Parcourt l'arbre visuel, extrait les objets de données (Tag) de chaque noeud (Dossier, Permissions, etc.)
    et construit une structure hiérarchique propre compatible avec le schéma de base de données.
    Ignore les éléments purement visuels (MetaItems).

.PARAMETER TreeView
    Le contrôle TreeView source.

.OUTPUTS
    [string] La représentation JSON de la structure.
#>
function Global:Convert-EditorTreeToJson {
    param([System.Windows.Controls.TreeView]$TreeView)

    function Get-NodeData {
        param($Item)
        
        # On récupère les données brutes de l'objet
        $data = $Item.Tag
        
        # 1. CAS LIEN
        if ($data.Type -eq "Link") {
            return @{
                Type = "Link"
                Name = $data.Name
                Url  = $data.Url
            }
        }

        # 2. CAS DOSSIER
        # On construit une Hashtable propre pour le JSON
        $nodeHash = @{
            Name        = $data.Name
            Permissions = $data.Permissions
            Tags        = $data.Tags
            Folders     = @()
        }

        # Récursion sur les enfants visuels
        foreach ($childItem in $Item.Items) {
            # FIX: Ignorer les métadonnées visuelles (qui sont dans le TreeView pour l'édition)
            if ($childItem.Name -eq "MetaItem") { continue }

            $nodeHash.Folders += Get-NodeData -Item $childItem
        }
        
        return $nodeHash
    }

    $rootList = @()
    $rootList = @()
    foreach ($rootItem in $TreeView.Items) {
        # Support pour les Liens à la racine (Type = Link)
        if ($rootItem.Name -eq "MetaItem" -and $rootItem.Tag -and $rootItem.Tag.PSObject.Properties['Url']) {
            $rootList += @{
                Type = "Link"
                Name = $rootItem.Tag.Name
                Url  = $rootItem.Tag.Url
            }
        }
        else {
            $rootList += Get-NodeData -Item $rootItem
        }
    }

    # On encapsule dans une structure standard
    $finalObj = @{ Folders = $rootList }
    
    return $finalObj | ConvertTo-Json -Depth 10 -Compress
}

# 2. JSON -> TREEVIEW (Chargement)
<#
.SYNOPSIS
    Reconstruit l'arbre visuel d'édition à partir d'un JSON.

.DESCRIPTION
    Désérialise le JSON et récrée récursivement les noeuds du TreeView (Nodes, Badges, Metadata)
    en utilisant les fonctions New-EditorNode et Update-EditorBadges.

.PARAMETER Json
    La chaîne JSON source.

.PARAMETER TreeView
    Le contrôle TreeView cible (sera vidé avant le chargement).
#>
function Global:Convert-JsonToEditorTree {
    param(
        [string]$Json, 
        [System.Windows.Controls.TreeView]$TreeView
    )

    $TreeView.Items.Clear()
    if ([string]::IsNullOrWhiteSpace($Json)) { return }

    try {
        $structure = $Json | ConvertFrom-Json
        
        # Gestion de la racine (Array ou Object)
        $folders = if ($structure.Folders) { $structure.Folders } else { @($structure) }

        function Build-Node {
            param($Data)
            
            # Création Visuelle
            $newItem = New-EditorNode -Name $Data.Name
            
            # Hydratation des Données
            # Note : ConvertFrom-Json crée des PSCustomObject, on doit parfois les caster
            
            # Permissions
            if ($Data.Permissions) {
                $newItem.Tag.Permissions = [System.Collections.Generic.List[psobject]]::new()
                foreach ($p in $Data.Permissions) { 
                    $newItem.Tag.Permissions.Add([PSCustomObject]@{ Email = $p.Email; Level = $p.Level }) 
                }
            }
            
            # Tags
            if ($Data.Tags) {
                $newItem.Tag.Tags = [System.Collections.Generic.List[psobject]]::new()
                foreach ($t in $Data.Tags) { 
                    $newItem.Tag.Tags.Add([PSCustomObject]@{ Name = $t.Name; Value = $t.Value }) 
                }
            }
            
            # Mise à jour des badges
            Update-EditorBadges -TreeItem $newItem

            # Récursion Enfants
            if ($Data.Folders) {
                foreach ($sub in $Data.Folders) {
                    if ($sub.Type -eq "Link") {
                        $subItem = New-EditorLinkNode -Name $sub.Name -Url $sub.Url
                    }
                    else {
                        $subItem = Build-Node -Data $sub
                    }
                    $newItem.Items.Add($subItem) | Out-Null
                }
            }

            return $newItem
        }

        foreach ($f in $folders) {
            if ($f.Type -eq "Link") {
                $rootNode = New-EditorLinkNode -Name $f.Name -Url $f.Url
            }
            else {
                $rootNode = Build-Node -Data $f
            }
            $TreeView.Items.Add($rootNode) | Out-Null
        }
    }
    catch {
        Write-Warning "Erreur déserialisation JSON : $_"
    }
}