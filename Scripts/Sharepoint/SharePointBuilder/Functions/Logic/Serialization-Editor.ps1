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
            $linkHash = @{
                Type = "Link"
                Name = $data.Name
                Url  = $data.Url
                Tags = @()
            }
            # Capture Tags
            foreach ($child in $Item.Items) {
                if ($child.Tag.Type -eq "Tag") {
                    $linkHash.Tags += @{ 
                        Name = $child.Tag.Name; Value = $child.Tag.Value
                        IsDynamic = $child.Tag.IsDynamic; SourceForm = $child.Tag.SourceForm; SourceVar = $child.Tag.SourceVar
                    }
                }
            }
            return $linkHash
        }
        
        # 2. CAS PUBLICATION
        if ($data.Type -eq "Publication") {
            $pubHash = @{
                Type             = "Publication"
                Name             = $data.Name
                TargetSiteMode   = $data.TargetSiteMode
                TargetSiteUrl    = $data.TargetSiteUrl
                TargetFolderPath = $data.TargetFolderPath
                UseModelName     = $data.UseModelName
                UseFormMetadata  = $data.UseFormMetadata
                GrantUser        = $data.GrantUser
                GrantLevel       = $data.GrantLevel
                Tags             = @()
            }
            # Capture Tags
            foreach ($child in $Item.Items) {
                if ($child.Tag.Type -eq "Tag") {
                    $pubHash.Tags += @{ 
                        Name = $child.Tag.Name; Value = $child.Tag.Value 
                        IsDynamic = $child.Tag.IsDynamic; SourceForm = $child.Tag.SourceForm; SourceVar = $child.Tag.SourceVar
                    }
                }
            }
            return $pubHash
        }

        # 2.5 CAS LIEN INTERNE (NOUVEAU)
        if ($data.Type -eq "InternalLink") {
            $iLinkHash = @{
                Type         = "InternalLink"
                Name         = $data.Name
                TargetNodeId = $data.TargetNodeId
                Tags         = @()
            }
            # Capture Tags
            foreach ($child in $Item.Items) {
                if ($child.Tag.Type -eq "Tag") {
                    $iLinkHash.Tags += @{ 
                        Name = $child.Tag.Name; Value = $child.Tag.Value 
                        IsDynamic = $child.Tag.IsDynamic; SourceForm = $child.Tag.SourceForm; SourceVar = $child.Tag.SourceVar
                    }
                }
            }
            return $iLinkHash
        }

        # 3. CAS DOSSIER
        # On construit une Hashtable propre pour le JSON
        $nodeHash = @{
            Name        = $data.Name
            Id          = $data.Id
            Permissions = @()
            Tags        = @()
            Folders     = @()
        }

        # Récursion sur les enfants visuels
        foreach ($childItem in $Item.Items) {
            $childData = $childItem.Tag
            
            # Gestion Types Enfants
            if ($childData.Type -eq "Permission") {
                $nodeHash.Permissions += @{
                    Email = $childData.Email
                    Level = $childData.Level
                }
            }
            elseif ($childData.Type -eq "Tag") {
                $nodeHash.Tags += @{
                    Name = $childData.Name
                    Value = $childData.Value
                    IsDynamic = $childData.IsDynamic; SourceForm = $childData.SourceForm; SourceVar = $childData.SourceVar
                }
            }
            else {
                # Dossier / Lien / Pub / InternalLink -> Folders List
                $nodeHash.Folders += Get-NodeData -Item $childItem
            }
        }
        
        return $nodeHash
    }

    $rootList = @()
    foreach ($rootItem in $TreeView.Items) {
        $rootList += Get-NodeData -Item $rootItem
    }

    $finalObj = @{ Folders = $rootList }
    return $finalObj | ConvertTo-Json -Depth 10 -Compress
}

function Global:Convert-JsonToEditorTree {
    param(
        [string]$Json, 
        [System.Windows.Controls.TreeView]$TreeView
    )

    $TreeView.Items.Clear()
    if ([string]::IsNullOrWhiteSpace($Json)) { return }

    try {
        $structure = $Json | ConvertFrom-Json
        $folders = if ($structure.Folders) { $structure.Folders } else { @($structure) }

        foreach ($f in $folders) {
            # Utilisation de la logique partagée (Replacements = null car éditeur = brut)
            $rootNode = New-BuilderTreeItem -NodeData $f
            if ($rootNode) {
                $TreeView.Items.Add($rootNode) | Out-Null
            }
        }
    }
    catch {
        Write-Warning "Erreur déserialisation JSON : $_"
    }
}