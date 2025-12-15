# Modules/Core/Core.psd1

@{
    # Version du module
    ModuleVersion     = '1.0.0'

    # Un ID unique pour le module
    GUID              = 'e1ebc98e-ad54-4827-873b-b70fa326dcca'

    # Informations sur l'auteur
    Author            = 'HUSSON Kévin'
    Copyright         = "(c) 2025. Tous droits réservés."

    # Description du module
    Description       = 'Module principal contenant les fonctions relative à la base de données SQLLite'

    # Fichier de script principal du module
    RootModule        = 'Database.psm1'

    # Liste explicite des fonctions à exporter (bonne pratique)
    FunctionsToExport = @(
        'Add-AppKnownGroup',
        'Add-AppScriptLock',
        'Add-AppScriptSecurityGroup',
        'Clear-AppScriptLock',
        'Get-AppKnownGroups',
        'Get-AppPermissionRequests',
        'Get-AppScriptProgress',
        'Get-AppScriptSecurity',
        'Get-AppScriptSettingsMap',
        'Get-AppSetting',
        'Get-AppSPTemplates',
        'Initialize-AppDatabase',
        'Remove-AppKnownGroup',
        'Remove-AppScriptProgress',
        'Remove-AppScriptSecurityGroup',
        'Remove-AppSPTemplate',
        'Set-AppScriptProgress',
        'Set-AppScriptSettings',
        'Set-AppSetting',
        'Set-AppSPTemplate',
        'Sync-AppScriptSecurity',
        'Sync-AppScriptSettings',
        'Test-AppScriptLock',
        'Unlock-AppScriptLock'
    )
}