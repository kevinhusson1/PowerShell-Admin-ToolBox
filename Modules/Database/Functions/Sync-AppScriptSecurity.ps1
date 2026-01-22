# Modules/Database/Functions/Sync-AppScriptSecurity.ps1

<#
.SYNOPSIS
    Met à jour la base de données de sécurité avec les scripts détectés.
.DESCRIPTION
    Pour chaque script fourni en paramètre :
    1. Vérifie s'il est déjà connu dans la table 'script_security'.
    2. Si non, insère les groupes par défaut définis dans son manifeste.
    3. Si oui, ne fait rien (on préserve les réglages faits par l'admin).
.PARAMETER Scripts
    La liste des objets scripts (provenant de Get-AppAvailableScript).
#>
function Sync-AppScriptSecurity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IEnumerable]$Scripts
    )

    foreach ($script in $Scripts) {
        # v3.1 Sanitization SQL
        
        # 1. Vérifier existence
        $checkQuery = "SELECT COUNT(1) as Cnt FROM script_security WHERE ScriptId = @ScriptId"
        # On définit les params pour le SELECT initiaux
        $selectParams = @{ ScriptId = $script.id }
        
        $count = (Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $checkQuery -SqlParameters $selectParams).Cnt

        # 2. Si le script n'est pas encore sécurisé en base, on l'initialise
        if ($count -eq 0) {
            if ($script.PSObject.Properties['security'] -and $script.security.allowedADGroups) {
                Write-Verbose "Initialisation sécurité BDD pour le script : '$($script.id)'"
                
                foreach ($group in $script.security.allowedADGroups) {
                    $paramGroup = $group.Trim()
                    if (-not [string]::IsNullOrWhiteSpace($paramGroup)) {
                        $insertQuery = "INSERT INTO script_security (ScriptId, ADGroup) VALUES (@ScriptId, @ADGroup);"
                        $insertParams = @{
                            ScriptId = $script.id
                            ADGroup  = $paramGroup
                        }
                        Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $insertQuery -SqlParameters $insertParams
                    }
                }
            }
        }
    }
}