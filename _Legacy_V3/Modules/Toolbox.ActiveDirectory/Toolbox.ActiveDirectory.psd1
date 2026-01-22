# Modules/Toolbox.ActiveDirectory/Toolbox.ActiveDirectory.psd1

@{
    ModuleVersion = '1.0.0'
    GUID = 'b69b31e4-c519-4e75-9bf6-e3d3ef35c59f' # Remplacez par un nouveau GUID : New-Guid
    Author = 'HUSSON Kévin'
    Copyright = '(c) 2025. Tous droits réservés.'
    Description = 'Module central pour toutes les interactions avec Active Directory.'
    RootModule = 'Toolbox.ActiveDirectory.psm1'
    
    # Pour l'instant, nous n'avons pas besoin des RSAT, donc pas de RequiredModules.
    
    FunctionsToExport = @(
        'Get-ADServiceCredential',
        'Test-ADConnection',
        'Test-ADInfrastructure',
        'Test-ADDirectoryObjects'
    )
}