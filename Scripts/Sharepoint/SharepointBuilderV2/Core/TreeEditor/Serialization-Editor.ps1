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

    # Variables globales au script pour capturer les éléments plats
    $script:GlobalPubs = @()
    $script:GlobalLinks = @()
    $script:GlobalInternalLinks = @()
    $script:GlobalFiles = @()

    function Get-NodeData {
        param($Item, [string]$ParentGuid, [string]$CurrentPath)
        
        $data = $Item.Tag
        $cleanPath = $CurrentPath.TrimEnd('/')
        
        # 1. CAS LIEN
        if ($data.Type -eq "Link") {
            $fullPath = "$cleanPath/$($data.Name)".TrimStart('/')
            $relPath = "/$fullPath.url"
            if ($data.PSObject.Properties.Match('RelativePath').Count -gt 0) { $data.RelativePath = $relPath }
            $linkHash = @{
                Type         = "Link"
                Id           = $data.Id
                ParentId     = $ParentGuid
                RelativePath = $relPath
                Name         = $data.Name
                Url          = $data.Url
                Tags         = @()
            }
            foreach ($child in $Item.Items) {
                if ($child.Tag.Type -eq "Tag") {
                    $linkHash.Tags += @{ Name = $child.Tag.Name; Value = $child.Tag.Value; IsDynamic = $child.Tag.IsDynamic; SourceForm = $child.Tag.SourceForm; SourceVar = $child.Tag.SourceVar }
                }
            }
            $script:GlobalLinks += $linkHash
            return $null # Ne retourne rien pour l'arbre Folders
        }
        
        # 2. CAS PUBLICATION
        if ($data.Type -eq "Publication") {
            $targetPathPrep = if ($data.TargetFolderPath) { $data.TargetFolderPath.TrimEnd('/') } else { "" }
            $modelSuffix = if ($data.UseFormName) { "/{FormFolderName}/$($data.Name).url" } else { "/$($data.Name).url" }
            
            # Nettoyage à la volée des URLs SharePoint complexes collées par l'utilisateur
            $cleanSiteUrl = $data.TargetSiteUrl
            if (-not [string]::IsNullOrWhiteSpace($cleanSiteUrl)) {
                if ($cleanSiteUrl -match "id=([^&]+)") {
                    # Cas AllItems.aspx?id=...
                    try {
                        $uri = [System.Uri]$cleanSiteUrl
                        $decodedId = [uri]::UnescapeDataString($matches[1])
                        $cleanSiteUrl = "https://$($uri.Host)$decodedId"
                    }
                    catch {}
                }
                elseif ($cleanSiteUrl -match "^(https?://[^/]+)/:[a-zA-Z]:/[a-zA-Z]/(.+)") {
                    # Cas /:f:/r/sites/...
                    $hostUrl = $matches[1]
                    $restOfUrl = $matches[2]
                    if ($restOfUrl -match "^([^?]+)") { $restOfUrl = $matches[1] }
                    $cleanSiteUrl = [uri]::UnescapeDataString("$hostUrl/$restOfUrl")
                }
                elseif ($cleanSiteUrl -match "^(https?://[^?]+)") {
                    # Regex basique pour virer tous les query ?param=
                    $cleanSiteUrl = [uri]::UnescapeDataString($matches[1])
                }
                
                # Mise à jour silencieuse de l'objet UI pour conserver la propreté en mémoire
                $data.TargetSiteUrl = $cleanSiteUrl
            }

            if ($data.TargetSiteMode -eq "Auto" -or [string]::IsNullOrWhiteSpace($cleanSiteUrl)) {
                $relPath = "$targetPathPrep$modelSuffix"
            }
            else {
                $sitePrep = $cleanSiteUrl.TrimEnd('/')
                $relPath = "$sitePrep$targetPathPrep$modelSuffix"
            }
            if ($data.PSObject.Properties.Match('RelativePath').Count -gt 0) { $data.RelativePath = $relPath }
            $pubHash = @{
                Type             = "Publication"
                Id               = $data.Id
                ParentId         = $ParentGuid
                RelativePath     = $relPath
                Name             = $data.Name
                TargetSiteMode   = $data.TargetSiteMode
                TargetSiteUrl    = $data.TargetSiteUrl
                TargetFolderPath = $data.TargetFolderPath
                UseFormName      = $data.UseFormName
                UseFormMetadata  = $data.UseFormMetadata
                Permissions      = @()
                Tags             = @()
            }
            foreach ($child in $Item.Items) {
                if ($child.Tag.Type -eq "Tag") {
                    $pubHash.Tags += @{ Name = $child.Tag.Name; Value = $child.Tag.Value; IsDynamic = $child.Tag.IsDynamic; SourceForm = $child.Tag.SourceForm; SourceVar = $child.Tag.SourceVar }
                }
                elseif ($child.Tag.Type -eq "Permission") {
                    $pubHash.Permissions += @{ Email = $child.Tag.Email; Level = $child.Tag.Level }
                }
            }
            $script:GlobalPubs += $pubHash
            return $null
        }

        # 3. CAS LIEN INTERNE
        if ($data.Type -eq "InternalLink") {
            $fullPath = "$cleanPath/$($data.Name)".TrimStart('/')
            $relPath = "/$fullPath.url"
            if ($data.PSObject.Properties.Match('RelativePath').Count -gt 0) { $data.RelativePath = $relPath }
            $iLinkHash = @{
                Type         = "InternalLink"
                Id           = $data.Id
                ParentId     = $ParentGuid
                RelativePath = $relPath
                Name         = $data.Name
                TargetNodeId = $data.TargetNodeId
                Tags         = @()
            }
            foreach ($child in $Item.Items) {
                if ($child.Tag.Type -eq "Tag") {
                    $iLinkHash.Tags += @{ Name = $child.Tag.Name; Value = $child.Tag.Value; IsDynamic = $child.Tag.IsDynamic; SourceForm = $child.Tag.SourceForm; SourceVar = $child.Tag.SourceVar }
                }
            }
            $script:GlobalInternalLinks += $iLinkHash
            return $null
        }

        # 4. CAS FICHIER
        if ($data.Type -eq "File") {
            $fullPath = "$cleanPath/$($data.Name)".TrimStart('/')
            $relPath = "/$fullPath"
            if ($data.PSObject.Properties.Match('RelativePath').Count -gt 0) { $data.RelativePath = $relPath }
            $fileHash = @{
                Type         = "File"
                Id           = $data.Id
                ParentId     = $ParentGuid
                RelativePath = $relPath
                Name         = $data.Name
                SourceUrl    = $data.SourceUrl
                Permissions  = @()
                Tags         = @()
            }
            foreach ($child in $Item.Items) {
                if ($child.Tag.Type -eq "Tag") {
                    $fileHash.Tags += @{ Name = $child.Tag.Name; Value = $child.Tag.Value; IsDynamic = $child.Tag.IsDynamic; SourceForm = $child.Tag.SourceForm; SourceVar = $child.Tag.SourceVar }
                }
                elseif ($child.Tag.Type -eq "Permission") {
                    $fileHash.Permissions += @{ Email = $child.Tag.Email; Level = $child.Tag.Level }
                }
            }
            $script:GlobalFiles += $fileHash
            return $null
        }

        # 5. CAS DOSSIER (On retourne le noeud pour construire l'arbre)
        $newPath = "$cleanPath/$($data.Name)"
        $relPath = if ($newPath -eq "/") { "/" } else { "/$($newPath.Trim('/'))" }
        if ($data.PSObject.Properties.Match('RelativePath').Count -gt 0) { $data.RelativePath = $relPath }

        $nodeHash = @{
            Type         = "Folder"
            Name         = $data.Name
            Id           = $data.Id
            RelativePath = $relPath
            Permissions  = @()
            Tags         = @()
            Folders      = @()
        }

        foreach ($childItem in $Item.Items) {
            $childData = $childItem.Tag
            if ($childData.Type -eq "Permission") {
                $nodeHash.Permissions += @{ Email = $childData.Email; Level = $childData.Level }
            }
            elseif ($childData.Type -eq "Tag") {
                $nodeHash.Tags += @{ Name = $childData.Name; Value = $childData.Value; IsDynamic = $childData.IsDynamic; SourceForm = $childData.SourceForm; SourceVar = $childData.SourceVar }
            }
            else {
                # C'est un sous-noeud (Dossier, Pub, Lien...), on le traite
                $childObj = Get-NodeData -Item $childItem -ParentGuid $data.Id -CurrentPath $newPath
                if ($childObj) {
                    $nodeHash.Folders += $childObj
                }
            }
        }
        
        return $nodeHash
    }

    $rootList = @()
    # "Root" n'a pas de ParentId, le chemin commence à la racine (vide)
    foreach ($rootItem in $TreeView.Items) {
        $node = Get-NodeData -Item $rootItem -ParentGuid "" -CurrentPath ""
        if ($node) { $rootList += $node }
    }

    $finalObj = [Ordered]@{ 
        TargetSchemaId = $TargetSchemaId
        TargetFormId   = $TargetFormId
        Folders        = $rootList
        Publications   = $script:GlobalPubs
        Links          = $script:GlobalLinks
        InternalLinks  = $script:GlobalInternalLinks
        Files          = $script:GlobalFiles
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