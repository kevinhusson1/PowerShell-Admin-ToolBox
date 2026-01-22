# Modules/Database/Functions/Remove-AppNamingRule.ps1

function Remove-AppNamingRule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$RuleId
    )

    try {
        # v3.1 Sanitization SQL
        $query = "DELETE FROM sp_naming_rules WHERE RuleId = @RuleId"
        $sqlParams = @{ RuleId = $RuleId }
        
        Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $query -SqlParameters $sqlParams -ErrorAction Stop
        return $true
    }
    catch {
        throw "Erreur suppression règle : $($_.Exception.Message)"
    }
}