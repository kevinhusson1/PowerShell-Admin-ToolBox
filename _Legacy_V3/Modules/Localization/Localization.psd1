# Modules/Localization/Localization.psd1

@{
    # Version du module
    ModuleVersion = '1.0.0'

    # Un ID unique pour le module
    GUID = '84e88eee-312a-45fd-ae56-5eb5f9ce1c57'

    # Informations sur l'auteur
    Author = 'HUSSON Kévin'
    Copyright = "(c) 2025. Tous droits réservés."

    # Description du module
    Description = 'Module permettant de changer de langue.'

    # Fichier de script principal du module
    RootModule = 'Localization.psm1'

    # Liste explicite des fonctions à exporter (bonne pratique)
    FunctionsToExport = @(
        'Get-AppLocalizedString',
        'Initialize-AppLocalization',
        'Add-AppLocalizationSource'
        # 'Merge-PSCustomObject'
    )

    AliasesToExport = @(
        'Get-AppText'
    )
}