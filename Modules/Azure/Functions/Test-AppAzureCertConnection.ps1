# Modules/Azure/Functions/Test-AppAzureCertConnection.ps1

<#
.SYNOPSIS
    Tente une connexion à Azure en utilisant les informations du certificat.
.DESCRIPTION
    Établit une connexion temporaire à Graph API avec le certificat,
    exécute une requête de test, puis restaure l'état de connexion précédent.
.OUTPUTS
    [PSCustomObject] avec les propriétés Success (bool) et Message (string).
#>
function Test-AppAzureCertConnection {
    [CmdletBinding()]
    param(
        [string]$TenantId, [string]$AppId, [string]$Thumbprint
    )

    $userWasConnected = $Global:AppAzureAuth.UserAuth.Connected
    try {
        Disconnect-MgGraph -ErrorAction SilentlyContinue
        Connect-MgGraph -TenantId $TenantId -AppId $AppId -CertificateThumbprint $Thumbprint
        Invoke-MgGraphRequest -Uri '/v1.0/servicePrincipals?$top=1&$select=id' -Method GET | Out-Null
        return [PSCustomObject]@{ Success = $true; Message = (Get-AppText 'settings_validation.azure_cert_test_success') }
    } catch {
        $msg = (Get-AppText 'settings_validation.azure_cert_test_failure') + "`n`nErreur: $($_.Exception.Message)"
        return [PSCustomObject]@{ Success = $false; Message = $msg }
    } finally {
        Disconnect-MgGraph -ErrorAction SilentlyContinue
        if ($userWasConnected) {
            # On restaure la connexion utilisateur pour ne pas perturber la session
            Connect-AppAzureWithUser -Scopes $Global:AppConfig.azure.authentication.userAuth.scopes | Out-Null
        }
    }
}