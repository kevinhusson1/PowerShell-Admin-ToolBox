# Modules/Database/Functions/Add-AppKnownGroup.ps1

function Add-AppKnownGroup {
    [CmdletBinding()]
    param([string]$GroupName, [string]$Description)
    
    # v3.1 Sanitization SQL
    $paramGroupName = $GroupName.Trim()
    $paramDesc = if ($Description) { $Description } else { "" }
    
    try {
        $query = "INSERT OR IGNORE INTO known_groups (GroupName, Description) VALUES (@GroupName, @Description);"
        $sqlParams = @{
            GroupName   = $paramGroupName
            Description = $paramDesc
        }
        Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $query -SqlParameters $sqlParams -ErrorAction Stop
        return $true
    }
    catch { return $false }
}