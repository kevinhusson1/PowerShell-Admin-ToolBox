# Modules/Database/Functions/Set-AppNamingRule.ps1

function Set-AppNamingRule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$RuleId,
        [Parameter(Mandatory)] [string]$DefinitionJson,
        [string]$Description = "Règle personnalisée"
    )

    try {
        $safeId = $RuleId.Replace("'", "''")
        $safeJson = $DefinitionJson.Replace("'", "''")
        $safeDesc = $Description.Replace("'", "''")

        # Note: La table sp_naming_rules n'a pas forcément de colonne Description dans le schéma initial, 
        # mais le JSON envoyé contenait "Description". 
        # On assume ici le schéma standard (RuleId, DefinitionJson).
        # Si vous avez ajouté Description en BDD, ajoutez-le à la requête.
        # Ici je reste sur le schéma validé : RuleId, DefinitionJson.

        $query = "INSERT OR REPLACE INTO sp_naming_rules (RuleId, DefinitionJson) VALUES ('$safeId', '$safeJson');"
        
        Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $query -ErrorAction Stop
        return $true
    }
    catch {
        throw "Erreur sauvegarde règle : $($_.Exception.Message)"
    }
}