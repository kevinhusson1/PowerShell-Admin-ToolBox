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
        
        # 2. CAS PUBLICATION
        if ($data.Type -eq "Publication") {
            return @{
                Type             = "Publication"
                Name             = $data.Name
                TargetSiteMode   = $data.TargetSiteMode
                TargetSiteUrl    = $data.TargetSiteUrl
                TargetFolderPath = $data.TargetFolderPath
                UseModelName     = $data.UseModelName
                GrantUser        = $data.GrantUser
                GrantLevel       = $data.GrantLevel
            }
        }

        # 2.5 CAS LIEN INTERNE (NOUVEAU)
        if ($data.Type -eq "InternalLink") {
            return @{
                Type         = "InternalLink"
                Name         = $data.Name
                TargetNodeId = $data.TargetNodeId
            }
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
                    Name  = $childData.Name
                    Value = $childData.Value
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

        function Build-Node {
            param($Data)
            
            # Création Visuelle (Dossier par défaut via New-EditorNode)
            $newItem = New-EditorNode -Name $Data.Name
            if ($Data.Id) { $newItem.Tag.Id = $Data.Id }

            # Hydratation Enfants (Permissions / Tags / Sous-Dossiers)
            
            # Permissions -> Noeuds
            if ($Data.Permissions) {
                $newItem.Tag.Permissions = $null # On vide la liste data parent, on utilise les noeuds enfants
                foreach ($p in $Data.Permissions) { 
                    $pNode = New-EditorPermNode -Email $p.Email -Level $p.Level
                    $newItem.Items.Add($pNode) | Out-Null
                }
            }
            
            # Tags -> Noeuds
            if ($Data.Tags) {
                $newItem.Tag.Tags = $null # Idem
                foreach ($t in $Data.Tags) { 
                    $tNode = New-EditorTagNode -Name $t.Name -Value $t.Value
                    $newItem.Items.Add($tNode) | Out-Null
                }
            }
            
            # Récursion Dossiers/Liens/Pubs
            if ($Data.Folders) {
                foreach ($sub in $Data.Folders) {
                    if ($sub.Type -eq "Link") {
                        $subItem = New-EditorLinkNode -Name $sub.Name -Url $sub.Url
                        # Charge les Tags du Lien aussi !
                        if ($sub.Tags) {
                            foreach ($t in $sub.Tags) {
                                $tNode = New-EditorTagNode -Name $t.Name -Value $t.Value
                                $subItem.Items.Add($tNode) | Out-Null
                            }
                        }
                    }
                    elseif ($sub.Type -eq "Publication") {
                        $subItem = New-EditorPubNode -Name $sub.Name
                        $subItem.Tag.TargetSiteMode = $sub.TargetSiteMode
                        $subItem.Tag.TargetSiteUrl = $sub.TargetSiteUrl
                        $subItem.Tag.TargetFolderPath = $sub.TargetFolderPath
                        $subItem.Tag.UseModelName = $sub.UseModelName
                        $subItem.Tag.GrantUser = $sub.GrantUser
                        $subItem.Tag.GrantLevel = $sub.GrantLevel
                        # Charge les Tags de la Pub
                        if ($sub.Tags) {
                            foreach ($t in $sub.Tags) {
                                $tNode = New-EditorTagNode -Name $t.Name -Value $t.Value
                                $subItem.Items.Add($tNode) | Out-Null
                            }
                        }
                    }
                    elseif ($sub.Type -eq "InternalLink") {
                        $subItem = New-EditorInternalLinkNode -Name $sub.Name -TargetNodeId $sub.TargetNodeId
                        # Charge Tags InternalLink
                        if ($sub.Tags) {
                            foreach ($t in $sub.Tags) {
                                $tNode = New-EditorTagNode -Name $t.Name -Value $t.Value
                                $subItem.Items.Add($tNode) | Out-Null
                            }
                        }
                    }
                    else {
                        $subItem = Build-Node -Data $sub
                    }
                    $newItem.Items.Add($subItem) | Out-Null
                }
            }

            Update-EditorBadges -TreeItem $newItem
            return $newItem
        }

        foreach ($f in $folders) {
            # Note: A la racine, on ne supporte a priori que des Dossiers, mais si Link/Pub à la racine...
            if ($f.Type -eq "Link") { 
                $rootNode = New-EditorLinkNode -Name $f.Name -Url $f.Url 
                if ($f.Tags) { foreach ($t in $f.Tags) { $rootNode.Items.Add((New-EditorTagNode -Name $t.Name -Value $t.Value)) | Out-Null } }
            }
            # ... Cases for Pub/InternalLink at root ...
            else {
                $rootNode = Build-Node -Data $f
            }
            $TreeView.Items.Add($rootNode) | Out-Null
            Update-EditorBadges -TreeItem $rootNode
        }
    }
    catch {
        Write-Warning "Erreur déserialisation JSON : $_"
    }
}