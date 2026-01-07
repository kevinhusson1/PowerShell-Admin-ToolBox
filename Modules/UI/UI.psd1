# Modules/UI/UI.psd1

@{
    # Version du module
    ModuleVersion     = '1.0.0'

    # Un ID unique pour le module
    GUID              = '529c33ce-283c-4166-8dac-149d64035ca1' # Générez un nouveau GUID avec New-Guid

    # Informations sur l'auteur
    Author            = 'HUSSON Kévin'

    # Copyright
    Copyright         = "(c) 2025. Tous droits réservés."

    # Description du module
    Description       = 'Module pour la gestion des composants UI de la plateforme.'

    # Fichier de script principal du module
    RootModule        = 'UI.psm1'

    # Liste explicite des fonctions à exporter (bonne pratique)
    FunctionsToExport = @(
        'Import-AppXamlTemplate',
        'Initialize-AppUIComponents',
        'Update-AppRichTextBox',
        'Set-AppWindowIdentity'
    )
}