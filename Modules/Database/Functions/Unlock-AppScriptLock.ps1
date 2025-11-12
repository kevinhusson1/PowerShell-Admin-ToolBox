# Modules/Database/Functions/Unlock-AppScriptLock.ps1

<#
.SYNOPSIS
    Libère un verrou de script en supprimant sa session de la base de données.
.DESCRIPTION
    Cette fonction supprime la ligne correspondante à un Process ID (PID)
    spécifique de la table 'active_sessions'. Elle est appelée à la fin de
    l'exécution d'un script (normalement ou forcée) pour signaler qu'une
    place s'est libérée.
.PARAMETER OwnerPID
    Le Process ID ($PID) du script dont le verrou doit être libéré.
.EXAMPLE
    # Dans le bloc 'finally' d'un script enfant
    Unlock-AppScriptLock -OwnerPID $PID
.OUTPUTS
    Aucune.
#>
function Unlock-AppScriptLock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$OwnerPID
    )
    try {
        # La concaténation d'un [int] est sûre, pas de risque d'injection.
        # La validation de type est faite par le paramètre [int]$OwnerPID.
        $query = "DELETE FROM active_sessions WHERE OwnerPID = $OwnerPID;"
        
        Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $query -ErrorAction Stop

        $logMsg = "{0} {1} {2}" -f (Get-AppText 'modules.database.lock_released_1'), $OwnerPID, (Get-AppText 'modules.database.lock_released_2')
        Write-Verbose $logMsg
    }
    catch {
        $errorMsg = Get-AppText -Key 'modules.database.lock_release_error'
        Write-Warning "$errorMsg $OwnerPID : $($_.Exception.Message)"
    }
}