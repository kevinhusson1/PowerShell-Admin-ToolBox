# Modules/Logging/Logging.psd1

@{
    # Version du module
    ModuleVersion = '1.0.0'

    # Un ID unique pour le module
    GUID = '4f01cfdb-794f-4c89-af26-7f12ce9a395c'

    # Informations sur l'auteur
    Author = 'HUSSON Kévin'
    Copyright = "(c) 2025. Tous droits réservés."

    # Description du module
    Description = 'Module pour le gestion des log en fichier ou dans une UI'

    # Fichier de script principal du module
    RootModule = 'Logging.psm1'

    # Liste explicite des fonctions à exporter (bonne pratique)
    FunctionsToExport = @(
        'Write-AppLog'
    )
}