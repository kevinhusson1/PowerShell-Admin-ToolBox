# Modules/Localization/Localization.psm1

# Chemin du répertoire contenant le script du module
$PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$functionsPath = "$PSScriptRoot\Functions"

# Charger toutes les fonctions du sous-dossier "Functions"
Get-ChildItem -Path $functionsPath -Filter "*.ps1" | ForEach-Object {
    . $_.FullName
}

# Exporter les fonctions pour les rendre disponibles
Export-ModuleMember -Function * -Alias *