<#
.SYNOPSIS
    Télécharge un fichier depuis SharePoint vers le système de fichiers local.

.DESCRIPTION
    Récupère un fichier SharePoint via son URL relative au serveur et l'enregistre dans un dossier local spécifié.
    Utilise PnP PowerShell (Get-PnPFile -AsFile).

.PARAMETER ServerRelativeUrl
    L'URL relative au serveur du fichier (ex: /sites/MySite/Shared Documents/doc.pdf).

.PARAMETER LocalFolder
    Le chemin complet du répertoire local de destination.

.PARAMETER LocalFileName
    (Optionnel) Le nom sous lequel le fichier sera enregistré localement.

.PARAMETER Connection
    (Optionnel) Objet de connexion PnP actif.

.EXAMPLE
    Get-AppSPFile -ServerRelativeUrl "/sites/HR/Docs/Policy.pdf" -LocalFolder "C:\Downloads"
#>
function Get-AppSPFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$ServerRelativeUrl, # URL du fichier sur SP
        [Parameter(Mandatory)] [string]$LocalFolder,       # Dossier local de destination
        [string]$LocalFileName,                            # Optionnel : Renommer en local
        [Parameter(Mandatory=$false)] $Connection
    )

    if (-not (Test-Path $LocalFolder)) { throw "Dossier local destination introuvable : $LocalFolder" }

    try {
        Write-Verbose "Téléchargement de '$ServerRelativeUrl'..."
        
        $params = @{ Url = $ServerRelativeUrl; Path = $LocalFolder; AsFile = $true; ErrorAction = "Stop" }
        if (-not [string]::IsNullOrWhiteSpace($LocalFileName)) { $params.Filename = $LocalFileName }
        if ($Connection) { $params.Connection = $Connection }

        Get-PnPFile @params | Out-Null
        
        $finalPath = Join-Path $LocalFolder (if ($LocalFileName) { $LocalFileName } else { Split-Path $ServerRelativeUrl -Leaf })
        return $finalPath
    }
    catch {
        throw "Erreur téléchargement : $($_.Exception.Message)"
    }
}