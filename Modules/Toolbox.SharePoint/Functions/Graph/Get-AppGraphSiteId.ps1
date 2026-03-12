<#
.SYNOPSIS
    Convertit l'URL complète d'un site SharePoint en identifiant unique SharePoint Graph SiteId.

.DESCRIPTION
    Utilise l'endpoint Graph 'sites/{hostname}:{path}' pour résoudre l'URL du site.
    Le SiteId retourné est nécessaire pour la plupart des appels Graph ciblant un site spécifique.

.PARAMETER SiteUrl
    L'URL complète du site SharePoint (ex: https://tenant.sharepoint.com/sites/nomdusite).

.EXAMPLE
    Get-AppGraphSiteId -SiteUrl "https://contoso.sharepoint.com/sites/HR"
#>
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
