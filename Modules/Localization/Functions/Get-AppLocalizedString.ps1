# Modules/Localization/Functions/Get-AppLocalizedString.ps1

<#
.SYNOPSIS
    Récupère une chaîne de texte traduite à partir de sa clé.
.DESCRIPTION
    Cette fonction recherche une clé hiérarchique (ex: 'app.title') dans le
    dictionnaire de langue global ($Global:AppLocalization) et retourne la valeur
    correspondante.
    Si le dictionnaire n'est pas chargé ou si la clé n'est pas trouvée, elle retourne
    la clé elle-même entre crochets pour un débogage visuel facile.
.PARAMETER Key
    La clé de traduction à rechercher, avec des points comme séparateurs de niveau.
.ALIAS
    Get-AppText
.EXAMPLE
    $title = Get-AppText -Key "app.title"
.OUTPUTS
    [string] - La chaîne de caractères traduite, ou une chaîne de fallback.
#>
function Get-AppLocalizedString {
    [CmdletBinding()]
    [Alias('Get-AppText')]
    param(
        [Parameter(Mandatory)]
        [string]$Key
    )

    if (-not $Global:AppLocalization) {
        # Si le dictionnaire n'est même pas chargé, on ne peut rien faire.
        return "[$Key]"
    }

    try {
        $parts = $Key.Split('.')
        $currentObject = $Global:AppLocalization
        foreach ($part in $parts) {
            if ($null -ne $currentObject -and $currentObject.PSObject.Properties[$part]) {
                $currentObject = $currentObject.$part
            } else {
                $warningMsg = "{0} : '{1}'" -f (Get-AppText -Key 'modules.localization.key_not_found'), $Key
                Write-Warning $warningMsg
                return "[$Key]"
            }
        }

        # Si la valeur finale est null (possible en JSON), on retourne une chaîne vide.
        if ($null -eq $currentObject) {
            return ""
        } 
        else {
            return $currentObject
        }
    } catch {
        # Intercepte toute erreur inattendue pendant la recherche
        $warningMsg = "{0} '{1}': $($_.Exception.Message)" -f (Get-AppText -Key 'modules.localization.key_lookup_error'), $Key
        Write-Warning $warningMsg
        return "[$Key]"
    }
}