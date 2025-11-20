# Modules/Database/Functions/Add-AppKnownGroup.ps1

function Add-AppKnownGroup {
    [CmdletBinding()]
    param([string]$GroupName, [string]$Description)
    
    $safeName = $GroupName.Trim().Replace("'", "''")
    $safeDesc = if ($Description) { $Description.Replace("'", "''") } else { "" }
    
    try {
        $query = "INSERT OR IGNORE INTO known_groups (GroupName, Description) VALUES ('$safeName', '$safeDesc');"
        Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $query -ErrorAction Stop
        return $true
    } catch { return $false }
}