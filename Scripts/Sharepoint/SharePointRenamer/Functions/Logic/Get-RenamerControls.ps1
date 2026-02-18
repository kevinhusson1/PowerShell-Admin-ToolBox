<#
.SYNOPSIS
    Récupère les contrôles UI du Renamer (V2 Dashboard)
#>
function Get-RenamerControls {
    param(
        [System.Windows.Window]$Window
    )

    $Ctrl = @{}
    $missing = @()

    # --- Controls Mapping (V2 Dashboard) ---
    $controlsToCheck = @(
        # 1. Header & Auth
        "ScriptAuthTextButton", "ScriptAuthStatusButton", "AuthOverlay", "OverlayConnectButton",
        
        # 2. Input Section
        "TargetUrlBox", "BtnAnalyze", "LoadingPanel", "ErrorPanel", "ErrorText",
        
        # 3. Dashboard
        "DashboardPanel", 
        "ProjectIcon", "ProjectTitle", "ProjectUrl",
        "BadgeStatus", "TextStatus", "TextConfig", "TextDate",
        "KpiStructure", "KpiMeta",
        
        # 4. Grids
        "MetaGrid", "StructureGrid",

        # 5. Actions
        "ActionsPanel", "RepairConfigPanel", "BtnCloseRepair", "RepairListPanel", "BtnConfirmRepair",
        "BtnRepair", "BtnRename", "BtnForget",

        # 6. Logs
        "LogRichTextBox"
    )

    foreach ($name in $controlsToCheck) {
        $c = $Window.FindName($name)
        
        # Fallback: LogicalTreeHelper (Robustesse pour XAML chargé dynamiquement)
        if (-not $c) {
            $c = [System.Windows.LogicalTreeHelper]::FindLogicalNode($Window, $name)
        }

        if ($c) { 
            $Ctrl[$name] = $c 
        }
        else {
            Write-Warning "[Renamer] Control '$name' introuvable dans XAML !"
        }
    }

    return $Ctrl
}
