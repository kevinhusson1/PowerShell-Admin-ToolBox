<#
.SYNOPSIS
    Charge et fusionne les dictionnaires de ressources XAML nécessaires dans une fenêtre.
.DESCRIPTION
    Cette fonction est responsable du système de design de l'application. Elle charge
    les styles de base (Couleurs, Typographie) puis charge dynamiquement des groupes
    de composants d'interface (Boutons, Champs de saisie, etc.) en fonction des
    besoins de la fenêtre qui l'appelle.
    Chaque composant est un dictionnaire de ressources XAML qui est fusionné dans
    les ressources de la fenêtre principale.
.PARAMETER Window
    La fenêtre WPF ([System.Windows.Window]) dans laquelle les ressources doivent être chargées.
.PARAMETER ProjectRoot
    Le chemin racine du projet pour localiser le dossier /Templates.
.PARAMETER Components
    [Optionnel] Un tableau de chaînes de caractères listant les groupes de composants à charger.
    Si non spécifié, un ensemble par défaut est chargé.
.EXAMPLE
    # Charge les composants nécessaires pour le lanceur
    Initialize-AppUIComponents -Window $mainWindow -ProjectRoot $projectRoot -Components 'Buttons', 'Inputs', 'Display', 'Navigation'
.OUTPUTS
    Aucune.
#>
function Initialize-AppUIComponents {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Window]$Window,

        [Parameter(Mandatory)]
        [string]$ProjectRoot,

        [Parameter()]
        [string[]]$Components
    )

    try {
        # Définir les ressources de base toujours chargées
        $baseResources = @(
            "$ProjectRoot\Templates\Styles\Colors.xaml",
            "$ProjectRoot\Templates\Styles\Typography.xaml"
        )
        
        # --- CORRECTION DE LA LISTE DES COMPOSANTS ---
        # On définit tous les composants disponibles et leurs fichiers XAML respectifs.
        $availableComponents = @{
            'Buttons' = @(
                "$ProjectRoot\Templates\Components\Buttons\PrimaryButton.xaml",
                "$ProjectRoot\Templates\Components\Buttons\SecondaryButton.xaml",
                "$ProjectRoot\Templates\Components\Buttons\GreenButton.xaml",
                "$ProjectRoot\Templates\Components\Buttons\RedButton.xaml",
                "$ProjectRoot\Templates\Components\Buttons\IconButton.xaml"
            );
            'Inputs' = @(
                "$ProjectRoot\Templates\Components\Inputs\ComboBox.xaml",
                "$ProjectRoot\Templates\Components\Inputs\PasswordBox.xaml",
                "$ProjectRoot\Templates\Components\Inputs\RadioButton.xaml",
                "$ProjectRoot\Templates\Components\Inputs\TextBox.xaml",
                "$ProjectRoot\Templates\Components\Inputs\ToggleSwitch.xaml"
            );
            'Display' = @(
                "$ProjectRoot\Templates\Components\Display\ListBox.xaml",
                "$ProjectRoot\Templates\Components\Display\LogViewer.xaml"
            );
            'Navigation' = @(
                "$ProjectRoot\Templates\Components\Navigation\TabControl.xaml" 
            );
            'ProfileButton' = @(
                "$ProjectRoot\Templates\Components\Buttons\ProfileButton.xaml"
            );
            'Layouts' = @(
                "$ProjectRoot\Templates\Components\Layouts\CardExpander.xaml",
                "$ProjectRoot\Templates\Components\Layouts\FormField.xaml"
            );
            'LauncherDisplay' = @(
                "$ProjectRoot\Templates\Components\Launcher\ScriptTile.xaml" # Chemin corrigé
            );
        }
        # -----------------------------------------------

        # Déterminer les composants à charger
        $componentsToLoad = if ($Components) { $Components } else { @('Buttons', 'Inputs') }

        # Construire la liste finale des fichiers XAML à charger
        $filesToLoad = $baseResources
        foreach ($componentName in $componentsToLoad) {
            if ($availableComponents.ContainsKey($componentName)) {
                $filesToLoad += $availableComponents[$componentName]
            } else {
                $warningMsg = "{0} '{1}' {2}" -f (Get-AppText 'modules.ui.component_unknown_1'), $componentName, (Get-AppText 'modules.ui.component_unknown_2')
                Write-Warning $warningMsg
            }
        }
        
        Write-Verbose (("{0} {1} {2}." -f (Get-AppText 'modules.ui.loading_components_1'), $filesToLoad.Count, (Get-AppText 'modules.ui.loading_components_2')))

        # Charger et fusionner les ressources
        foreach ($file in $filesToLoad) {
            if(Test-Path $file) {
                Write-Verbose "    -> $file"
                $resourceDictionary = Import-AppXamlTemplate -XamlPath $file
                $Window.Resources.MergedDictionaries.Add($resourceDictionary)
            } else {
                $warningMsg = "{0} '{1}' {2}" -f (Get-AppText 'modules.ui.style_file_not_found_1'), $file, (Get-AppText 'modules.ui.style_file_not_found_2')
                Write-Warning $warningMsg
            }
        }
    }
    catch {
        $errorMsg = Get-AppText -Key 'modules.ui.component_init_error'
        throw "$errorMsg : $($_.Exception.Message)"
    }
}