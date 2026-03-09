function Get-AppGraphSiteId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$SiteUrl
    )
    process {
        Write-Verbose "[Get-AppGraphSiteId] Récupération de l'ID du site pour : $SiteUrl"
        $uri = [System.Uri]$SiteUrl
        $hostname = $uri.Host
        $path = $uri.AbsolutePath
        $requestUrl = "https://graph.microsoft.com/v1.0/sites/$hostname`:$path"
        
        try {
            $res = Invoke-MgGraphRequest -Method GET -Uri $requestUrl -ErrorAction Stop
            return $res.id
        } catch {
            Write-Error "Échec lors de la récupération du SiteId Graph pour $SiteUrl : $($_.Exception.Message)"
            throw $_
        }
    }
}
