# Modules/Azure/Functions/Get-AppAzureGroupMembers.ps1

<#
.SYNOPSIS
    Récupère les membres (Display Name et UPN) d'un groupe Azure AD par son nom.
#>
function Get-AppAzureGroupMembers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$GroupName
    )

    if (-not $Global:AppAzureAuth.UserAuth.Connected) { return @() }

    try {
        # 1. Trouver l'ID du groupe via son nom
        $group = Get-MgGroup -Filter "displayName eq '$GroupName'" -ErrorAction Stop | Select-Object -First 1
        
        if (-not $group) {
            Write-Warning "Le groupe '$GroupName' est introuvable dans Azure AD."
            return @()
        }

        # 2. Récupérer les membres
        $members = Get-MgGroupMember -GroupId $group.Id -ErrorAction Stop
        
        # 3. Récupérer les détails des utilisateurs (car Get-MgGroupMember ne renvoie parfois que des IDs)
        $memberDetails = @()
        foreach ($member in $members) {
            # On tente de récupérer l'objet utilisateur complet pour avoir l'UPN
            $user = Get-MgUser -UserId $member.Id -ErrorAction SilentlyContinue
            if ($user) {
                $memberDetails += [PSCustomObject]@{
                    DisplayName = $user.DisplayName
                    UserPrincipalName = $user.UserPrincipalName
                }
            }
        }
        return $memberDetails
    }
    catch {
        Write-Warning "Erreur lors de la récupération des membres du groupe '$GroupName' : $($_.Exception.Message)"
        return @()
    }
}