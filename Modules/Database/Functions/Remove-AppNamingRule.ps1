# Modules/Database/Functions/Remove-AppNamingRule.ps1

function Remove-AppNamingRule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$RuleId
    )

    try {
        $safeId = $RuleId.Replace("'", "''")
        $query = "DELETE FROM sp_naming_rules WHERE RuleId = '$safeId'"
        
        Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $query -ErrorAction Stop
        return $true
    }
    catch {
        throw "Erreur suppression règle : $($_.Exception.Message)"
    }
}