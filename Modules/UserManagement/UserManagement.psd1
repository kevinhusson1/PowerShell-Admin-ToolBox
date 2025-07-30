@{
    # Module metadata
    ModuleVersion = '0.1.0'
    GUID = '87654321-4321-4321-4321-210987654321'
    Author = 'PowerShell Admin ToolBox Team'
    CompanyName = 'ToolBox'
    Copyright = '(c) 2025 ToolBox Team. All rights reserved.'
    Description = 'Module de gestion des utilisateurs AD et Azure AD'
    
    # Minimum version required
    PowerShellVersion = '7.5'
    
    # Functions to export
    FunctionsToExport = @('Show-UserManagement')
    
    # ToolBox specific configuration
    PrivateData = @{
        ToolBox = @{
            Enabled = $false  # Désactivé pour test
            RequiredRoles = @('Admin')
            DisplayName = 'Gestion Utilisateurs'
            Description = 'Création, modification et gestion des comptes utilisateurs'
            Category = 'Administration'
            SortOrder = 5
        }
    }
}