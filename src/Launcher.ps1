# src/Launcher.ps1
# Point d'entrée principal de la PowerShell Admin ToolBox

$ErrorActionPreference = 'Stop'

try {
    # Définir les chemins de base
    $scriptRoot = $PSScriptRoot
    $appRoot = (Resolve-Path (Join-Path $scriptRoot "..")).Path
    $coreModulePath = Join-Path $appRoot "src/Core/PSToolBox.Core.psm1"

    # Importer le module utilitaire
    Import-Module -Path $coreModulePath

    # Charger la configuration (à implémenter dans une fonction du module Core plus tard)
    $configPath = Join-Path $appRoot "config.json"
    if (-not (Test-Path $configPath)) {
        throw "Le fichier de configuration 'config.json' est introuvable. Veuillez copier 'config.template.json' et le remplir."
    }
    $config = Get-Content -Path $configPath | ConvertFrom-Json

    # Charger le dictionnaire de styles central
    $stylesXamlPath = Join-Path $appRoot "src/UI/Styles.xaml"
    $stylesDictionary = Load-WpfXaml -Path $stylesXamlPath # On supposera que Load-WpfXaml existe dans le module Core

    # Définir le ViewModel de la fenêtre principale
    $mainViewModel = [PSCustomObject]@{
        AvailableTools = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
        SelectedTool   = $null
    }

    # Charger les outils disponibles (à implémenter)
    # Load-Tools -ViewModel $mainViewModel -ToolsPath (Join-Path $appRoot "src/Tools")

    # Charger la vue principale (fenêtre XAML)
    $mainWindowXamlPath = Join-Path $appRoot "src/UI/ToolBox.View.xaml" # On renomme le XAML
    $mainWindow = Load-WpfXaml -Path $mainWindowXamlPath -Styles $stylesDictionary

    # Lier le ViewModel à la fenêtre
    $mainWindow.DataContext = $mainViewModel
    
    # Afficher la fenêtre
    $null = $mainWindow.ShowDialog()

} catch {
    # Afficher les erreurs critiques dans une MessageBox
    [System.Windows.MessageBox]::Show($_.Exception.Message, "Erreur Fatale", "OK", "Error")
}