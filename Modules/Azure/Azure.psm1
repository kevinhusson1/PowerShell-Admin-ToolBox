# Modules/Azure/Azure.psm1

$PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition

# Plus de chargement manuel dangereux des DLLs ici, 
# La gestion est faite au sommet de Launcher.ps1 et des scripts enfants.

Get-ChildItem -Path "$PSScriptRoot\Functions" -Filter "*.ps1" | ForEach-Object {
    . $_.FullName
}