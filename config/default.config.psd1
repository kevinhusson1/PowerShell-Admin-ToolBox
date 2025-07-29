# Configuration PowerShell Admin ToolBox
@{
    Application = @{
        Name = "PowerShell Admin ToolBox"
        Version = "1.0.0"
        LogLevel = "Info"
        LogPath = ".\logs"
    }
    
    UI = @{
        Theme = "Modern"
        Language = "FR"
        WindowStartPosition = "CenterScreen"
    }
    
    Security = @{
        AuthenticationMode = "UserPassword"  # UserPassword | Certificate
        RequireAdminRights = $true
    }
}
