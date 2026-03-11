$testRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $testRoot "..\Shared\Init-TestEnvironment.ps1")

Write-Host "Getting token via MSAL..."
$tokenParams = @{
    TenantId  = $Global:TestTenantName
    ClientId  = $Global:TestClientId
    Thumbprint = $Global:TestThumbprint
}
# Since we know Connect-MgGraph is problematic locally without MSAL, let's just use Connect-AppAzureCert
Import-Module (Join-Path $testRoot "..\..\..\..\Modules\Azure\Azure.psd1") -Force
Import-Module (Join-Path $testRoot "..\..\..\..\Modules\Toolbox.SharePoint\Toolbox.SharePoint.psd1") -Force

Connect-AppAzureCert @tokenParams

$siteId = Get-AppGraphSiteId -SiteUrl $Global:TestTargetSiteUrl
$libDrive = Get-AppGraphListDriveId -SiteId $siteId -ListDisplayName $Global:TestTargetLibrary

Write-Host "SiteID: $siteId"
Write-Host "ListID: $($libDrive.ListId)"

$uri = "https://graph.microsoft.com/v1.0/sites/$siteId/lists/$($libDrive.ListId)/columns"
try {
    $colsRes = Invoke-MgGraphRequest -Method GET -Uri $uri -ErrorAction Stop
    $colsRes.value | Select-Object name, displayName | Export-Csv "C:\CLOUD\Github\PowerShell-Admin-ToolBox\Scripts\Sharepoint\SharepointTEST\Tests\debug-cols-output.csv" -NoTypeInformation
    Write-Host "Cols exported."
}
catch {
    Write-Host "Failed to MG Graph: $($_.Exception.Message)"
}
