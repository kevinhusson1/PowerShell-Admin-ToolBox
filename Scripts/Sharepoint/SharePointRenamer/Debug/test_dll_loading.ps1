$ErrorActionPreference = "Stop"
$projectRoot = "c:\CLOUD\Github\PowerShell-Admin-ToolBox"
$env:PSModulePath = "$($projectRoot)\Modules;$($projectRoot)\Vendor;$($env:PSModulePath)"

Write-Output "--- AVANT IMPORTS ---"
[AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.FullName -match 'Azure\.Identity' } | Select-Object FullName, Location | Format-List

Write-Output "--- APRES Import-Module Microsoft.Graph.Authentication ---"
Import-Module Microsoft.Graph.Authentication -ErrorAction SilentlyContinue
[AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.FullName -match 'Azure\.Identity' } | Select-Object FullName, Location | Format-List

Write-Output "--- APRES Imports Toolbox ---"
Import-Module "PSSQLite", "Core", "UI", "Localization", "Logging", "Database", "Azure" -Force
[AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.FullName -match 'Azure\.Identity' } | Select-Object FullName, Location | Format-List
