# Modules/LauncherUI/Functions/Update-ScriptListBoxUI.ps1

<#
.SYNOPSIS
    Met à jour l'interface de la liste des scripts et de la barre de statut.
.DESCRIPTION
    Filtre les scripts pour n'afficher que ceux qui sont ACTIVÉS (enabled=true).
    Met à jour la grille et le compteur en bas de page.
#>
function Update-ScriptListBoxUI {
    [CmdletBinding()]
    param(
        $scripts
    )

    # 1. Transformation sécurisée en tableau (Collection)
    $collection = if ($scripts -isnot [System.Collections.IEnumerable] -and $null -ne $scripts) { @($scripts) } else { $scripts }

    # 2. FILTRAGE : On ne garde que les scripts ACTIVÉS pour l'onglet Accueil
    $visibleScripts = @($collection | Where-Object { $_.enabled -eq $true })
    
    # 3. COMPTAGE : On compte ce qui va être affiché
    $visibleCount = $visibleScripts.Count
    
    # 4. COMPTAGE ACTIFS : On compte les processus en cours
    $activeScriptsCount = ($Global:AppActiveScripts | Where-Object { $_.HasExited -eq $false }).Count

    # 5. Mise à jour UI
    $Global:AppControls.scriptsListBox.Dispatcher.Invoke([Action]{
        # Mise à jour de la liste
        $Global:AppControls.scriptsListBox.ItemsSource = $null
        $Global:AppControls.scriptsListBox.ItemsSource = $visibleScripts
        
        # Mise à jour de la barre de statut avec le bon chiffre ($visibleCount)
        $statusText = "{0} : {1}  •  {2} : {3}" -f (Get-AppText 'launcher.status_available'), $visibleCount, (Get-AppText 'launcher.status_active'), $activeScriptsCount
        $Global:AppControls.statusTextBlock.Text = $statusText
    })
}