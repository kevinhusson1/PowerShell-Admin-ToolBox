# Modules/Toolbox.SharePoint/Toolbox.SharePoint.psm1

$PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
Get-ChildItem -Path "$PSScriptRoot\Functions" -Filter "*.ps1" -Recurse | ForEach-Object {
    . $_.FullName
}
Export-ModuleMember -Function *