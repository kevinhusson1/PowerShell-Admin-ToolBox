# Scripts/Sharepoint/SharepointTest/Tests/debug_urls.ps1
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir "..\Shared\Init-TestEnvironment.ps1")
$siteId = Get-AppGraphSiteId -SiteUrl $Global:TestTargetSiteUrl
$lists = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/lists?`$select=displayName,webUrl"
foreach ($list in $lists.value) {
    if ($list.displayName -match "Builder") {
        Write-Output "LIST: $($list.displayName) -> URL: $($list.webUrl)"
    }
}
