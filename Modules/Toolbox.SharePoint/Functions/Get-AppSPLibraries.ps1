function Get-AppSPLibraries {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)] [string]$SiteUrl,
        [Parameter(Mandatory=$false)] $Connection
    )

    try {
        $params = @{ ErrorAction = "Stop" }
        if ($Connection) { $params.Connection = $Connection }
        elseif (-not [string]::IsNullOrWhiteSpace($SiteUrl)) {
             $conn = Connect-PnPOnline -Url $SiteUrl -Interactive -ReturnConnection -ErrorAction Stop
             $params.Connection = $conn
        }

        # Filtre Legacy strict
        $libs = Get-PnPList @params | Where-Object { $_.BaseTemplate -eq 101 } | Sort-Object Title
        
        # Projection pour l'UI
        $results = @()
        foreach ($lib in $libs) {
            $results += [PSCustomObject]@{
                Title = $lib.Title
                Id = $lib.Id
                RootFolder = $lib.RootFolder # Utile pour le path relatif
            }
        }

        return $results
    }
    catch {
        throw "Erreur récupération bibliothèques : $($_.Exception.Message)"
    }
}