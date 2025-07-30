@{
    # Module metadata
    ModuleVersion = '1.0.0'
    GUID = '12345678-1234-1234-1234-123456789012'
    Author = 'PowerShell Admin ToolBox Team'
    CompanyName = 'ToolBox'
    Copyright = '(c) 2025 ToolBox Team. All rights reserved.'
    Description = 'Module de test pour affichage des informations système'
    
    # Minimum version required
    PowerShellVersion = '7.5'
    
    # Functions to export
    FunctionsToExport = @('Show-SystemInfo')
    
    # ToolBox specific configuration
    PrivateData = @{
        ToolBox = @{
            Enabled = $true
            RequiredRoles = @('User', 'Admin')
            DisplayName = 'Informations Système'
            Description = 'Affiche les informations détaillées du système'
            Category = 'Système'
            SortOrder = 10
        }
    }
}