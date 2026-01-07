<#
.SYNOPSIS
    Point d'entrée de la logique métier du Deployer (Orchestrateur).

.DESCRIPTION
    Charge les sous-fonctions logiques (V3 Architecture).
    Définit les Helpers Globaux (Find-ControlRecursive).
    Initialise la localisation locale.
    Récupère les contrôles et lance l'enregistrement des événements.
    C'est le "Chef d'Orchestre" qui relie l'UI statique (XAML) à la logique dynamique (PowerShell).

.PARAMETER Window
    Fenêtre WPF principale.

.PARAMETER ScriptRoot
    Chemin racine du script Deployer.
#>
function Initialize-DeployerLogic {
    param(
        [System.Windows.Window]$Window,
        [string]$ScriptRoot
    )

    # Helper Global pour éviter les problèmes de Scope dans les Closures complexes (Nested Closures)
    # Défini ici pour être visible partout dans la session de l'outil.
    function Global:Find-ControlRecursive {
        param($parent, $tagName)
        if (-not $parent) { return $null }

        # 1. Direct match
        if ("$($parent.Tag)" -eq $tagName) { return $parent }
        
        # 2. Children (Panel)
        if ($parent -is [System.Windows.Controls.Panel]) {
            foreach ($child in $parent.Children) {
                $res = Find-ControlRecursive -parent $child -tagName $tagName
                if ($res) { return $res }
            }
        }
        # 3. Content (ScrollViewer, ContentControl)
        elseif ($parent -is [System.Windows.Controls.ContentControl]) {
            if ($parent.Content) {
                $res = Find-ControlRecursive -parent $parent.Content -tagName $tagName
                if ($res) { return $res }
            }
        }
        # 4. Child (Decorator -> Border)
        elseif ($parent -is [System.Windows.Controls.Decorator]) {
            if ($parent.Child) {
                $res = Find-ControlRecursive -parent $parent.Child -tagName $tagName
                if ($res) { return $res }
            }
        }
        return $null
    }

    # 1. Chargement dynamique des sous-fonctions logiques (Architecture V3)
    $logicPath = Join-Path $ScriptRoot "Functions\Logic"
    if (Test-Path $logicPath) {
        Get-ChildItem -Path $logicPath -Filter "*.ps1" | ForEach-Object { 
            . $_.FullName 
        }
    }

    # 2. Localisation (Rechargement de sécurité)
    if ($Global:AppConfig.defaultLanguage) {
        $locPath = Join-Path $ScriptRoot "Localization\$($Global:AppConfig.defaultLanguage).json"
        if (Test-Path $locPath) { Add-AppLocalizationSource -FilePath $locPath }
    }

    # 3. Récupération centralisée des contrôles UI
    if (Get-Command Get-DeployerControls -ErrorAction SilentlyContinue) {
        $Ctrl = Get-DeployerControls -Window $Window
    }
    else {
        [System.Windows.MessageBox]::Show("Erreur interne : Get-DeployerControls introuvable.", "Erreur", "OK", "Error")
        return
    }

    if (-not $Ctrl) { return }

    # 4. Enregistrement des événements (Câblage)
    if (Get-Command Register-ConfigEvents -ErrorAction SilentlyContinue) {
        Register-ConfigEvents -Ctrl $Ctrl -Window $Window
    }
    
    if (Get-Command Register-FormEvents -ErrorAction SilentlyContinue) {
        Register-FormEvents -Ctrl $Ctrl -Window $Window
    }

    if (Get-Command Register-ActionEvents -ErrorAction SilentlyContinue) {
        Register-ActionEvents -Ctrl $Ctrl -Window $Window
    }
}
