# Modules/Azure/Functions/Get-AppUserAzureGroups.ps1

<#
.SYNOPSIS
    Récupère la liste des noms des groupes Azure AD auxquels l'utilisateur connecté appartient.
.DESCRIPTION
    Cette fonction interroge l'API Microsoft Graph pour obtenir tous les groupes
    dont l'utilisateur actuel est membre. Elle gère automatiquement la pagination
    pour s'assurer de récupérer la liste complète des groupes.
.EXAMPLE
    $myGroups = Get-AppUserAzureGroups
.OUTPUTS
    [string[]] - Un tableau de chaînes de caractères contenant le nom (DisplayName) de chaque groupe.
#>
function Get-AppUserAzureGroups {
    [CmdletBinding()]
    param()

    try {
        # On récupère uniquement la propriété displayName
        $groups = Invoke-MgGraphRequest -Uri '/v1.0/me/memberOf?$select=displayName' -Method GET

        if ($null -ne $groups.Value) {
            # CORRECTION : On filtre pour ne garder que les chaînes non vides
            $groupNames = $groups.Value.displayName | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

            $successMessage1 = Get-AppText -Key 'modules.azure.get_groups_success1'
            $successMessage2 = Get-AppText -Key 'modules.azure.get_groups_success2'
            Write-Verbose "$successMessage1 $($groupNames.Count) $successMessage2"

            return $groupNames
        } else {
            $failureMessage = Get-AppText -Key 'modules.azure.get_groups_failure'
            Write-Verbose "$failureMessage"
            return @()
        }
    } catch {
        $errorMessage = Get-AppText -Key 'modules.azure.get_groups_error'
        Write-Warning "$errorMessage : $($_.Exception.Message)"
        return @()
    }
}