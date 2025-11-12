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
        # On interroge l'endpoint /me/memberOf qui retourne tous les groupes (et rôles) de l'utilisateur.
        # On ne sélectionne que le displayName, car c'est tout ce dont on a besoin pour la comparaison.
        $groups = Invoke-MgGraphRequest -Uri '/v1.0/me/memberOf?$select=displayName' -Method GET

        if ($null -ne $groups.Value) {
            # La commande retourne un objet avec une propriété "Value" qui contient la liste.
            $groupNames = $groups.Value.displayName

            # Messages de succès en verbose
            $successMessage1 = Get-AppText -Key 'modules.azure.get_groups_success1'
            $successMessage1 = Get-AppText -Key 'modules.azure.get_groups_success2'
            Write-Verbose "$successMessage1 $($groupNames.Count) $successMessage1"

            return $groupNames
        } else {
            # Messages d'erreur en verbose
            $failureMessage = Get-AppText -Key 'modules.azure.get_groups_failure'
            Write-Verbose "$failureMessage"

            return @()
        }
    } catch {
        $errorMessage = Get-AppText -Key 'modules.azure.get_groups_error'
        Write-Warning "$errorMessage : $($_.Exception.Message)"
        return @() # En cas d'erreur, on retourne toujours un tableau vide pour la sécurité.
    }
}