<#
.SYNOPSIS
    Résout ou crée un dossier SharePoint via PnP PowerShell.

.DESCRIPTION
    Utilise Resolve-PnPFolder pour s'assurer qu'un chemin relatif au site existe. 
    Si le dossier n'existe pas, il est créé automatiquement par la commande PnP.
    Retourne l'objet Folder SharePoint.

.PARAMETER SiteRelativePath
    Le chemin relatif au site (ex: "Shared Documents/Folder/SubFolder").

.PARAMETER Connection
    (Optionnel) Objet de connexion PnP actif.

.EXAMPLE
    New-AppSPFolder -SiteRelativePath "Shared Documents/NouveauProjet" -Connection $conn
#>
function New-AppSPFolder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$SiteRelativePath, # Ex: /sites/HR/Docs/2024
        [Parameter(Mandatory=$false)] $Connection
    )

    try {
        Write-Verbose "Vérification/Création dossier : $SiteRelativePath"
        
        $params = @{ SiteRelativePath = $SiteRelativePath; ErrorAction = "Stop" }
        if ($Connection) { $params.Connection = $Connection }

        # Resolve-PnPFolder crée le dossier s'il n'existe pas (comportement par défaut)
        $folder = Resolve-PnPFolder @params
        
        return $folder
    }
    catch {
        throw "Impossible de créer le dossier '$SiteRelativePath' : $($_.Exception.Message)"
    }
}