# Modules/Database/Functions/Test-AppScriptLock.ps1

<#
.SYNOPSIS
    Vérifie si un script a le droit de s'exécuter (Concurrency check).
.DESCRIPTION
    Version Corrigée v2.0 : 
    Ne se fie PAS à la propriété 'maxConcurrentRuns' de l'objet passé en paramètre (qui peut venir d'un JSON obsolète).
    Interroge la base de données pour obtenir la configuration réelle en temps réel.
#>
function Test-AppScriptLock {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [psobject]$Script
    )

    try {
        $scriptId = $Script.id
        $safeScriptId = $scriptId.Replace("'", "''")

        # --- CORRECTION MAJEURE : On récupère la limite depuis la BDD ---
        # On ignore ce qu'il y a dans $Script.maxConcurrentRuns
        
        $queryConfig = "SELECT MaxConcurrentRuns FROM script_settings WHERE ScriptId = '$safeScriptId';"
        $dbConfig = Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $queryConfig -ErrorAction Stop
        
        $limit = 1 # Valeur par défaut si introuvable en BDD
        
        if ($dbConfig) {
            $limit = [int]$dbConfig.MaxConcurrentRuns
        } elseif ($Script.PSObject.Properties['maxConcurrentRuns']) {
            # Fallback sur le manifeste uniquement si la BDD est muette (cas rare)
            $limit = $Script.maxConcurrentRuns
        }

        $logLimit = if ($limit -eq -1) { "illimitées" } else { $limit }
        Write-Verbose (("{0} '{1}' : {2} {3}." -f (Get-AppText 'modules.database.lock_check_1'), $scriptId, (Get-AppText 'modules.database.lock_check_2'), $logLimit))

        if ($limit -eq -1) {
            return $true # Illimité
        }

        # --- Compter le nombre d'instances en cours ---
        $countQuery = "SELECT COUNT(*) AS RunCount FROM active_sessions WHERE ScriptName = '$safeScriptId';"
        $result = Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $countQuery -ErrorAction Stop
        $currentRuns = [int]$result.RunCount
        
        Write-Verbose (("{0} '{1}' : {2}." -f (Get-AppText 'modules.database.lock_check_3'), $scriptId, $currentRuns))

        # --- Vérification ---
        # Note : Si on est dans le script qui tente de se lancer, on ne s'est pas encore enregistré.
        # Donc si Limit=2 et qu'il y a déjà 2 instances, on refuse.
        if ($currentRuns -ge $limit) {
            $warningMsg = "{0} ($limit) {1} '$scriptId' {2}" -f (Get-AppText 'modules.database.lock_limit_reached_1'), (Get-AppText 'modules.database.lock_limit_reached_2'), (Get-AppText 'modules.database.lock_limit_reached_3')
            Write-Warning $warningMsg
            return $false
        }

        return $true
    }
    catch {
        $errorMsg = Get-AppText -Key 'modules.database.lock_check_error'
        Write-Warning "$errorMsg '$($Script.id)': $($_.Exception.Message)"
        return $false
    }
}