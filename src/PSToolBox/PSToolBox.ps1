# =================================================================
# PowerShell Admin ToolBox - Point d'Entrée Principal
# =================================================================

# --- Initialisation de l'environnement ---
$ProjectRoot = (Get-Item $PSScriptRoot).Parent.Parent.FullName # Remonte de PSToolBox -> src -> Racine
$CoreModulePath = Join-Path $ProjectRoot "src/Modules/PSToolBox.Core/PSToolBox.Core.psd1"
$MainViewModelPath = Join-Path $ProjectRoot "src/PSToolBox/ViewModels/Main.ViewModel.ps1"
$MainViewPath = Join-Path $ProjectRoot "src/PSToolBox/Views/MainWindow.xaml"

# --- Importation de notre framework ---
Import-Module $CoreModulePath -Force

# --- Préparation du ViewModel Principal ---
# On exécute le script du ViewModel pour créer notre objet $mainViewModel
. $MainViewModelPath

# --- Lancement de la Fenêtre Principale via notre service ---
Show-ToolBoxWindow -ViewPath $MainViewPath -ViewModel $mainViewModel -IsDialog

Write-Host "Application ToolBox fermée."