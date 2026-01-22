# Modules/Database/Functions/Clear-AppScriptLock.ps1

<#
.SYNOPSIS
    Supprime tous les verrous de scripts de la base de données.
.DESCRIPTION
    Cette fonction exécute une commande DELETE pour vider entièrement la table 'active_sessions' et 'script_progress'.
    Elle est conçue comme un outil de maintenance pour les administrateurs afin de
    résoudre des situations de verrous orphelins.
.EXAMPLE
    Clear-AppScriptLock
.OUTPUTS
    [bool] - Retourne $true en cas de succès, $false en cas d'erreur.
#>
function Clear-AppScriptLock {
    [CmdletBinding()]
    param()

    try {
        # Requête 1 : Vider la table des sessions actives (verrous)
        $queryLocks = "DELETE FROM active_sessions;"
        Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $queryLocks -ErrorAction Stop
        
        # Requête 2 : Vider la table de progression des scripts
        $queryProgress = "DELETE FROM script_progress;"
        Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $queryProgress -ErrorAction Stop

        $logMsg = Get-AppText -Key 'modules.database.all_locks_cleared'
        Write-Verbose "$logMsg"
        return $true
    }
    catch {
        $errorMsg = Get-AppText -Key 'modules.database.clear_locks_error'
        Write-Warning "$errorMsg : $($_.Exception.Message)"
        return $false
    }
}