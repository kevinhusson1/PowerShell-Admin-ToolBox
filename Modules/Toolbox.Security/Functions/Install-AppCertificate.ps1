# Modules/Toolbox.Security/Functions/Install-AppCertificate.ps1

<#
.SYNOPSIS
    Installe un certificat PFX dans le magasin CurrentUser.
.DESCRIPTION
    Importe un certificat PFX. L'élévation de privilèges n'est plus nécessaire.
.PARAMETER PfxPath
    Le chemin vers le fichier .pfx à installer.
.PARAMETER SecurePassword
    Le mot de passe du fichier .pfx sous forme de SecureString.
.OUTPUTS
    [PSCustomObject] - Un rapport sur le succès ou l'échec de l'installation.
#>
function Install-AppCertificate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$PfxPath,
        [Parameter(Mandatory)] [System.Security.SecureString]$SecurePassword
    )
    
    $report = [PSCustomObject]@{
        Success = $false
        Message = ""
    }

    try {
        Import-PfxCertificate -FilePath $PfxPath -CertStoreLocation "Cert:\CurrentUser\My" -Password $SecurePassword -Exportable -ErrorAction Stop | Out-Null
        $report.Success = $true
        $report.Message = (Get-AppText 'settings_validation.cert_install_cu_success')
        Write-LauncherLog -Message $report.Message -Level Success -LogToUI
    } catch {
        $report.Message = (Get-AppText 'settings_validation.cert_install_cu_error') + ": $($_.Exception.Message)"
        Write-LauncherLog -Message $report.Message -Level Error -LogToUI
    }

    return $report
}