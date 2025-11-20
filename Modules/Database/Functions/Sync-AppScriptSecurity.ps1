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
        # On sécurise l'ID pour le SQL
        $safeId = $script.id.Replace("'", "''")

        # 1. Vérifier existence
        # On utilise une requête COUNT rapide
        $checkQuery = "SELECT COUNT(1) as Cnt FROM script_security WHERE ScriptId = '$safeId'"
        $count = (Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $checkQuery).Cnt

        # 2. Si le script n'est pas encore sécurisé en base, on l'initialise
        if ($count -eq 0) {
            if ($script.PSObject.Properties['security'] -and $script.security.allowedADGroups) {
                Write-Verbose "Initialisation sécurité BDD pour le script : '$($script.id)'"
                
                foreach ($group in $script.security.allowedADGroups) {
                    $safeGroup = $group.Trim().Replace("'", "''")
                    if (-not [string]::IsNullOrWhiteSpace($safeGroup)) {
                        $insertQuery = "INSERT INTO script_security (ScriptId, ADGroup) VALUES ('$safeId', '$safeGroup');"
                        Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $insertQuery
                    }
                }
            }
        }
    }
}