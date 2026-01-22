function Add-AppSPFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$LocalPath,
        [Parameter(Mandatory)] [string]$Folder,    # Site Relative URL (ex: /Shared Documents)
        [string]$NewFileName,                      # Optionnel
        [Parameter(Mandatory=$false)] $Connection
    )

    if (-not (Test-Path $LocalPath)) { throw "Fichier local introuvable : $LocalPath" }

    try {
        # 1. Normalisation du dossier cible
        # Resolve-PnPFolder est plus tolérant et nous renvoie l'objet Dossier avec le bon ServerRelativeUrl
        # (ex: /sites/TEST_PNP/Shared Documents/...)
        $folderParam = @{ SiteRelativePath = $Folder; ErrorAction = "Stop" }
        if ($Connection) { $folderParam.Connection = $Connection }
        
        $targetFolderObj = Resolve-PnPFolder @folderParam
        $safeServerRelativeUrl = $targetFolderObj.ServerRelativeUrl

        Write-Verbose "Upload de '$LocalPath' vers '$safeServerRelativeUrl'..."
        
        # 2. Upload avec le chemin sécurisé
        $uploadParams = @{ Path = $LocalPath; Folder = $safeServerRelativeUrl; ErrorAction = "Stop" }
        if (-not [string]::IsNullOrWhiteSpace($NewFileName)) { $uploadParams.NewFileName = $NewFileName }
        if ($Connection) { $uploadParams.Connection = $Connection }

        $file = Add-PnPFile @uploadParams
        return $file
    }
    catch {
        throw "Erreur upload : $($_.Exception.Message)"
    }
}