# Modules/Database/Functions/Get-AppNamingRules.ps1

function Get-AppNamingRules {
    [CmdletBinding()]
    param(
        [string]$RuleId
    )

    try {
        $query = "SELECT * FROM sp_naming_rules"
        if (-not [string]::IsNullOrWhiteSpace($RuleId)) {
            $safeId = $RuleId.Replace("'", "''")
            $query += " WHERE RuleId = '$safeId'"
        }
        # Pas de colonne DisplayName dans cette table, on trie par ID
        $query += " ORDER BY RuleId"

        return Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $query -ErrorAction Stop
    }
    catch {
        Write-Warning "Erreur lecture règles nommage : $($_.Exception.Message)"
        return @()
    }
}