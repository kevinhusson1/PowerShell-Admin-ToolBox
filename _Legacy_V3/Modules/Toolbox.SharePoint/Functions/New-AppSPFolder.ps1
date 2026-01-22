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