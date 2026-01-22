# Scripts/test/hello.ps1
param($Name = "World")

Write-Output "Hello, $Name from PowerShell Core inside .NET 8!"
Write-Output "Current Time: $(Get-Date)"
Write-Output "Host Name: $($Host.Name)"
Write-Output "Process ID: $PID"

# Test Error handling
# Write-Error "This is a test error from PowerShell"
