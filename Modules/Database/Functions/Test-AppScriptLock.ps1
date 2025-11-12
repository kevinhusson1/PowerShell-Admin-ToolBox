# Modules/Database/Functions/Test-AppScriptLock.ps1

<#
.SYNOPSIS
    Vérifie si un script a le droit de s'exécuter en fonction des limites de concurrence.
.DESCRIPTION
    Cette fonction lit la configuration 'maxConcurrentRuns' du manifeste d'un script.
    Elle interroge ensuite la base de données pour compter le nombre d'instances
    de ce script déjà en cours d'exécution.
    Elle retourne $true si le lancement est autorisé, et $false sinon.
.PARAMETER Script
    L'objet manifest (ou un objet similaire) du script à vérifier. Doit contenir
    les propriétés 'id' et optionnellement 'maxConcurrentRuns'.
.EXAMPLE
    if (Test-AppScriptLock -Script $manifest) { # Lancement autorisé }
.OUTPUTS
    [bool] - $true si le script peut se lancer, $false sinon.
#>
function Test-AppScriptLock {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [psobject]$Script
    )

    try {
        # --- 1. Déterminer la limite d'exécutions simultanées ---
        $limit = 1 # Valeur par défaut si non spécifié
        if ($Script.PSObject.Properties['maxConcurrentRuns']) {
            $limit = $Script.maxConcurrentRuns
        }
        $logLimit = if ($limit -eq -1) { "illimitées" } else { $limit }
        Write-Verbose (("{0} '{1}' : {2} {3}." -f (Get-AppText 'modules.database.lock_check_1'), $Script.id, (Get-AppText 'modules.database.lock_check_2'), $logLimit))

        if ($limit -eq -1) {
            return $true # Illimité, pas besoin de vérifier la base de données.
        }

        # --- 2. Compter le nombre d'instances déjà en cours (de manière sécurisée) ---
        $safeScriptId = $Script.id.Replace("'", "''")
        $countQuery = "SELECT COUNT(*) AS RunCount FROM active_sessions WHERE ScriptName = '$safeScriptId';"
        
        $result = Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $countQuery -ErrorAction Stop
        $currentRuns = $result.RunCount
        
        Write-Verbose (("{0} '{1}' : {2}." -f (Get-AppText 'modules.database.lock_check_3'), $Script.id, $currentRuns))

        # --- 3. Comparer à la limite ---
        if ($currentRuns -ge $limit) {
            $warningMsg = "{0} ($limit) {1} '$($Script.id)' {2}" -f (Get-AppText 'modules.database.lock_limit_reached_1'), (Get-AppText 'modules.database.lock_limit_reached_2'), (Get-AppText 'modules.database.lock_limit_reached_3')
            Write-Warning $warningMsg
            return $false
        }

        # Si on arrive ici, le lancement est autorisé.
        return $true
    }
    catch {
        $errorMsg = Get-AppText -Key 'modules.database.lock_check_error'
        Write-Warning "$errorMsg '$($Script.id)': $($_.Exception.Message)"
        return $false # Par sécurité, on refuse le verrou en cas d'erreur.
    }
}