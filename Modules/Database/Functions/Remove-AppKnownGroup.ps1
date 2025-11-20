# Modules/Database/Functions/Remove-AppKnownGroup.ps1

function Remove-AppKnownGroup {
    [CmdletBinding()]
    param([string]$GroupName)
    $safeName = $GroupName.Trim().Replace("'", "''")
    try {
        # On supprime du référentiel
        $q1 = "DELETE FROM known_groups WHERE GroupName = '$safeName';"
        Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $q1 -ErrorAction Stop
        
        # On nettoie aussi les associations existantes pour ne pas laisser de fantômes
        $q2 = "DELETE FROM script_security WHERE ADGroup = '$safeName';"
        Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $q2 -ErrorAction Stop
        
        return $true
    } catch { return $false }
}