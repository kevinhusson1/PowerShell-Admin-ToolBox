# Modules/Database/Functions/Get-AppSetting.ps1

<#
.SYNOPSIS
    Récupère la valeur d'un paramètre de configuration depuis la base de données.
.DESCRIPTION
    Cette fonction interroge la table 'settings' pour une clé spécifique.
    Elle lit la valeur et son type, effectue la conversion de type nécessaire,
    et retourne la valeur typée. Si la clé n'est pas trouvée, elle retourne
    la valeur par défaut fournie.
.PARAMETER Key
    La clé unique du paramètre à récupérer (ex: 'app.companyName').
.PARAMETER DefaultValue
    La valeur à retourner si la clé n'est pas trouvée dans la base de données.
.EXAMPLE
    $company = Get-AppSetting -Key 'app.companyName' -DefaultValue "Entreprise par défaut"
.OUTPUTS
    [string], [int], [bool] - La valeur du paramètre, convertie au bon type.
#>
function Get-AppSetting {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Key,
        
        $DefaultValue
    )

    try {
        $safeKey = $Key.Replace("'", "''")
        $query = "SELECT Value, Type FROM settings WHERE Key = '$safeKey';"
        
        $result = Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $query -ErrorAction Stop

        if (-not $result) {
            $logMsg = "{0} '{1}'. {2}" -f (Get-AppText 'modules.database.setting_not_found_1'), $Key, (Get-AppText 'modules.database.setting_not_found_2')
            Write-Verbose $logMsg
            return $DefaultValue
        }
        
        $logMsg = "{0} '{1}'. {2}: '$($result.Value)', {3}: '$($result.Type)'." -f (Get-AppText 'modules.database.setting_found_1'), $Key, (Get-AppText 'modules.database.setting_found_2'), (Get-AppText 'modules.database.setting_found_3')
        Write-Verbose $logMsg

        switch ($result.Type) {
            'integer' {
                $intValue = 0
                if ([int]::TryParse($result.Value, [ref]$intValue)) {
                    return $intValue
                } else {
                    $warningMsg = "{0} '$($result.Value)' {1} '$Key'. {2}" -f (Get-AppText 'modules.database.int_parse_error_1'), (Get-AppText 'modules.database.int_parse_error_2'), (Get-AppText 'modules.database.setting_not_found_2')
                    Write-Warning $warningMsg
                    return $DefaultValue
                }
            }
            'boolean' {
                $boolValue = $false
                if ([bool]::TryParse($result.Value, [ref]$boolValue)) {
                    return $boolValue
                } else {
                    $warningMsg = "{0} '$($result.Value)' {1} '$Key'. {2}" -f (Get-AppText 'modules.database.bool_parse_error_1'), (Get-AppText 'modules.database.bool_parse_error_2'), (Get-AppText 'modules.database.setting_not_found_2')
                    Write-Warning $warningMsg
                    return $DefaultValue
                }
            }
            default {
                return $result.Value
            }
        }
    } catch {
        $errorMsg = Get-AppText -Key 'modules.database.get_setting_error'
        Write-Warning "$errorMsg '$Key': $($_.Exception.Message)"
        return $DefaultValue
    }
}