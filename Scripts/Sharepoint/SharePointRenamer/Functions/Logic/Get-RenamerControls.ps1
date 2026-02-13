<#
.SYNOPSIS
    Récupère les références des contrôles UI XAML de la fenêtre Renamer.
#>
<#
.SYNOPSIS
    Mappe les contrôles XAML vers une Hashtable PowerShell.
    
.DESCRIPTION
    Parcourt l'arbre visuel ou utilise FindName pour récupérer les références
    aux boutons, listbox, textblocks, etc.
    Retourne une Hashtable $Ctrl utilisable par les autres scripts logiques.
#>
function Get-RenamerControls {
    param([System.Windows.Window]$Window)

    # Helper: Iterative Deep Search (Stack-Based DFS)
    function Find-ControlByName {
        param($Parent, $Name)
        if (-not $Parent) { return $null }

        $nodes = [System.Collections.Generic.Stack[System.Windows.DependencyObject]]::new()
        $nodes.Push($Parent)

        while ($nodes.Count -gt 0) {
            $current = $nodes.Pop()
            
            # Check Name match
            if ($current -is [System.Windows.FrameworkElement] -and $current.Name -eq $Name) {
                return $current
            }

            # Get Children (Logical Tree)
            try {
                $children = [System.Windows.LogicalTreeHelper]::GetChildren($current)
                if ($children) {
                    foreach ($child in $children) {
                        if ($child -is [System.Windows.DependencyObject]) {
                            $nodes.Push($child)
                        }
                    }
                }
            }
            catch {}
        }
        return $null
    }

    $Ctrl = @{
        ListBox              = Find-ControlByName -Parent $Window -Name "ConfigListBox"
        
        # Main Panels
        PlaceholderPanel     = Find-ControlByName -Parent $Window -Name "PlaceholderPanel"
        DetailGrid           = Find-ControlByName -Parent $Window -Name "DetailGrid"
        ConfigTitleText      = Find-ControlByName -Parent $Window -Name "ConfigTitleText"
        
        # Detail Content
        TargetPanel          = Find-ControlByName -Parent $Window -Name "TargetPanel"
        TargetFolderBox      = Find-ControlByName -Parent $Window -Name "TargetFolderBox"
        CurrentMetaText      = Find-ControlByName -Parent $Window -Name "CurrentMetaText"
        BtnPickFolder        = Find-ControlByName -Parent $Window -Name "BtnPickFolder"
        
        FormPanel            = Find-ControlByName -Parent $Window -Name "FormPanel"
        DynamicFormPanel     = Find-ControlByName -Parent $Window -Name "DynamicFormPanel"
        FolderNamePreview    = Find-ControlByName -Parent $Window -Name "FolderNamePreviewText"
        BtnRename            = Find-ControlByName -Parent $Window -Name "BtnRename"
        
        LogBox               = Find-ControlByName -Parent $Window -Name "LogRichTextBox"
        AuthOverlay          = Find-ControlByName -Parent $Window -Name "AuthOverlay"
        OverlayBtn           = Find-ControlByName -Parent $Window -Name "OverlayConnectButton"
        
        # Header Auth Button
        ScriptAuthTextButton = Find-ControlByName -Parent $Window -Name "ScriptAuthTextButton"
    }

    # Critial Check
    $missing = @()
    foreach ($k in $Ctrl.Keys) {
        if (-not $Ctrl[$k]) { $missing += $k }
    }

    if ($missing.Count -gt 0) {
        $msg = "ERREUR CRITIQUE UI: Des contrôles sont introuvables lors de l'initialisation :`n" + ($missing -join ", ")
        $msg += "`n`nL'application risque ne pas fonctionner."
        [System.Windows.MessageBox]::Show($msg, "Erreur UI", "OK", "IconExclamation")
    }

    return $Ctrl
}
