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