# Modules/Toolbox.ActiveDirectory/Functions/Test-ADDirectoryObjects.ps1

<#
.SYNOPSIS
    Valide l'existence d'objets spécifiques dans Active Directory.
.DESCRIPTION
    Cette fonction vérifie que :
    1. Le chemin de l'OU fourni correspond à une OU existante.
    2. Le groupe "Utilisateurs du domaine" existe avec le sAMAccountName fourni.
    3. Chaque groupe dans la liste des exclusions existe.
    Elle retourne un rapport détaillé, notamment pour les groupes à exclure.
.PARAMETER OUPath
    Le Distinguished Name de l'OU de création des utilisateurs.
.PARAMETER ExcludedGroups
    Une chaîne de caractères contenant les sAMAccountNames des groupes à exclure, séparés par des virgules.
.PARAMETER DomainUserGroupSamAccountName
    Le sAMAccountName attendu pour le groupe "Utilisateurs du domaine".
.PARAMETER Credential
    L'objet PSCredential du compte de service pour effectuer les requêtes AD.
.OUTPUTS
    [PSCustomObject] - Un objet de résultat détaillé.
#>
function Test-ADDirectoryObjects {
    [CmdletBinding()]
    param(
        [string]$OUPath,
        [string]$ExcludedGroups,
        [string]$DomainUserGroupSamAccountName,
        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$Credential
    )

    # --- Prérequis : Vérifier que le module AD est disponible ---
    try {
        Assert-ADModuleAvailable # Fonction privée du module
    } catch {
        # On reformate l'erreur pour qu'elle soit plus "contrôlée"
        return [PSCustomObject]@{ Success = $false; Target = "ADObjects"; Message = $_.Exception.Message }
    }

    # --- Pré-validation des entrées ---
    if ([string]::IsNullOrWhiteSpace($OUPath)) { throw (Get-AppText 'settings_validation.adobjects_ou_empty') }
    if ([string]::IsNullOrWhiteSpace($DomainUserGroupSamAccountName)) { throw (Get-AppText 'settings_validation.adobjects_domainusergroup_empty') }

    # --- Test 1 : Validation de l'OU ---
    try {
        Write-Verbose "Vérification de l'OU : '$OUPath'..."
        if (-not (Get-ADOrganizationalUnit -Identity $OUPath -Credential $Credential -ErrorAction Stop)) {
            $msg = (Get-AppText 'settings_validation.adobjects_ou_not_found') -f $OUPath
            return [PSCustomObject]@{ Success = $false; Target = "OUPath"; Message = $msg }
        }
    } catch {
        $msg = (Get-AppText 'settings_validation.adobjects_ou_not_found') -f $OUPath
        return [PSCustomObject]@{ Success = $false; Target = "OUPath"; Message = "$msg. Erreur : $($_.Exception.Message)" }
    }

    # --- Test 2 : Validation du groupe "Utilisateurs du domaine" ---
    try {
        Write-Verbose "Vérification du groupe 'Utilisateurs du domaine' via sAMAccountName : '$DomainUserGroupSamAccountName'..."
        $filter = "sAMAccountName -eq '$DomainUserGroupSamAccountName'"
        if (-not (Get-ADGroup -Filter $filter -Credential $Credential -ErrorAction Stop)) {
            $msg = (Get-AppText 'settings_validation.adobjects_domainusergroup_not_found') -f $DomainUserGroupSamAccountName
            return [PSCustomObject]@{ Success = $false; Target = "DomainUserGroup"; Message = $msg }
        }
    } catch {
        $msg = (Get-AppText 'settings_validation.adobjects_domainusergroup_not_found') -f $DomainUserGroupSamAccountName
        return [PSCustomObject]@{ Success = $false; Target = "DomainUserGroup"; Message = "$msg. Erreur : $($_.Exception.Message)" }
    }

    # --- Test 3 : Validation des groupes à exclure (si la liste n'est pas vide) ---
    $foundGroups = [System.Collections.Generic.List[string]]::new()
    $notFoundGroups = [System.Collections.Generic.List[string]]::new()

    if (-not [string]::IsNullOrWhiteSpace($ExcludedGroups)) {
        $groupList = $ExcludedGroups.Split(',') | ForEach-Object { $_.Trim() }
        Write-Verbose "Vérification de $($groupList.Count) groupe(s) à exclure..."

        foreach ($groupName in $groupList) {
            if ([string]::IsNullOrWhiteSpace($groupName)) { continue }
            try {
                # CORRECTION : Le filtre utilise maintenant 'sAMAccountName' au lieu de 'Name'
                if (Get-ADGroup -Filter "sAMAccountName -eq '$groupName'" -Credential $Credential -ErrorAction Stop) {
                    $foundGroups.Add($groupName)
                } else {
                    $notFoundGroups.Add($groupName)
                }
            } catch {
                $notFoundGroups.Add($groupName)
            }
        }

        if ($notFoundGroups.Count -gt 0) {
            $foundText = if ($foundGroups.Count -gt 0) { (Get-AppText 'settings_validation.adobjects_excluded_found') -f ($foundGroups -join ", ") } else { "" }
            $notFoundText = (Get-AppText 'settings_validation.adobjects_excluded_not_found') -f ($notFoundGroups -join ", ")
            $message = ("{0}`n{1}" -f $foundText, $notFoundText).Trim()
            return [PSCustomObject]@{ Success = $false; Target = "ExcludedGroups"; Message = $message }
        }
    }

    # --- Tous les tests ont réussi ---
    $successMessage = (Get-AppText 'settings_validation.adobjects_success_all')
    if ($foundGroups.Count -gt 0) {
        $successMessage += "`n" + ((Get-AppText 'settings_validation.adobjects_excluded_all_found') -f ($foundGroups -join ", "))
    }

    return [PSCustomObject]@{
        Success = $true
        Message = $successMessage
    }
}