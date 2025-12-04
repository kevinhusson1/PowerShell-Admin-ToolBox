# Scripts/SharePoint/SharePointBuilder/Functions/Logic/Serialization-Editor.ps1

# 1. TREEVIEW -> JSON (Sauvegarde)
function Global:Convert-EditorTreeToJson {
    param([System.Windows.Controls.TreeView]$TreeView)

    function Get-NodeData {
        param($Item)
        
        # On récupère les données brutes de l'objet
        $data = $Item.Tag
        
        # On construit une Hashtable propre pour le JSON
        $nodeHash = @{
            Name        = $data.Name
            Permissions = $data.Permissions
            Tags        = $data.Tags
            Links       = $data.Links
            Folders     = @()
        }

        # Récursion sur les enfants visuels
        foreach ($childItem in $Item.Items) {
            $nodeHash.Folders += Get-NodeData -Item $childItem
        }
        
        return $nodeHash
    }

    $rootList = @()
    foreach ($rootItem in $TreeView.Items) {
        $rootList += Get-NodeData -Item $rootItem
    }

    # On encapsule dans une structure standard
    $finalObj = @{ Folders = $rootList }
    
    return $finalObj | ConvertTo-Json -Depth 10 -Compress
}

# 2. JSON -> TREEVIEW (Chargement)
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
            
            # Links
            if ($Data.Links) {
                $newItem.Tag.Links = [System.Collections.Generic.List[psobject]]::new()
                foreach ($l in $Data.Links) { 
                    $newItem.Tag.Links.Add([PSCustomObject]@{ Name = $l.Name; Url = $l.Url }) 
                }
            }

            # Mise à jour des badges
            Update-EditorBadges -TreeItem $newItem

            # Récursion Enfants
            if ($Data.Folders) {
                foreach ($sub in $Data.Folders) {
                    $subItem = Build-Node -Data $sub
                    $newItem.Items.Add($subItem) | Out-Null
                }
            }

            return $newItem
        }

        foreach ($f in $folders) {
            $rootNode = Build-Node -Data $f
            $TreeView.Items.Add($rootNode) | Out-Null
        }

    }
    catch {
        Write-Warning "Erreur déserialisation JSON : $_"
    }
}