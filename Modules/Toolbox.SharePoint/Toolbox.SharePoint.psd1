# Modules/Toolbox.SharePoint/Toolbox.SharePoint.psd1

@{
    # Version du module
    ModuleVersion     = '1.0.0'

    # ID unique
    GUID              = 'a1b2c3d4-e5f6-7890-1234-567890abcdef'

    # Auteur
    Author            = 'Service IT'
    Copyright         = "(c) 2025. Tous droits réservés."

    # Description
    Description       = 'Module central pour toutes les interactions avec SharePoint Online (via PnP).'

    # Script principal
    RootModule        = 'Toolbox.SharePoint.psm1'

    # Fonctions à exporter
    FunctionsToExport = @(
        'Add-AppSPFile',
        'Connect-AppSharePoint',
        'Get-AppProjectStatus',
        'Get-AppSPFile',
        'Get-AppSPLibraries',
        'Get-AppSPSites',
        'Import-AppSPFile',
        'New-AppSPFolder',
        'New-AppSPLink',
        'New-AppSPStructure',
        'New-AppSPTrackingList',
        'Rename-AppSPFolder',
        'Rename-AppSPPublications',
        'Repair-AppProject',
        'Repair-AppSPLinks',
        'Set-AppSPMetadata',
        'Set-AppSPPermission',
        'Test-AppSPDrift',
        'Test-AppSPModel'
    )
}