# Modules/Database/Functions/Set-AppScriptProgress.ps1

<#
.SYNOPSIS
    Insère ou met à jour l'état de progression d'un script en cours d'exécution.
.DESCRIPTION
    Utilise une requête "INSERT OR REPLACE" (UPSERT) pour créer ou modifier une ligne
    dans la table 'script_progress', en utilisant le PID comme clé unique.
.PARAMETER OwnerPID
    Le PID du processus de script qui rapporte sa progression.
.PARAMETER ProgressPercentage
    Le pourcentage d'avancement (0-100).
.PARAMETER StatusMessage
    Un court message décrivant l'étape en cours.
#>
function Set-AppScriptProgress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [int]$OwnerPID,
        [Parameter(Mandatory)] [int]$ProgressPercentage,
        [Parameter(Mandatory)] [string]$StatusMessage
    )
    try {
        # Sécurisation simple des entrées
        # Sécurisation SQL (v3.1)
        $query = "INSERT OR REPLACE INTO script_progress (OwnerPID, ProgressPercentage, StatusMessage) VALUES (@OwnerPID, @ProgressPercentage, @StatusMessage);"
        $sqlParams = @{
            OwnerPID           = $OwnerPID
            ProgressPercentage = $ProgressPercentage
            StatusMessage      = $StatusMessage
        }
        
        Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $query -SqlParameters $sqlParams -ErrorAction Stop

        Write-Verbose "Progression pour PID $OwnerPID mise à jour : $ProgressPercentage% - $StatusMessage"
    }
    catch {
        Write-Warning "Impossible de mettre à jour la progression pour le PID $OwnerPID : $($_.Exception.Message)"
    }
}