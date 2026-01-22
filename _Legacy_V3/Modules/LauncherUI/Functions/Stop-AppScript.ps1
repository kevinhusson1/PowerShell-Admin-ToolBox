# Modules/LauncherUI/Functions/Stop-AppScript.ps1

<#
.SYNOPSIS
    Force l'arrêt d'un processus de script enfant et nettoie son verrou.
.DESCRIPTION
    Cette fonction est appelée par le bouton "Arrêter l'exécution".
    Elle utilise Stop-Process -Force pour terminer brutalement le processus.
    Puisque le processus enfant n'aura pas la chance d'exécuter son propre nettoyage,
    cette fonction prend la responsabilité de libérer le verrou dans la base de données
    pour éviter un verrou orphelin.
.PARAMETER SelectedScript
    L'objet script complet (enrichi) que l'utilisateur a demandé d'arrêter.
.EXAMPLE
    Stop-AppScript -SelectedScript $runningScript
.OUTPUTS
    Aucune.
#>
function Stop-AppScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$SelectedScript
    )

    if (-not $SelectedScript -or -not $SelectedScript.IsRunning) {
        return
    }

    try {
        $pidToStop = $SelectedScript.pid
        
        $logMessage = "{0} {1} {2} '{3}'." -f (Get-AppText 'modules.launcherui.stop_attempt_1'), $pidToStop, (Get-AppText 'modules.launcherui.stop_attempt_2'), $SelectedScript.name
        Write-LauncherLog -Message $logMessage -Level Warning

        # On arrête le processus de force
        Get-Process -Id $pidToStop | Stop-Process -Force -ErrorAction Stop

        # Le lanceur prend la responsabilité de nettoyer le verrou
        Unlock-AppScriptLock -OwnerPID $pidToStop

    } catch {    
        $warningMsg = Get-AppText -Key 'modules.launcherui.stop_process_error'
        # On tente quand même de nettoyer le verrou, au cas où le processus serait déjà mort mais le verrou encore présent
        if ($SelectedScript.pid) {
            Unlock-AppScriptLock -OwnerPID $SelectedScript.pid
        }
        Write-Warning "$warningMsg $($SelectedScript.pid): $($_.Exception.Message)"
    }
}