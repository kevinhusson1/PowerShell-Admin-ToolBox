# Modules/Database/Functions/Get-AppNamingRules.ps1

function Get-AppNamingRules {
    [CmdletBinding()]
    param(
        [string]$RuleId
    )

    try {
        # v3.1 Sanitization SQL
        $query = "SELECT * FROM sp_naming_rules"
        $sqlParams = @{}

        if (-not [string]::IsNullOrWhiteSpace($RuleId)) {
            $query += " WHERE RuleId = @RuleId"
            $sqlParams.RuleId = $RuleId
        }
        # Pas de colonne DisplayName dans cette table, on trie par ID
        $query += " ORDER BY RuleId"

        return Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $query -SqlParameters $sqlParams -ErrorAction Stop
    }
    catch {
        Write-Warning "Erreur lecture règles nommage : $($_.Exception.Message)"
        return @()
    }
}