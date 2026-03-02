$projectRoot = 'c:\CLOUD\Github\PowerShell-Admin-ToolBox'
$env:PSModulePath = "$($projectRoot)\Modules;$($projectRoot)\Vendor;$($env:PSModulePath)"
Import-Module Microsoft.Graph.Authentication -ErrorAction SilentlyContinue
Import-Module 'PSSQLite', 'Core', 'UI', 'Localization', 'Logging', 'Database', 'Azure' -Force
[AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.FullName -match 'Azure\.Identity' } | Select-Object FullName, Location | Format-List | Out-File C:\CLOUD\Github\PowerShell-Admin-ToolBox\dll_output.txt
