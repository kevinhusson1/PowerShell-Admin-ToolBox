<#
.SYNOPSIS
    Recherche des éléments (dossiers/fichiers) dans une liste SharePoint en filtrant par métadonnées (Tags).

.DESCRIPTION
    Interroge Microsoft Graph pour récupérer les éléments d'une liste avec leurs champs étendus ($expand=fields).
    Effectue ensuite un filtrage côté client basé sur la hashtable de filtres passée en paramètre.

.PARAMETER SiteId
    L'identifiant unique (ID) du site SharePoint.

.PARAMETER ListId
    L'identifiant unique (GUID) de la liste SharePoint.

.PARAMETER TagFilters
    Une table de hachage (hashtable) contenant les couples NomDuChamp = ValeurAttendue.

.EXAMPLE
    Find-AppGraphFolderByTag -SiteId "..." -ListId "..." -TagFilters @{ "ProjectCode" = "PROJ001"; "NodeType" = "Root" }
#>
function Find-AppGraphFolderByTag {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$SiteId,
        [Parameter(Mandatory=$true)]
        [string]$ListId,
        [Parameter(Mandatory=$true)]
        [hashtable]$TagFilters
    )
    process {
        Write-Verbose "[Find-AppGraphFolderByTag] Recherche de dossiers avec les tags spécifiés dans la liste $ListId..."
        
        try {
            # Récupere tous les éléments avec leurs métadonnées
            $itemsUrl = "https://graph.microsoft.com/v1.0/sites/$SiteId/lists/$ListId/items?`$expand=fields"
            $response = Invoke-MgGraphRequest -Method GET -Uri $itemsUrl -ErrorAction Stop
            $allItems = $response.value
            
            $matchItems = @()
            
            foreach ($item in $allItems) {
                if ($null -ne $item.fields) {
                    $isMatch = $true
                    foreach ($key in $TagFilters.Keys) {
                        # Si le champ n'existe pas ou ne correspond pas à la valeur attendue
                        if ($item.fields.$key -ne $TagFilters[$key]) {
                            $isMatch = $false
                            break
                        }
                    }
                    if ($isMatch) {
                        $matchItems += $item
                    }
                }
            }
            
            return $matchItems
            
        } catch {
            Write-Error "Échec de la recherche de dossiers par Tag : $($_.Exception.Message)"
            if ($_.ErrorDetails) { Write-Error "Détails API : $($_.ErrorDetails.Message)" }
            throw $_
        }
    }
}
