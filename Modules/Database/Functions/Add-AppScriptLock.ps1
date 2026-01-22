# Modules/Database/Functions/Add-AppScriptLock.ps1

<#
.SYNOPSIS
    Enregistre une nouvelle session de script active dans la base de données.
.DESCRIPTION
    Cette fonction insère une nouvelle ligne dans la table 'active_sessions' pour
    signaler qu'une instance d'un script a démarré, en enregistrant son nom et le PID
    du processus qui le détient.
.PARAMETER Script
    L'objet manifest (ou un objet similaire) du script à verrouiller. Doit contenir une propriété 'id'.
.PARAMETER OwnerPID
    Le Process ID ($PID) du script qui acquiert le verrou.
.EXAMPLE
    Add-AppScriptLock -Script $manifest -OwnerPID $PID
.OUTPUTS
    Aucune.
#>
function Add-AppScriptLock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Script,
        
        [Parameter(Mandatory)]
        [int]$OwnerPID
    )
    try {
        # --- UTILISATION DE REQUÊTES PARAMÉTRÉES POUR LA SÉCURITÉ ---
        # --- UTILISATION DE REQUÊTES PARAMÉTRÉES (v3.1) ---
        $startTime = (Get-Date -Format 'o')
        
        $query = "INSERT INTO active_sessions (ScriptName, OwnerPID, OwnerHost, StartTime) VALUES (@ScriptName, @OwnerPID, @OwnerHost, @StartTime);"
        $sqlParams = @{
            ScriptName = $Script.id
            OwnerPID   = $OwnerPID
            OwnerHost  = $env:COMPUTERNAME
            StartTime  = $startTime
        }
        
        Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $query -SqlParameters $sqlParams -ErrorAction Stop
        # -----------------------------------------------------------
        
        $logMsg = "{0} '{1}' {2} {3}." -f (Get-AppText 'modules.database.lock_registered_1'), $Script.id, (Get-AppText 'modules.database.lock_registered_2'), $OwnerPID
        Write-Verbose $logMsg
    }
    catch {
        $errorMsg = Get-AppText -Key 'modules.database.lock_register_error'
        throw "$errorMsg '$($Script.id)': $($_.Exception.Message)"
    }
}