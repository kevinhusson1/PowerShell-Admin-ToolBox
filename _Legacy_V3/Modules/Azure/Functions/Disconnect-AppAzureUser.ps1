# Modules/Azure/Functions/Disconnect-AppAzureUser.ps1

<#
.SYNOPSIS
    Déconnecte la session Microsoft Graph de l'utilisateur.
.DESCRIPTION
    Cette fonction ferme la connexion interactive à Microsoft Graph et efface
    les jetons d'authentification du cache de la session en cours.
.EXAMPLE
    Disconnect-AppAzureUser
.OUTPUTS
    Aucune.
#>
function Disconnect-AppAzureUser {
    [CmdletBinding()]
    param()

    try {
        Disconnect-MgGraph
    } catch {
        $errorMessage = Get-AppText -Key 'modules.azure.disconnect_error'
        Write-Warning "$errorMessage  : $($_.Exception.Message)."
    }
}