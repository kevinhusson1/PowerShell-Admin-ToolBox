@{
    # Module metadata
    ModuleVersion = '1.0.0'
    GUID = 'TEST1234-5678-9ABC-DEF0-123456789ABC'
    Author = 'PowerShell Admin ToolBox Team'
    CompanyName = 'ToolBox'
    Copyright = '(c) 2025 ToolBox Team. All rights reserved.'
    Description = 'Module de test pour validation du système de styles globaux'
    
    # Minimum version required
    PowerShellVersion = '7.5'
    
    # Functions to export
    FunctionsToExport = @('Show-TestStyles')
    
    # ToolBox specific configuration
    PrivateData = @{
        ToolBox = @{
            Enabled = $true
            RequiredRoles = @('User', 'Admin')
            DisplayName = 'Test Styles'
            Description = 'Module de validation du chargement des styles globaux'
            Category = 'Test'
            SortOrder = 1000  # En dernier dans la liste pour tests
        }
    }
}