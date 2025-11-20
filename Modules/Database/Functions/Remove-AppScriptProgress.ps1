# Modules/Database/Functions/Remove-AppScriptProgress.ps1

<#
.SYNOPSIS
    Supprime une entrée de progression de la base de données.
.DESCRIPTION
    Appelé lorsqu'un script a terminé son initialisation ou est arrêté,
    pour nettoyer sa ligne dans la table 'script_progress'.
.PARAMETER OwnerPID
    Le PID de la session de progression à supprimer.
#>
function Remove-AppScriptProgress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [int]$OwnerPID
    )
    try {
        $query = "DELETE FROM script_progress WHERE OwnerPID = $OwnerPID;"
        Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $query -ErrorAction Stop
        Write-Verbose "Entrée de progression pour le PID $OwnerPID supprimée."
    }
    catch {
        Write-Warning "Impossible de supprimer l'entrée de progression pour le PID $OwnerPID : $($_.Exception.Message)"
    }
}