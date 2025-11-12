# Modules/Azure/Functions/Connect-AppAzureWithUser.ps1

<#
.SYNOPSIS
    Connecte l'utilisateur de manière interactive à Microsoft Graph.
.DESCRIPTION
    Cette fonction initie une connexion à Microsoft Graph en utilisant les scopes fournis.
    Elle gère l'ouverture de la fenêtre de connexion si nécessaire (ou utilise le cache de jetons).
    En cas de succès, elle retourne un objet contenant les informations du profil de l'utilisateur.
.PARAMETER Scopes
    Un tableau de chaînes de caractères représentant les permissions (scopes) à demander pour la session Graph.
.EXAMPLE
    $authResult = Connect-AppAzureWithUser -Scopes "User.Read", "Mail.Read"
    if ($authResult.Success) {
        Write-Host "Connecté en tant que $($authResult.DisplayName)"
    }
.OUTPUTS
    PSCustomObject - Un objet contenant le statut de la connexion et les informations de l'utilisateur.
#>
function Connect-AppAzureWithUser {
    [CmdletBinding()]
    param(
        [string[]]$Scopes = @("User.Read", "GroupMember.Read.All")
    )

    try {
        Connect-MgGraph -Scopes $Scopes -NoWelcome
        
        $user = Invoke-MgGraphRequest -Uri '/v1.0/me?$select=displayName,userPrincipalName' -Method GET
        $initials = (($user.DisplayName -split ' ' | Where-Object { $_ }) | ForEach-Object { $_.Substring(0,1) }) -join ''

        return [PSCustomObject]@{
            Connected         = $true
            Success           = $true
            UserPrincipalName = $user.userPrincipalName
            DisplayName       = $user.DisplayName
            Initials          = $initials
        }
    } catch {
        $errorMessage = Get-AppText -Key 'modules.azure.auth_error'
        # Le message technique de l'exception reste en anglais, ce qui est une bonne pratique.
        Write-Warning "$errorMessage : $($_.Exception.Message)"

        return [PSCustomObject]@{ Success = $false; Connected = $false }
    }
}