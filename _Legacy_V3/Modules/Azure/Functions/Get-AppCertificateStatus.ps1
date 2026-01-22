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
