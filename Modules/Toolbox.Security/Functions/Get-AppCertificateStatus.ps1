# Modules/Toolbox.Security/Functions/Get-AppCertificateStatus.ps1

<#
.SYNOPSIS
    Vérifie la présence et la validité d'un certificat par son empreinte dans le magasin de l'utilisateur.
.DESCRIPTION
    Recherche un certificat UNIQUEMENT dans le magasin Cert:\CurrentUser\My.
    Retourne un objet détaillé sur son statut (présence, validité, date d'expiration).
.PARAMETER Thumbprint
    L'empreinte du certificat à rechercher.
.OUTPUTS
    [PSCustomObject] - Un objet détaillé sur le statut du certificat.
#>
function Get-AppCertificateStatus {
    [CmdletBinding()]
    param(
        [string]$Thumbprint
    )

    $result = [PSCustomObject]@{
        Found = $false
        IsValid = $false # Ajout d'un booléen simple pour la logique
        Status = "NotFound" # NotFound, Valid, ExpiringSoon, Expired
        StatusText = (Get-AppText 'settings.azure_cert_status_notfound')
        ExpirationDate = $null
    }

    if ([string]::IsNullOrWhiteSpace($Thumbprint)) {
        $result.StatusText = (Get-AppText 'settings.azure_cert_status_no_thumbprint')
        return $result
    }

    # CORRECTION : Recherche uniquement dans le magasin de l'utilisateur actuel
    $cert = Get-ChildItem -Path "Cert:\CurrentUser\My" | Where-Object { $_.Thumbprint -eq $Thumbprint.ToUpper() } | Select-Object -First 1

    if (-not $cert) {
        return $result
    }

    $result.Found = $true
    $result.ExpirationDate = $cert.NotAfter

    # Vérification de la validité
    $today = Get-Date
    if ($cert.NotAfter -lt $today) {
        $result.Status = "Expired"
        $result.StatusText = (Get-AppText 'settings.azure_cert_status_expired') -f $cert.NotAfter.ToString('dd/MM/yyyy')
    } elseif ($cert.NotAfter -lt ($today.AddDays(30))) {
        $result.Status = "ExpiringSoon"
        $result.StatusText = (Get-AppText 'settings.azure_cert_status_expiring') -f $cert.NotAfter.ToString('dd/MM/yyyy')
        $result.IsValid = $true # Un certificat qui expire bientôt est toujours valide
    } else {
        $result.Status = "Valid"
        $result.StatusText = (Get-AppText 'settings.azure_cert_status_valid') -f $cert.NotAfter.ToString('dd/MM/yyyy')
        $result.IsValid = $true
    }

    return $result
}