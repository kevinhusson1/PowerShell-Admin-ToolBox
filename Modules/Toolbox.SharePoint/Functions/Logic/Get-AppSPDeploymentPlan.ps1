# Modules/Toolbox.SharePoint/Functions/Logic/Get-AppSPDeploymentPlan.ps1

<#
.SYNOPSIS
    Prépare un plan de déploiement SharePoint à partir d'une structure JSON.
.DESCRIPTION
    Analyse le JSON (hiérarchique ou plat), résout les variables dynamiques (FormValues)
    et génère une liste ordonnée d'opérations à effectuer.
#>
function Get-AppSPDeploymentPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$StructureJson,
        [Parameter(Mandatory = $false)] [hashtable]$FormValues,
        [Parameter(Mandatory = $false)] [hashtable]$RootMetadata
    )

    $structure = $StructureJson | ConvertFrom-Json
    $plan = [System.Collections.Generic.List[psobject]]::new()
    
    # Cache pour la résolution des chemins
    $IdToPathMap = @{}

    # --- ÉTAPE 1 : RÉSOLUTION DYNAMIQUE DES TAGS ---
    function Resolve-Tags {
        param($TagsConfig)
        if (-not $TagsConfig) { return $null }
        $resolved = [System.Collections.Generic.List[psobject]]::new()
        
        foreach ($t in $TagsConfig) {
            $val = $null
            if ($t.IsDynamic -and $FormValues -and $t.SourceVar) {
                $val = $FormValues[$t.SourceVar]
            }
            else {
                $val = if ($t.Value) { $t.Value } else { $t.Term }
            }
            
            if ($null -ne $val -and $val -ne "") {
                $resolved.Add([PSCustomObject]@{ Name = $t.Name; Value = $val })
            }
        }
        return $resolved
    }

    # --- ÉTAPE 2 : PARCOURS DE LA STRUCTURE ---
    function Process-Node {
        param($Node, $ParentPath, $ParentId)
        
        if ($Node -is [array]) {
            foreach ($n in $Node) { Process-Node -Node $n -ParentPath $ParentPath -ParentId $ParentId }
            return
        }

        $nodeId = $Node.Id
        $nodeName = $Node.Name
        $type = if ($Node.Type) { $Node.Type } else { "Folder" }
        $currentPath = if ($ParentPath -eq "/") { "/$nodeName" } else { "$ParentPath/$nodeName" }

        # Enregistrement pour les liens internes
        if ($nodeId) { $IdToPathMap[$nodeId] = $currentPath }

        # Création de l'opération
        $op = [PSCustomObject]@{
            Action      = "Create"
            Type        = $type
            Id          = $nodeId
            Name        = $nodeName
            ParentId    = $ParentId
            Path        = $currentPath
            Tags        = Resolve-Tags -TagsConfig $Node.Tags
            Permissions = $Node.Permissions
            RawNode     = $Node # Pour les propriétés spécifiques (Url, SourceUrl, etc.)
        }
        $plan.Add($op)

        # Récursion pour les dossiers
        if ($Node.Folders) {
            Process-Node -Node $Node.Folders -ParentPath $currentPath -ParentId $nodeId
        }
    }

    # Lancement du parcours
    if ($structure.Folders) {
        Process-Node -Node $structure.Folders -ParentPath "/" -ParentId "root"
    }
    else {
        # Cas Flat JSON ou objet unique racine
        Process-Node -Node $structure -ParentPath "/" -ParentId "root"
    }

    # --- ÉTAPE 3 : POST-PROCESSING (Liens Internes, Publications) ---
    foreach ($op in $plan) {
        if ($op.Type -eq "InternalLink") {
            $targetId = $op.RawNode.TargetNodeId
            if ($IdToPathMap.ContainsKey($targetId)) {
                $op.TargetPath = $IdToPathMap[$targetId]
            }
        }
    }

    return $plan
}
