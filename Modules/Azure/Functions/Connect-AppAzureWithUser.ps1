# Modules/Azure/Functions/Connect-AppAzureWithUser.ps1

<#
.SYNOPSIS
    Connecte l'utilisateur de manière interactive à Microsoft Graph.
.DESCRIPTION
    Cette fonction initie une connexion à Microsoft Graph en utilisant les scopes fournis.
    Elle utilise le Tenant ID pour cibler l'annuaire spécifique de l'entreprise.
.PARAMETER AppId
    L'Application (Client) ID à utiliser pour l'authentification.
.PARAMETER TenantId
    L'ID du Tenant Azure AD (obligatoire pour les applications Single Tenant).
#>
function Connect-AppAzureWithUser {
    [CmdletBinding()]
    param(
        [string[]]$Scopes = @("User.Read", "GroupMember.Read.All"),
        [Parameter(Mandatory)]
        [string]$AppId,
        [Parameter(Mandatory)]
        [string]$TenantId
    )

    try {
        # CORRECTION : Ajout du paramètre -TenantId pour cibler le bon annuaire
        Connect-MgGraph -Scopes $Scopes -AppId $AppId -TenantId $TenantId -NoWelcome
        
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
        Write-Warning "$errorMessage : $($_.Exception.Message)"
        return [PSCustomObject]@{ Success = $false; Connected = $false }
    }
}