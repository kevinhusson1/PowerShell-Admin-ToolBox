# Modules/Database/Functions/Set-AppSetting.ps1

<#
.SYNOPSIS
    Sauvegarde ou met à jour un paramètre de configuration dans la base de données.
.DESCRIPTION
    Cette fonction insère une nouvelle ligne dans la table 'settings' ou met à jour
    une ligne existante si la clé est déjà présente (comportement "upsert").
    Elle détecte automatiquement le type de la valeur fournie et le stocke.
.PARAMETER Key
    La clé unique du paramètre à sauvegarder (ex: 'app.companyName').
.PARAMETER Value
    La valeur à sauvegarder. Le type peut être [string], [int], ou [bool].
.EXAMPLE
    Set-AppSetting -Key 'app.companyName' -Value "Nouvelle Entreprise"
.OUTPUTS
    Aucune.
#>
function Set-AppSetting {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Key,
        
        [AllowNull()]
        $Value
    )

    try {
        # --- DÉTECTION ET NORMALISATION DU TYPE ---
        $type = 'string' # Par défaut, tout est une chaîne
        if ($null -ne $Value) {
            $valueType = $Value.GetType().Name.ToLower()
            if ($valueType -eq 'int32' -or $valueType -eq 'int64') {
                $type = 'integer'
            }
            elseif ($valueType -eq 'boolean') {
                $type = 'boolean'
            }
        }
        # ----------------------------------------

        # --- SÉCURISATION CONTRE L'INJECTION SQL (v3.1) ---
        # Utilisation de paramètres nommés au lieu de l'échappement manuel.
        $safeValue = if ($null -eq $Value) { "" } else { $Value.ToString() }
        
        $query = "INSERT OR REPLACE INTO settings (Key, Value, Type) VALUES (@Key, @Value, @Type);"
        $sqlParams = @{
            Key   = $Key
            Value = $safeValue
            Type  = $type
        }
        
        Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $query -SqlParameters $sqlParams -ErrorAction Stop

        $logMsg = "{0} '{1}' {2} '$safeValue' ({3}: $type)." -f (Get-AppText 'modules.database.setting_saved_1'), $Key, (Get-AppText 'modules.database.setting_saved_2'), (Get-AppText 'modules.database.setting_saved_3')
        Write-Verbose $logMsg
    }
    catch {
        $errorMsg = Get-AppText -Key 'modules.database.set_setting_error'
        throw "$errorMsg '$Key': $($_.Exception.Message)"
    }
}