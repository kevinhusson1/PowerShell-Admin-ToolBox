# Modules/Azure/Azure.psd1

@{
    # Version du module
    ModuleVersion     = '1.0.2'

    # Un ID unique pour le module
    GUID              = 'f6bebb1d-ac55-4609-b571-03057f2d7e1f'

    # Informations sur l'auteur
    Author            = 'HUSSON Kévin'
    Copyright         = "(c) 2025. Tous droits réservés."

    # Description du module
    Description       = 'Module pour le gestion des interactions avec Azure (authentification, gestion des ressources, etc.).'

    # Fichier de script principal du module
    RootModule        = 'Azure.psm1'

    # Pré-chargement explicite de Graph.Authentication pour éviter le conflit de DLL (ex: avec PnP.PowerShell)
    RequiredModules   = @('Microsoft.Graph.Authentication')

    # Liste explicite des fonctions à exporter (bonne pratique)
    FunctionsToExport = @(
        'Add-AppGraphPermission',
        'Connect-AppAzureWithUser',
        'Connect-AppAzureCert',
        'Disconnect-AppAzureUser',
        'Get-AppAzureGroupMembers',
        'Get-AppServicePrincipalPermissions',
        'Get-AppUserAzureGroups',
        'Test-AppAzureCertConnection',
        'Test-AppAzureUserConnection',
        'Connect-AppChildSession',
        'Get-AppCertificateStatus',
        'Get-AppAzureDirectoryUsers'
    )
}