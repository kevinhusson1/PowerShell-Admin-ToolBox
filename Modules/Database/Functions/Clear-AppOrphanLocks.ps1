function Clear-AppOrphanLocks {
    [CmdletBinding()]
    param()

    try {
        # Requête 1 : Récupérer tous les verrous actifs
        # CORRECTION : La clé primaire est RunID
        $query = "SELECT RunID, ScriptName, OwnerPID FROM active_sessions"
        $sessions = Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $query -ErrorAction Stop

        if (-not $sessions) { return }

        $pidsToRemove = [System.Collections.Generic.List[int]]::new()

        foreach ($session in $sessions) {
            $pidToCheck = [int]$session.OwnerPID
            
            # Vérification si le processus existe
            if (-not (Get-Process -Id $pidToCheck -ErrorAction SilentlyContinue)) {
                $pidsToRemove.Add($pidToCheck)
                Write-Verbose "Verrou orphelin détecté : Script '$($session.ScriptName)' (PID: $pidToCheck - Processus absent)."
            }
        }

        # 2. Suppression en masse
        if ($pidsToRemove.Count -gt 0) {
            foreach ($orphanPid in $pidsToRemove) {
                # On utilise la fonction existante
                try {
                    Unlock-AppScriptLock -OwnerPID $orphanPid
                }
                catch {
                    Write-Warning "Erreur lors du déverrouillage orphelin (PID $orphanPid) : $($_.Exception.Message)"
                }
            }
            Write-Verbose "$($pidsToRemove.Count) verrous orphelins nettoyés."
        }
    }
    catch {
        $errorMsg = "Erreur lors du nettoyage des verrous orphelins"
        Write-Warning "$errorMsg : $($_.Exception.Message)"
    }
}
