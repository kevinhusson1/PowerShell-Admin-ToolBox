# Modules/Azure/Functions/Test-AppAzureUserConnection.ps1

<#
.SYNOPSIS
    Tente une connexion à Azure en utilisant les informations de l'utilisateur.
.DESCRIPTION
    Établit une connexion temporaire à Graph API avec l'App ID et les scopes fournis,
    exécute une requête de test, puis restaure l'état de connexion précédent.
.PARAMETER AppId
    L'Application (Client) ID à utiliser.
.PARAMETER Scopes
    Les scopes à demander.
.OUTPUTS
    [PSCustomObject] avec les propriétés Success (bool) et Message (string).
#>
function Test-AppAzureUserConnection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)][string[]]$Scopes
    )
    $userWasConnected = $Global:AppAzureAuth.UserAuth.Connected
    try {
        Disconnect-MgGraph -ErrorAction SilentlyContinue
        # C'est ici que le test réel a lieu
        Connect-MgGraph -AppId $AppId -Scopes $Scopes
        return [PSCustomObject]@{ Success = $true; Message = (Get-AppText 'settings_validation.azure_user_test_success') }
    } catch {
        $msg = (Get-AppText 'settings_validation.azure_user_test_failure') + "`n`nErreur: $($_.Exception.Message)"
        return [PSCustomObject]@{ Success = $false; Message = $msg }
    } finally {
        Disconnect-MgGraph -ErrorAction SilentlyContinue
        if ($userWasConnected) {
            # On restaure la connexion utilisateur originale pour ne pas perturber la session
            Connect-AppAzureWithUser -AppId $Global:AppConfig.azure.authentication.userAuth.appId -Scopes $Global:AppConfig.azure.authentication.userAuth.scopes | Out-Null
        }
    }
}