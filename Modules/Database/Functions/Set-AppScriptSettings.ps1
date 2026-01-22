# Modules/Database/Functions/Set-AppScriptSettings.ps1

<#
.SYNOPSIS
    Met à jour les paramètres d'un script (État et Concurrence).
#>
function Set-AppScriptSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$ScriptId,
        [Parameter(Mandatory)] [bool]$IsEnabled,
        [Parameter(Mandatory)] [int]$MaxConcurrentRuns
    )

    # v3.1 Sanitization SQL
    $intEnabled = if ($IsEnabled) { 1 } else { 0 }

    try {
        $query = "INSERT OR REPLACE INTO script_settings (ScriptId, IsEnabled, MaxConcurrentRuns) VALUES (@ScriptId, @IsEnabled, @MaxConcurrentRuns);"
        $sqlParams = @{
            ScriptId          = $ScriptId
            IsEnabled         = $intEnabled
            MaxConcurrentRuns = $MaxConcurrentRuns
        }
        
        Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $query -SqlParameters $sqlParams -ErrorAction Stop
        Write-Verbose "Paramètres mis à jour pour '$ScriptId'."
        return $true
    }
    catch {
        Write-Warning "Erreur sauvegarde settings : $($_.Exception.Message)"
        return $false
    }
}