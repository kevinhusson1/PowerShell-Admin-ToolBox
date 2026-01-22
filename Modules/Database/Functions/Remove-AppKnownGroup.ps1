# Modules/Database/Functions/Remove-AppKnownGroup.ps1

function Remove-AppKnownGroup {
    [CmdletBinding()]
    param([string]$GroupName)
    # v3.1 Sanitization SQL
    $paramGroupName = $GroupName.Trim()
    try {
        $sqlParams = @{ GroupName = $paramGroupName }
        
        # On supprime du référentiel
        $q1 = "DELETE FROM known_groups WHERE GroupName = @GroupName;"
        Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $q1 -SqlParameters $sqlParams -ErrorAction Stop
        
        # On nettoie aussi les associations existantes pour ne pas laisser de fantômes
        $q2 = "DELETE FROM script_security WHERE ADGroup = @GroupName;"
        Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $q2 -SqlParameters $sqlParams -ErrorAction Stop
        
        return $true
    }
    catch { return $false }
}