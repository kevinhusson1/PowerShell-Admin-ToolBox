<#
.SYNOPSIS
    Crée ou récupère un Type de Contenu (Content Type) sur un site SharePoint et y attache des colonnes.

.DESCRIPTION
    Utilise l'endpoint Beta de Microsoft Graph pour gérer les Content Types de site.
    Si le Content Type n'existe pas, il est créé à partir d'un ID de base.
    Si une liste d'IDs de colonnes est fournie, la fonction les attache au Content Type (ODATA bind).

.PARAMETER SiteId
    L'identifiant unique (ID) du site SharePoint.

.PARAMETER Name
    Le nom du Content Type à créer/vérifier.

.PARAMETER Description
    La description du Content Type.

.PARAMETER Group
    Le nom du groupe de colonnes/content types dans lequel le classer.

.PARAMETER BaseId
    L'identifiant du Content Type parent (ex: 0x0120 pour un dossier).

.PARAMETER ColumnIdsToBind
    (Optionnel) Tableau d'IDs de colonnes de site à attacher à ce Content Type.

.EXAMPLE
    New-AppGraphContentType -SiteId "..." -Name "Dossier Avancé" -Group "IT" -BaseId "0x0120"
#>
function New-AppGraphContentType {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SiteId,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$Description,
        [Parameter(Mandatory = $true)]
        [string]$Group,
        [Parameter(Mandatory = $true)]
        [string]$BaseId,
        [Parameter(Mandatory = $false)]
        [string[]]$ColumnIdsToBind
    )
    process {
        Write-Verbose "[New-AppGraphContentType] Vérification du Content Type '$Name'..."
        $ctsUrl = "https://graph.microsoft.com/beta/sites/$SiteId/contentTypes"
        
        try {
            $allCts = Invoke-MgGraphRequest -Method GET -Uri $ctsUrl -ErrorAction Stop
            $ct = $allCts.value | Where-Object { $_.name -eq $Name }
            
            $status = "Existing"
            if (-not $ct) {
                Write-Verbose "[New-AppGraphContentType] Création du Content Type '$Name' (Beta)..."
                $bodyCT = @{ 
                    name        = $Name
                    description = $Description
                    group       = $Group
                    base        = @{ id = $BaseId } 
                }
                $ct = Invoke-MgGraphRequest -Method POST -Uri $ctsUrl -Body $bodyCT -ContentType "application/json" -ErrorAction Stop
                $status = "Created"
            }
            else {
                Write-Verbose "[New-AppGraphContentType] Le Content Type '$Name' existe déjà (Beta)."
            }
            
            # Attachement des colonnes
            if ($ColumnIdsToBind -and $ColumnIdsToBind.Count -gt 0) {
                Write-Verbose "[New-AppGraphContentType] Vérification et attachement des colonnes au CT (Beta)..."
                $ctColsUrl = "https://graph.microsoft.com/beta/sites/$SiteId/contentTypes/$($ct.id)/columns"
                $ctColsRes = Invoke-MgGraphRequest -Method GET -Uri $ctColsUrl -ErrorAction Stop
                
                # Récupère la liste des IDs déjà attachés
                $existingColIds = $ctColsRes.value.id
                
                foreach ($colId in $ColumnIdsToBind) {
                    if ($colId -notin $existingColIds) {
                        Write-Verbose "[New-AppGraphContentType] Attachement de la colonne ID '$colId'..."
                        $bindBody = @{ "sourceColumn@odata.bind" = "https://graph.microsoft.com/v1.0/sites/$SiteId/columns/$colId" }
                        Invoke-MgGraphRequest -Method POST -Uri $ctColsUrl -Body $bindBody -ContentType "application/json" -ErrorAction Stop | Out-Null
                    }
                }
            }
            
            return [PSCustomObject]@{ Status = $status; ContentType = $ct }
            
        }
        catch {
            Write-Error "Échec de l'opération sur le Content Type '$Name' : $($_.Exception.Message)"
            if ($_.ErrorDetails) { Write-Error "Détails API : $($_.ErrorDetails.Message)" }
            throw $_
        }
    }
}
