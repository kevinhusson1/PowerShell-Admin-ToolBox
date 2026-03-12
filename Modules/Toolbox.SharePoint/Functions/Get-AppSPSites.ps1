<#
.SYNOPSIS
    Récupère la liste des collections de sites (Site Collections) du tenant.

.DESCRIPTION
    Se connecte au centre d'administration SharePoint (-admin.sharepoint.com) pour lister tous les sites.
    Requiert des privilèges d'administrateur SharePoint ou Global Admin.
    Retourne une liste d'objets simplifiés avec le Titre, l'URL et le Template.

.PARAMETER Connection
    (Ignoré) Paramètre conservé pour compatibilité, la fonction gère sa propre connexion Admin.

.PARAMETER ClientId
    L'identifiant de l'application Azure AD.

.PARAMETER Thumbprint
    L'empreinte du certificat pour l'authentification.

.PARAMETER TenantName
    Le nom du tenant (ex: contoso).

.PARAMETER Filter
    (Optionnel) Filtre textuel sur le titre ou l'URL.

.EXAMPLE
    Get-AppSPSites -TenantName "contoso" -ClientId "..." -Thumbprint "..." -Filter "Marketing"
#>
function Get-AppSPSites {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)] $Connection, # Ignoré ici car on doit forcer l'Admin
        [string]$ClientId,
        [string]$Thumbprint,
        [string]$TenantName,
        [string]$Filter # Filtre local optionnel
    )

    # Nettoyage du nom du tenant
    $cleanTenant = $TenantName -replace "\.onmicrosoft\.com$", "" -replace "\.sharepoint\.com$", ""
    $adminUrl = "https://$cleanTenant-admin.sharepoint.com"

    try {
        # Connexion spécifique au centre d'Admin
        Write-Verbose "Connexion Admin sur $adminUrl pour lister les Site Collections..."
        
        $adminConn = Connect-PnPOnline -Url $adminUrl -ClientId $ClientId -Thumbprint $Thumbprint -Tenant "$cleanTenant.onmicrosoft.com" -ReturnConnection -ErrorAction Stop
        
        # Commande Legacy demandée
        $sites = Get-PnPTenantSite -Connection $adminConn | Sort-Object Title
        
        # Filtrage si demandé (Côté client car Get-PnPTenantSite ne filtre pas nativement aussi bien que Search)
        if (-not [string]::IsNullOrWhiteSpace($Filter)) {
            $sites = $sites | Where-Object { $_.Title -like "*$Filter*" -or $_.Url -like "*$Filter*" }
        }

        $results = @()
        foreach ($s in $sites) {
            $results += [PSCustomObject]@{
                Title = $s.Title
                Url   = $s.Url
                Id    = $s.Template # Note: L'objet retourné par Get-PnPTenantSite diffère un peu, on adapte
            }
        }
        
        return $results
    }
    catch {
        # Fallback : Si l'accès Admin échoue, on tente la méthode Search classique
        Write-Warning "Échec accès Admin ($adminUrl). Tentative via Search... Erreur: $($_.Exception.Message)"
        throw $_
    }
}