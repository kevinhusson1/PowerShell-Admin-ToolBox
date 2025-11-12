# Modules/Database/Functions/Clear-AppScriptLock.ps1

<#
.SYNOPSIS
    Supprime tous les verrous de scripts de la base de données.
.DESCRIPTION
    Cette fonction exécute une commande DELETE pour vider entièrement la table 'active_sessions'.
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
        $query = "DELETE FROM active_sessions;"
        
        # On appelle simplement la requête sans confirmation.
        Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $query -ErrorAction Stop
        
        $logMsg = Get-AppText -Key 'modules.database.all_locks_cleared'
        Write-Verbose $logMsg
        return $true
    }
    catch {
        $errorMsg = Get-AppText -Key 'modules.database.clear_locks_error'
        Write-Warning "$errorMsg : $($_.Exception.Message)"
        return $false
    }
}