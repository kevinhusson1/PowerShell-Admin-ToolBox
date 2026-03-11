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
    param(
        [System.Windows.Controls.TreeView]$TreeView,
        [string]$TargetSchemaId = "",
        [string]$TargetFormId = ""
    )

    function Get-NodeData {
        param($Item, $ParentPath = "")
        
        $data = $Item.Tag
        $nodeName = $data.Name
        
        $currentPath = if ($data.Type -eq "Publication" -and $data.UseFormMetadata) {
            if ([string]::IsNullOrWhiteSpace($ParentPath) -or $ParentPath -eq "/") { "/{formDestination}/$nodeName" } else { "$ParentPath/{formDestination}/$nodeName" }
        }
        else {
            if ([string]::IsNullOrWhiteSpace($ParentPath) -or $ParentPath -eq "/") { "/$nodeName" } else { "$ParentPath/$nodeName" }
        }
        
        # Suffixe .url pour les types de fichiers/liens/publications
        if ($data.Type -match "Link|Publication" -and $currentPath -notmatch "\.url$") {
            $currentPath += ".url"
        }

        # Initialisation de l'objet de base
        $hash = [Ordered]@{
            Type         = $data.Type
            Id           = $data.Id
            Name         = $nodeName
            RelativePath = $currentPath
        }

        # Propriétés spécifiques par type
        switch ($data.Type) {
            "Link" {
                $hash.Url = if ($data.Url) { $data.Url } else { "" }
            }
            "Publication" {
                $hash.TargetSiteMode = if ($data.TargetSiteMode) { $data.TargetSiteMode } else { "Auto" }
                $hash.TargetSiteUrl = if ($data.TargetSiteUrl) { $data.TargetSiteUrl } else { "" }
                $hash.TargetFolderPath = if ($data.TargetFolderPath) { $data.TargetFolderPath } else { "" }
                $hash.UseFormName = if ($null -ne $data.UseFormName) { [bool]$data.UseFormName } else { $true }
                $hash.UseFormMetadata = if ($null -ne $data.UseFormMetadata) { [bool]$data.UseFormMetadata } else { $false }
                $hash.Permissions = @()
            }
            "InternalLink" {
                $hash.TargetNodeId = if ($data.TargetNodeId) { $data.TargetNodeId } else { "" }
                # Pour les liens internes, le nom est souvent (.url)
                if ($hash.Name -notmatch "\.url$") { $hash.RelativePath = "$currentPath.url" }
            }
            "File" {
                $hash.SourceUrl = if ($data.SourceUrl) { $data.SourceUrl } else { "" }
                $hash.Permissions = @()
            }
            "Folder" {
                $hash.Permissions = @()
            }
        }

        # Tags et Enfants (Récursif)
        $hash.Tags = @()
        $hash.Children = @()

        foreach ($childItem in $Item.Items) {
            $childData = $childItem.Tag
            
            if ($childData.Type -eq "Permission") {
                # Les permissions s'ajoutent à l'objet courant s'il les supporte
                # FIX: [Ordered] hashtable uses .Contains() instead of .ContainsKey() in some PS contexts
                if ($hash.Contains('Permissions')) {
                    $hash.Permissions += @{ Email = $childData.Email; Level = $childData.Level }
                }
            }
            elseif ($childData.Type -eq "Tag") {
                $hash.Tags += @{ 
                    Name       = $childData.Name
                    Value      = $childData.Value
                    IsDynamic  = $childData.IsDynamic
                    SourceForm = $childData.SourceForm
                    SourceVar  = $childData.SourceVar 
                }
            }
            else {
                # C'est un sous-noeud (Dossier, Pub, Lien, Fichier), on récycle
                $childObj = Get-NodeData -Item $childItem -ParentPath $currentPath
                if ($childObj) { $hash.Children += $childObj }
            }
        }
        
        return $hash
    }

    $rootList = @()
    foreach ($rootItem in $TreeView.Items) {
        $node = Get-NodeData -Item $rootItem
        if ($node) { $rootList += $node }
    }

    $finalObj = [Ordered]@{ 
        TargetSchemaId = $TargetSchemaId
        TargetFormId   = $TargetFormId
        Children       = $rootList
    }
    
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
        
        # Utilisation de la logique UNIFIÉE (via Invoke-AppSPReassembleTree)
        Invoke-AppSPReassembleTree -Structure $structure -TreeViewItems $TreeView.Items -Replacements $null
    }
    catch {
        Write-Warning "Erreur déserialisation JSON : $_"
    }
}