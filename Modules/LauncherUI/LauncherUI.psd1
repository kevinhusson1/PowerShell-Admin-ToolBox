# Modules/LauncherUI/LauncherUI.psd1

@{
    # Version du module
    ModuleVersion = '1.0.0'

    # Un ID unique pour le module
    GUID = 'c8c1404c-2427-4c7a-956f-9f12d2e4819d'

    # Informations sur l'auteur
    Author = 'HUSSON Kévin'
    Copyright = "(c) 2025. Tous droits réservés."

    # Description du module
    Description = 'Module principal pour le lancement du launcher'

    # Fichier de script principal du module
    RootModule = 'LauncherUI.psm1'

    # Liste explicite des fonctions à exporter (bonne pratique)
    FunctionsToExport = @(
        'Get-FilteredAndEnrichedScripts',
        'Initialize-LauncherData',
        'Register-LauncherEvents',
        'Start-AppScript',
        'Stop-AppScript',
        'Test-IsAppAdmin',
        'Update-LauncherAuthButton',
        'Update-ScriptListBoxUI'
    )
}