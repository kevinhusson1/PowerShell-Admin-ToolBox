$testRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $testRoot "..\Shared\Init-TestEnvironment.ps1")
$modPath = Join-Path $testRoot "..\..\..\..\Modules\Toolbox.SharePoint\Toolbox.SharePoint.psd1"
Import-Module $modPath -Force

$tplPath = Join-Path $testRoot "..\Data\sp_templates.json"
$tplData = Get-Content $tplPath -Raw | ConvertFrom-Json
$deployTemplate = $tplData[0]

$structure = $deployTemplate.StructureJson | ConvertFrom-Json

Write-Host "Lancement Test-AppSPModel sur la structure..."
$res = Test-AppSPModel -StructureData $structure

Write-Host "Résultats :"
$res | Format-Table -AutoSize
