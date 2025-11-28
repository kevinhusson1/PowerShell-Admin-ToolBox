# Modules/Toolbox.SharePoint/Toolbox.SharePoint.psm1

$PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition

# Chargement des fonctions publiques
Get-ChildItem -Path (Join-Path $PSScriptRoot "Functions") -Filter "*.ps1" | ForEach-Object {
    . $_.FullName
}

Export-ModuleMember -Function *