# Fichier principal du module PSToolBox.Core
# Ce script est exécuté lors de l'importation du module (Import-Module).

Write-Verbose "Chargement du module PSToolBox.Core..."

# Le chemin du dossier où se trouve ce fichier .psm1
$ModuleRoot = $PSScriptRoot

# Lister et charger (dot-source) toutes les fonctions publiques et privées.
# L'enrobage @(...) garantit que nous avons TOUJOURS un tableau, même avec 0 ou 1 résultat.
$PublicFunctions = @(Get-ChildItem -Path (Join-Path $ModuleRoot "Public/*.ps1") -ErrorAction SilentlyContinue)
$PrivateFunctions = @(Get-ChildItem -Path (Join-Path $ModuleRoot "Private/*.ps1") -ErrorAction SilentlyContinue)

# L'addition de deux tableaux fonctionne toujours parfaitement.
foreach ($FunctionFile in ($PublicFunctions + $PrivateFunctions)) {
    try {
        . $FunctionFile.FullName
    }
    catch {
        Write-Error "Impossible de charger la fonction '$($FunctionFile.Name)': $($_.Exception.Message)"
    }
}

Write-Verbose "Module PSToolBox.Core chargé."