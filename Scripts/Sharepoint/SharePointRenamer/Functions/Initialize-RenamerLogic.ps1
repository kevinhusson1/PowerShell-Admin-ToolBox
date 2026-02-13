<#
.SYNOPSIS
    Point d'entrée de la logique métier du Renamer (Orchestrateur).

.DESCRIPTION
    Fonction principale appelée par le script maître 'SharePointRenamer.ps1'.
    Son rôle est de :
    1. Charger dynamiquement tous les scripts du dossier 'Functions/Logic'.
    2. Définir des Helpers globaux (comme Find-ControlRecursive).
    3. Charger la localisation spécifique au plugin.
    4. Initialiser la Hashtable des contrôles UI ($Ctrl).
    5. Appeler les fonctions d'enregistrement d'événements (Configs, Forms, Actions).
#>
function Initialize-RenamerLogic {
    param(
        [System.Windows.Window]$Window,
        [string]$ScriptRoot
    )

    # 1. Chargement des sous-fonctions Logic
    $logicPath = Join-Path $ScriptRoot "Functions\Logic"
    if (Test-Path $logicPath) {
        Get-ChildItem -Path $logicPath -Filter "*.ps1" -Recurse | ForEach-Object { . $_.FullName }
    }

    # 2. Helpers Globaux
    # Helper pour la recherche récursive de Tag (Compatible String & Hashtable)
    function Global:Find-ControlRecursive {
        param($parent, $tagName)
        if (-not $parent) { return $null }

        # 1. Direct match (Compatible String & Hashtable)
        if ($parent.Tag -is [System.Collections.IDictionary]) {
            if ($parent.Tag.Key -eq $tagName) { return $parent }
        }
        elseif ("$($parent.Tag)" -eq $tagName) { return $parent }
        
        # 2. Children (Panel)
        if ($parent -is [System.Windows.Controls.Panel]) {
            foreach ($child in $parent.Children) {
                $res = Find-ControlRecursive -parent $child -tagName $tagName
                if ($res) { return $res }
            }
        }
        # 3. Content (ContentControl ex: ScrollViewer, Border)
        if ($parent -is [System.Windows.Controls.ContentControl]) {
            if ($parent.Content -is [System.Windows.UIElement]) {
                $res = Find-ControlRecursive -parent $parent.Content -tagName $tagName
                if ($res) { return $res }
            }
        }
        # 4. Decorator (Border etc)
        if ($parent -is [System.Windows.Controls.Decorator]) {
            if ($parent.Child -is [System.Windows.UIElement]) {
                $res = Find-ControlRecursive -parent $parent.Child -tagName $tagName
                if ($res) { return $res }
            }
        }
        return $null
    }
    
    # 3. Localisation
    # On charge le fichier de langue du Renamer s'il existe, sinon fallback Deployer/Global
    $lang = $Global:AppConfig.defaultLanguage
    $locFile = Join-Path $ScriptRoot "Localization\$lang.json"
    if (Test-Path $locFile) {
        Add-AppLocalizationSource -FilePath $locFile
    }

    # 4. Initialisation Contrôles & Events
    $Ctrl = Get-RenamerControls -Window $Window
    
    # Masquer panels par défaut
    $Ctrl.FormPanel.Visibility = "Collapsed"
    
    # Enregistrement des événements
    Register-RenamerConfigEvents -Ctrl $Ctrl -Window $Window
    Register-RenamerPickerEvents -Ctrl $Ctrl -Window $Window
    Register-RenamerFormEvents -Ctrl $Ctrl -Window $Window
    Register-RenamerActionEvents -Ctrl $Ctrl -Window $Window
}
