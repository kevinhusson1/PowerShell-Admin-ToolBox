# Modules/Database/Functions/Get-AppKnownGroups.ps1

function Get-AppKnownGroups {
    [CmdletBinding()]
    param()
    try {
        return Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query "SELECT * FROM known_groups ORDER BY GroupName" -ErrorAction Stop
    } catch { return @() }
}