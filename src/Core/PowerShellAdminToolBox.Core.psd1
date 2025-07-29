@{
    # Module manifest pour PowerShellAdminToolBox.Core
    RootModule = 'PowerShellAdminToolBox.Core.psm1'
    ModuleVersion = '1.0.0'
    GUID = '12345678-9abc-def0-1234-56789abcdef0'
    Author = 'PowerShell Admin ToolBox Team'
    CompanyName = 'Open Source Community'
    Copyright = '(c) 2025 PowerShell Admin ToolBox Contributors'
    Description = 'Module Core pour PowerShell Admin ToolBox - Services fondamentaux et architecture MVVM'
    
    # Version PowerShell minimum
    PowerShellVersion = '7.5'
    DotNetFrameworkVersion = '9.0'
    
    # Pas de dépendances externes pour le Core
    RequiredModules = @()
    
    # Fonctions exportées (sera mis à jour au fur et à mesure)
    FunctionsToExport = @(
        'Write-ToolBoxLog',
        'Initialize-ToolBoxLogging',
        'Get-ToolBoxLogPath'
    )
    
    # Classes exportées
    ClassesToExport = @(
        'LoggingService',
        'ViewModelBase',
        'RelayCommand'
    )
    
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    
    # Métadonnées du module Core
    PrivateData = @{
        PSData = @{
            Tags = @('PowerShell', 'Admin', 'ToolBox', 'Core', 'MVVM', 'Logging')
            LicenseUri = 'https://github.com/username/PowerShellAdminToolBox/blob/main/LICENSE'
            ProjectUri = 'https://github.com/username/PowerShellAdminToolBox'
            ReleaseNotes = 'Version initiale du module Core avec système de logging'
        }
        
        # Métadonnées spécifiques ToolBox
        ToolBoxCore = @{
            Version = '1.0.0'
            LastUpdated = '2025-01-01'
            Components = @('LoggingService', 'MVVM-Base')
            IsCore = $true
        }
    }
}