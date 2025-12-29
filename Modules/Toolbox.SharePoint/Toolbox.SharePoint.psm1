# Modules/Toolbox.SharePoint/Toolbox.SharePoint.psm1



# Chargement des dépendances
$loggingModule = Join-Path $PSScriptRoot "..\Logging"
if (Test-Path $loggingModule) {
    Import-Module $loggingModule -Force -ErrorAction SilentlyContinue
}

# Chargement des fonctions publiques
Get-ChildItem -Path (Join-Path $PSScriptRoot "Functions") -Filter "*.ps1" | ForEach-Object {
    . $_.FullName
}

Export-ModuleMember -Function *