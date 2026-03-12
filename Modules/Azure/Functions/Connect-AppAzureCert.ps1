<#
.SYNOPSIS
    Établit une connexion à Microsoft Graph en utilisant un certificat (App-Only).

.DESCRIPTION
    Utilise le module Microsoft.Graph.Authentication pour se connecter via l'identité d'une application Azure AD (Service Principal) et un certificat local.
    La connexion est établie au niveau du processus actuel.

.PARAMETER TenantId
    L'identifiant unique (GUID) du tenant Azure AD.

.PARAMETER ClientId
    L'identifiant unique (GUID) de l'application (ID Client) enregistrée dans Azure AD.

.PARAMETER Thumbprint
    L'empreinte (Thumbprint) du certificat installé dans le magasin de certificats (Currentuser/My) utilisé pour l'authentification.

.EXAMPLE
    Connect-AppAzureCert -TenantId "xxx" -ClientId "yyy" -Thumbprint "zzz"
#>
function Connect-AppAzureCert {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$TenantId,
        [Parameter(Mandatory)] [string]$ClientId,
        [Parameter(Mandatory)] [string]$Thumbprint
    )

    try {
        Write-Verbose "[Connect-AppAzureCert] Connexion via Certificat (App-Only)..."
        
        # Connexion Graph (Scope Process par défaut pour que ça s'applique au script entier)
        Connect-MgGraph -TenantId $TenantId -ClientId $ClientId -CertificateThumbprint $Thumbprint -NoWelcome -ErrorAction Stop
        
        $context = Get-MgContext
        if ($context) {
            Write-Verbose "[Connect-AppAzureCert] Connecté en tant que : $($context.Account)"
            return $true
        }
        return $false
    }
    catch {
        Write-Warning "[Connect-AppAzureCert] Echec connexion : $($_.Exception.Message)"
        throw $_
    }
}
