# Modules/Database/Functions/Get-AppScriptSettingsMap.ps1

<#
.SYNOPSIS
    Récupère tous les paramètres de scripts sous forme de Hashtable.
.OUTPUTS
    Hashtable : Clé = ScriptId, Valeur = PSCustomObject { IsEnabled, MaxConcurrentRuns }
#>
function Get-AppScriptSettingsMap {
    [CmdletBinding()]
    param()

    $map = @{}
    try {
        $rows = Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query "SELECT * FROM script_settings"
        if ($rows) {
            foreach ($r in $rows) {
                $map[$r.ScriptId] = [PSCustomObject]@{
                    IsEnabled = [bool]$r.IsEnabled
                    MaxConcurrentRuns = [int]$r.MaxConcurrentRuns
                }
            }
        }
    } catch { Write-Warning "Erreur lecture settings map: $_" }
    return $map
}