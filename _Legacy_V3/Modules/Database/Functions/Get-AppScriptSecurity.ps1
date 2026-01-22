# Modules/Database/Functions/Get-AppScriptSecurity.ps1

<#
.SYNOPSIS
    Récupère les règles de sécurité des scripts depuis la base de données.
.DESCRIPTION
    Retourne une Hashtable où la Clé est l'ID du script et la Valeur est un tableau des groupes AD autorisés.
    Cela permet une vérification ultra-rapide côté UI.
.OUTPUTS
    [System.Collections.Hashtable]
#>
function Get-AppScriptSecurity {
    [CmdletBinding()]
    param()

    try {
        $query = "SELECT ScriptId, ADGroup FROM script_security"
        $rows = Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $query -ErrorAction Stop

        $securityMap = @{}
        
        if ($rows) {
            foreach ($row in $rows) {
                if (-not $securityMap.ContainsKey($row.ScriptId)) {
                    $securityMap[$row.ScriptId] = [System.Collections.Generic.List[string]]::new()
                }
                $securityMap[$row.ScriptId].Add($row.ADGroup)
            }
        }
        
        return $securityMap
    }
    catch {
        Write-Warning "Impossible de récupérer la sécurité des scripts : $($_.Exception.Message)"
        return @{}
    }
}