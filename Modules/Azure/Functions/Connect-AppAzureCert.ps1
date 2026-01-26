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
