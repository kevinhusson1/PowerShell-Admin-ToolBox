<#
.SYNOPSIS
    Crée un dossier dans une bibliothèque SharePoint en utilisant Graph API.

.DESCRIPTION
    Utilise l'endpoint 'drives/{driveId}/items/{parentId}/children' pour créer un nouveau dossier.
    Gère les conflits en remplaçant l'élément existant si nécessaire.

.PARAMETER SiteId
    L'identifiant unique (ID) du site SharePoint.

.PARAMETER DriveId
    L'identifiant unique (ID) du Drive (Bibliothèque).

.PARAMETER FolderName
    Le nom du dossier à créer.

.PARAMETER ParentFolderId
    (Optionnel) L'identifiant de l'élément parent. Par défaut : "root".

.EXAMPLE
    New-AppGraphFolder -SiteId "..." -DriveId "..." -FolderName "NouveauDossier"
#>
function New-AppGraphFolder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$SiteId,
        [Parameter(Mandatory=$true)]
        [string]$DriveId,
        [Parameter(Mandatory=$true)]
        [string]$FolderName,
        [Parameter(Mandatory=$false)]
        [string]$ParentFolderId = "root"
    )
    process {
        Write-Verbose "[New-AppGraphFolder] Création du dossier '$FolderName' (Parent: '$ParentFolderId')..."
        $folderBody = @{
            name = $FolderName
            folder = @{}
            "@microsoft.graph.conflictBehavior" = "replace"
        }
        $folderUrl = "https://graph.microsoft.com/v1.0/sites/$SiteId/drives/$DriveId/items/$ParentFolderId/children"
        
        try {
            $folderRes = Invoke-MgGraphRequest -Method POST -Uri $folderUrl -Body $folderBody -ContentType "application/json" -ErrorAction Stop
            return $folderRes
        } catch {
            Write-Error "Échec de la création du dossier '$FolderName' : $($_.Exception.Message)"
            if ($_.ErrorDetails) { Write-Error "Détails API : $($_.ErrorDetails.Message)" }
            throw $_
        }
    }
}
