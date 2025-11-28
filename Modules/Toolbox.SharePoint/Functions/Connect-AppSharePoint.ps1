# Modules/Toolbox.SharePoint/Functions/Connect-AppSharePoint.ps1

<#
.SYNOPSIS
    Établit une connexion sécurisée à SharePoint Online via PnP PowerShell.
.DESCRIPTION
    Utilise l'App Registration de l'entreprise (ClientId) pour s'authentifier.
    En mode Interactive, cela bénéficie du SSO si l'utilisateur est déjà connecté à Windows/Office.
.PARAMETER TenantName
    Le nom du tenant (ex: 'vosgelis365'). Si 'vosgelis365.onmicrosoft.com' est passé, il sera nettoyé.
.PARAMETER ClientId
    L'ID de l'application Azure (App Registration). Si non fourni, tente de lire la config globale.
#>
function Connect-AppSharePoint {
    [CmdletBinding()]
    param(
        [string]$TenantName,
        [string]$ClientId,
        [string]$Thumbprint # <--- Ce paramètre manquait dans votre version actuelle
    )

    # Si le Thumbprint n'est pas passé, on le lit en config
    if ([string]::IsNullOrWhiteSpace($Thumbprint)) {
        if ($Global:AppConfig -and $Global:AppConfig.azure) {
            $Thumbprint = $Global:AppConfig.azure.certThumbprint
        }
        # Fallback lecture directe BDD si l'objet config n'est pas à jour
        if ([string]::IsNullOrWhiteSpace($Thumbprint)) {
            $Thumbprint = Get-AppSetting -Key 'azure.cert.thumbprint'
        }
    }

    if ([string]::IsNullOrWhiteSpace($Thumbprint)) {
        Write-Error "Aucun certificat configuré. Impossible de se connecter en App-Only."
        return $false
    }

    # Nettoyage Tenant
    if (-not [string]::IsNullOrWhiteSpace($TenantName)) {
        $TenantName = $TenantName -replace "\.onmicrosoft\.com$", "" -replace "\.sharepoint\.com$", ""
    }
    
    if ([string]::IsNullOrWhiteSpace($TenantName)) {
        Write-Error "Nom du tenant manquant."
        return $false
    }

    $rootUrl = "https://$TenantName.sharepoint.com"

    Write-Verbose "Connexion PnP App-Only sur $rootUrl..."

    try {
        # Connexion par Certificat (App-Only)
        Connect-PnPOnline -Url $rootUrl -ClientId $ClientId -Thumbprint $Thumbprint -Tenant "$TenantName.onmicrosoft.com" -ErrorAction Stop
        
        Write-Verbose "Connexion App-Only réussie !"
        return $true
    }
    catch {
        Write-Error "Échec connexion PnP : $($_.Exception.Message)"
        return $false
    }
}