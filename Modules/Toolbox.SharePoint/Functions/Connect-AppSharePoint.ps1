function Connect-AppSharePoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$ClientId,
        [Parameter(Mandatory)] [string]$Thumbprint,
        [Parameter(Mandatory)] [string]$TenantName,
        [Parameter(Mandatory=$false)] [string]$SiteUrl # Optionnel : URL spécifique
    )

    # Nettoyage du nom du tenant
    $cleanTenant = $TenantName -replace "\.onmicrosoft\.com$", "" -replace "\.sharepoint\.com$", ""
    
    # Détermination de l'URL cible
    $targetUrl = if (-not [string]::IsNullOrWhiteSpace($SiteUrl)) { 
        $SiteUrl 
    } else { 
        "https://$cleanTenant.sharepoint.com" 
    }

    Write-Verbose "Connexion PnP (App-Only) sur : $targetUrl"

    try {
        # On force le retour de la connexion pour l'utiliser dans les autres fonctions
        $conn = Connect-PnPOnline -Url $targetUrl -ClientId $ClientId -Thumbprint $Thumbprint -Tenant "$cleanTenant.onmicrosoft.com" -ReturnConnection -ErrorAction Stop
        
        Write-Verbose "Connexion établie avec succès."
        return $conn
    }
    catch {
        throw "Échec connexion SharePoint ($targetUrl) : $($_.Exception.Message)"
    }
}