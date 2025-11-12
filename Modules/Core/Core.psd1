# Modules/Core/Core.psd1

@{
    # Version du module
    ModuleVersion = '1.0.0'

    # Un ID unique pour le module
    GUID = '0663e359-9fec-42cd-ae3a-2ed30dd51b89'

    # Informations sur l'auteur
    Author = 'HUSSON Kévin'
    Copyright = "(c) 2025. Tous droits réservés."

    # Description du module
    Description = 'Module principal contenant les fonctions de base (configuration, lancement de scripts, etc.).'

    # Modules requis par ce module
    RequiredModules = @(
        'Database'
    )

    # Fichier de script principal du module
    RootModule = 'Core.psm1'

    # Liste explicite des fonctions à exporter (bonne pratique)
    FunctionsToExport = @(
        'Get-AppAvailableScript',
        'Get-AppConfiguration'
    )
}