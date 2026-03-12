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
    Description       = 'Module central pour toutes les interactions avec SharePoint Online (via Graph API).'

    # Script principal
    RootModule        = 'Toolbox.SharePoint.psm1'

    # Fonctions à exporter
    FunctionsToExport = @(
        'Add-AppSPFile',
        'Get-AppProjectStatus',
        'Get-AppSPFile',
        'Get-AppSPLibraries',
        'Get-AppSPSites',
        'New-AppSPFolder',
        'New-AppSPStructure',
        'Repair-AppProject',
        'Test-AppSPDrift',
        'Test-AppSPModel',
        'New-AppGraphSPStructure',
        'Find-AppGraphFolderByTag',
        'Get-AppGraphListDriveId',
        'Get-AppGraphSiteId',
        'Get-AppSPDeploymentPlan',
        'New-AppGraphContentType',
        'New-AppGraphFolder',
        'New-AppGraphSiteColumn',
        'Set-AppGraphListItemMetadata',
        'Save-AppSPDeploymentState'
    )
}