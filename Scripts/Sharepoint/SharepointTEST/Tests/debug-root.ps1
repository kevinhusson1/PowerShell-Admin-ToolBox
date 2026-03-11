$testRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $testRoot "..\Shared\Init-TestEnvironment.ps1")
$modPath = Join-Path $testRoot "..\..\..\..\Modules\Toolbox.SharePoint\Toolbox.SharePoint.psd1"
Import-Module $modPath -Force

$siteId = Get-AppGraphSiteId -SiteUrl $Global:TestTargetSiteUrl
$libDrive = Get-AppGraphListDriveId -SiteId $siteId -ListDisplayName $Global:TestTargetLibrary

$rootRes = New-AppGraphFolder -SiteId $siteId -DriveId $libDrive.DriveId -FolderName "DebugRoot_123" -ParentFolderId "root"

Write-Host "Dump de RootRes :"
$rootRes | Format-List *

Write-Host "Id : $($rootRes.id)"
Write-Host "Type of Id : $($rootRes.id.GetType().Name)"
