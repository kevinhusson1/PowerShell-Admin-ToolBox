# Modules/Database/Functions/Sync-AppScriptSettings.ps1

<#
.SYNOPSIS
    Initialise les paramètres d'un script en base de données s'ils n'existent pas.
.DESCRIPTION
    Appelé au démarrage pour chaque script découvert sur le disque.
    1. Crée l'entrée dans script_settings (Activé par défaut, MaxRuns=1).
    2. Crée l'entrée dans script_security (Groupe Admin par défaut).
#>
function Sync-AppScriptSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$ScriptId,
        [Parameter(Mandatory)] [string]$AdminGroupName
    )

    # v3.1 Sanitization SQL

    # 1. Table script_settings (Paramètres)
    try {
        # INSERT OR IGNORE : Ne fait rien si l'ID existe déjà
        $querySettings = "INSERT OR IGNORE INTO script_settings (ScriptId, IsEnabled, MaxConcurrentRuns) VALUES (@ScriptId, 1, 1);"
        $settingsParams = @{ ScriptId = $ScriptId }
        
        Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $querySettings -SqlParameters $settingsParams -ErrorAction Stop
    }
    catch {
        Write-Warning "Erreur synchro settings pour $ScriptId : $($_.Exception.Message)"
    }

    # 2. Table script_security (Droits)
    try {
        # On vérifie s'il y a AU MOINS UN groupe défini pour ce script
        $checkQuery = "SELECT COUNT(1) as Cnt FROM script_security WHERE ScriptId = @ScriptId"
        # On réutilise settingsParams (ScriptId) car c'est le même
        $count = (Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $checkQuery -SqlParameters $settingsParams).Cnt

        # Si aucun groupe n'est défini (nouveau script), on ajoute le groupe Admin par sécurité
        if ($count -eq 0 -and -not [string]::IsNullOrWhiteSpace($AdminGroupName)) {
            $querySec = "INSERT INTO script_security (ScriptId, ADGroup) VALUES (@ScriptId, @ADGroup);"
            $secParams = @{
                ScriptId = $ScriptId
                ADGroup  = $AdminGroupName.Trim()
            }
            Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $querySec -SqlParameters $secParams -ErrorAction Stop
            Write-Verbose "Sécurité initialisée pour '$ScriptId' avec le groupe Admin."
        }
    }
    catch {
        Write-Warning "Erreur synchro sécurité pour $ScriptId : $($_.Exception.Message)"
    }
}