<#
.SYNOPSIS
    Récupère les références des contrôles UI XAML de la fenêtre Renamer.
#>
function Get-RenamerControls {
    param([System.Windows.Window]$Window)

    # Helper for deep search (Robustness against NameScope)
    function Find-ControlByName {
        param($Parent, $Name)
        if (-not $Parent) { return $null }
        if ($Parent.Name -eq $Name) { return $Parent }
        
        $count = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($Parent)
        for ($i = 0; $i -lt $count; $i++) {
            $child = [System.Windows.Media.VisualTreeHelper]::GetChild($Parent, $i)
            # Check visual child
            if ($child -is [System.Windows.FrameworkElement] -and $child.Name -eq $Name) { return $child }
            
            # Recursive
            $res = Find-ControlByName -Parent $child -Name $Name
            if ($res) { return $res }
        }
        return $null
    }

    $Ctrl = @{
        ListBox              = $Window.FindName("ConfigListBox")
        TargetPanel          = $Window.FindName("TargetPanel")
        TargetFolderBox      = $Window.FindName("TargetFolderBox")
        CurrentMetaText      = $Window.FindName("CurrentMetaText")
        BtnPickFolder        = $Window.FindName("BtnPickFolder")
        
        FormPanel            = $Window.FindName("FormPanel")
        DynamicFormPanel     = $Window.FindName("DynamicFormPanel")
        FolderNamePreview    = $Window.FindName("FolderNamePreviewText")
        BtnRename            = $Window.FindName("BtnRename")
        
        LogBox               = $Window.FindName("LogRichTextBox")
        AuthOverlay          = $Window.FindName("AuthOverlay")
        OverlayBtn           = $Window.FindName("OverlayConnectButton")
        
        # Header Auth Button (pour simulation click)
        ScriptAuthTextButton = $Window.FindName("ScriptAuthTextButton")
    }

    return $Ctrl
}
