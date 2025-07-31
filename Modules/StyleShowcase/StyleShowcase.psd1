@{
    # Module metadata
    ModuleVersion = '1.0.0'
    GUID = 'A1B2C3D4-5E6F-7890-ABCD-EF1234567890'
    Author = 'PowerShell Admin ToolBox Team'
    CompanyName = 'ToolBox'
    Copyright = '(c) 2025 ToolBox Team. All rights reserved.'
    Description = 'Module vitrine pour démonstration des styles et contrôles ToolBox'
    
    # Minimum version required
    PowerShellVersion = '7.5'
    
    # Functions to export
    FunctionsToExport = @('Show-StyleShowcase')
    
    # ToolBox specific configuration
    PrivateData = @{
        ToolBox = @{
            Enabled = $true  # Activé par défaut pour les tests
            RequiredRoles = @('User', 'Admin')
            DisplayName = 'Vitrine de Styles'
            Description = 'Référence visuelle de tous les styles et contrôles disponibles'
            Category = 'Développement'
            SortOrder = 999  # En dernier dans la liste
        }
    }
}