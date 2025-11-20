# Modules/Database/Functions/Get-AppScriptProgress.ps1

<#
.SYNOPSIS
    Récupère les informations de progression pour un ou tous les scripts.
.DESCRIPTION
    Lit la table 'script_progress'. Si un PID est fourni, ne retourne que la ligne
    correspondante. Sinon, retourne toutes les entrées de la table.
.PARAMETER OwnerPID
    [Optionnel] Le PID du script dont on veut récupérer la progression.
#>
function Get-AppScriptProgress {
    [CmdletBinding()]
    param(
        [int]$OwnerPID
    )
    try {
        $query = "SELECT * FROM script_progress"
        if ($PSBoundParameters.ContainsKey('OwnerPID')) {
            $query += " WHERE OwnerPID = $OwnerPID"
        }
        
        return Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $query -ErrorAction Stop
    }
    catch {
        Write-Warning "Impossible de récupérer les informations de progression : $($_.Exception.Message)"
        return $null
    }
}