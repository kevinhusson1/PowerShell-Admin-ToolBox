$projectRoot = 'c:\CLOUD\Github\PowerShell-Admin-ToolBox'
$env:PSModulePath = "$($projectRoot)\Modules;$($projectRoot)\Vendor;$($env:PSModulePath)"
Import-Module Microsoft.Graph.Authentication -MinimumVersion 2.32.0 -ErrorAction SilentlyContinue
[AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.FullName -match 'Azure\.Identity' } | Select-Object FullName, Location | Format-List | Out-File C:\CLOUD\Github\PowerShell-Admin-ToolBox\dll_output2.txt
