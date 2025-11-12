# Modules/LauncherUI/Functions/Update-ScriptListBoxUI.ps1

<#
.SYNOPSIS
    Met à jour l'interface de la liste des scripts et de la barre de statut.
.DESCRIPTION
    Cette fonction est le point d'entrée unique pour rafraîchir la grille des scripts.
    Elle prend en charge la mise à jour de la propriété ItemsSource de la ListBox de manière
    sécurisée (via le Dispatcher) et gère le cas où la source de données n'est pas une
    collection (un bug courant en PowerShell).
    Elle met également à jour le texte de la barre de statut pour refléter les
    nouveaux comptes de scripts.
.PARAMETER scripts
    La source de données pour la liste. Peut être une collection d'objets script
    ou un objet script unique. La fonction gère les deux cas.
.EXAMPLE
    Update-ScriptListBoxUI -scripts $Global:AppAvailableScripts
.OUTPUTS
    Aucune.
#>
function Update-ScriptListBoxUI {
    [CmdletBinding()]
    param(
        $scripts
    )

    # On prépare une variable qui sera TOUJOURS une collection.
    $collection = $null

    # Si $scripts n'est pas déjà une collection (cas où il n'y a qu'un seul objet),
    # on le met nous-mêmes dans un tableau. C'est une sécurité cruciale.
    if ($scripts -isnot [System.Collections.IEnumerable] -and $null -ne $scripts) {
        $collection = @($scripts)
    } else {
        $collection = $scripts
    }
    $collectionCount = if ($null -ne $collection) { $collection.Count } else { 0 }

    $logMsg = "{0} {1} {2}" -f (Get-AppText 'modules.launcherui.updating_script_list_ui_1'), $collectionCount, (Get-AppText 'modules.launcherui.updating_script_list_ui_2')
    Write-Verbose $logMsg

    # Mettre à jour la ListBox via le Dispatcher pour la sécurité des threads.
    $Global:AppControls.scriptsListBox.Dispatcher.Invoke([Action]{
        $Global:AppControls.scriptsListBox.ItemsSource = $null
        $Global:AppControls.scriptsListBox.ItemsSource = $collection
    })
    
    # Mettre à jour la barre de statut.
    $activeScriptsCount = ($Global:AppActiveScripts | Where-Object { $_.HasExited -eq $false }).Count
    $Global:AppControls.statusTextBlock.Text = "$(Get-AppText 'launcher.status_available') : $collectionCount  •  $(Get-AppText 'launcher.status_active') : $activeScriptsCount"
}