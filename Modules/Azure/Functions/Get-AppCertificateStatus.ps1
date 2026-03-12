<#
.SYNOPSIS
    Vérifie l'existence et l'état de validité d'un certificat local par son empreinte (Thumbprint).

.DESCRIPTION
    Recherche un certificat dans les magasins 'CurrentUser\My' et 'LocalMachine\My'.
    Retourne des informations sur sa localisation, sa date d'expiration et si celui-ci est expiré.

.PARAMETER Thumbprint
    L'empreinte du certificat à rechercher (insensible à la casse et aux espaces).

.EXAMPLE
    Get-AppCertificateStatus -Thumbprint "D25A39ACC63BC2F3F1B6389568E9B5AA3726969D"
#>
function Get-AppCertificateStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Thumbprint
    )

    $cleanThumb = $Thumbprint -replace '\s', '' -replace '[^0-9a-fA-F]', ''
    
    # Recherche CurrentUser
    $pathUser = "Cert:\CurrentUser\My\$cleanThumb"
    if (Test-Path $pathUser) {
        $cert = Get-Item $pathUser
        return [PSCustomObject]@{
            Found          = $true
            Location       = "CurrentUser"
            ExpirationDate = $cert.NotAfter
            DaysRemaining  = ($cert.NotAfter - (Get-Date)).Days
            Issuer         = $cert.Issuer
            Subject        = $cert.Subject
            IsExpired      = ($cert.NotAfter -lt (Get-Date))
        }
    }

    # Recherche LocalMachine
    $pathMachine = "Cert:\LocalMachine\My\$cleanThumb"
    if (Test-Path $pathMachine) {
        $cert = Get-Item $pathMachine
        return [PSCustomObject]@{
            Found          = $true
            Location       = "LocalMachine"
            ExpirationDate = $cert.NotAfter
            DaysRemaining  = ($cert.NotAfter - (Get-Date)).Days
            Issuer         = $cert.Issuer
            Subject        = $cert.Subject
            IsExpired      = ($cert.NotAfter -lt (Get-Date))
        }
    }

    return [PSCustomObject]@{
        Found          = $false
        Location       = $null
        ExpirationDate = $null
        DaysRemaining  = $null
        IsExpired      = $false
    }
}
