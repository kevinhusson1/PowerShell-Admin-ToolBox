# Chemin du répertoire contenant le script du module
$PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition

# Charger les fonctions privées (non exportées)
Get-ChildItem -Path (Join-Path $PSScriptRoot "Private") -Filter "*.ps1" | ForEach-Object {
    . $_.FullName
}

# Charger les fonctions publiques (exportées)
Get-ChildItem -Path (Join-Path $PSScriptRoot "Functions") -Filter "*.ps1" | ForEach-Object {
    . $_.FullName
}