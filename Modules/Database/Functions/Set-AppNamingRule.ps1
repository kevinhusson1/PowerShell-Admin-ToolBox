# Modules/Database/Functions/Set-AppNamingRule.ps1

function Set-AppNamingRule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$RuleId,
        [Parameter(Mandatory)] [string]$DefinitionJson,
        [string]$Description = "Règle personnalisée"
    )

    try {
        # v3.1 Sanitization SQL
        
        # Note: La table sp_naming_rules n'a pas forcément de colonne Description dans le schéma initial, 
        # mais le JSON envoyé contenait "Description". 
        # On assume ici le schéma standard (RuleId, DefinitionJson).
        # Si vous avez ajouté Description en BDD, ajoutez-le à la requête.
        # Ici je reste sur le schéma validé : RuleId, DefinitionJson.

        $query = "INSERT OR REPLACE INTO sp_naming_rules (RuleId, DefinitionJson) VALUES (@RuleId, @DefinitionJson);"
        $sqlParams = @{
            RuleId         = $RuleId
            DefinitionJson = $DefinitionJson
        }
        
        Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $query -SqlParameters $sqlParams -ErrorAction Stop
        return $true
    }
    catch {
        throw "Erreur sauvegarde règle : $($_.Exception.Message)"
    }
}