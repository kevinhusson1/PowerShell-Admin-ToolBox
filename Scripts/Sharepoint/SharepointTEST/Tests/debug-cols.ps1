$testRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $testRoot "..\Shared\Init-TestEnvironment.ps1")
$modPath = Join-Path $testRoot "..\..\..\..\Modules\Toolbox.SharePoint\Toolbox.SharePoint.psd1"
Import-Module $modPath -Force

Connect-AppAzureCert -TenantId $Global:TestTenantName -ClientId $Global:TestClientId -Thumbprint $Global:TestThumbprint
$siteId = Get-AppGraphSiteId -SiteUrl $Global:TestTargetSiteUrl
$libDrive = Get-AppGraphListDriveId -SiteId $siteId -ListDisplayName $Global:TestTargetLibrary

Write-Host "SiteID: $siteId"
Write-Host "ListID: $($libDrive.ListId)"
$columns = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/lists/$($libDrive.ListId)/columns"
$columns.value | Select-Object name, displayName | Format-Table -AutoSize
