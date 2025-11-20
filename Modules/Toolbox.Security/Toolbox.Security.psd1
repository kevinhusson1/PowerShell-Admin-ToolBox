# Modules/Toolbox.Security/Toolbox.Security.psd1

@{
    ModuleVersion = '1.0.0'
    GUID = '26c7da78-843c-4fbb-a3bb-528b64c3ba0c' 
    Author = 'HUSSON Kévin'
    Copyright = '(c) 2025. Tous droits réservés.'
    Description = 'Module pour les tâches liées à la sécurité et à la gestion des certificats.'
    RootModule = 'Toolbox.Security.psm1'
    FunctionsToExport = @(
        'Get-AppCertificateStatus',
        'Install-AppCertificate'
    )
}