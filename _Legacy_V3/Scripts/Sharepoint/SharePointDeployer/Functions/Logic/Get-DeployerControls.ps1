<#
.SYNOPSIS
    Récupère les références des contrôles UI XAML de la fenêtre Deployer.

.DESCRIPTION
    Parcourt l'arbre visuel ou utilise FindName pour mapper les éléments XAML (Boutons, Panels, TextBlocks)
    dans une Hashtable centralisée ($Ctrl) utilisée par les fonctions logiques.
    Inclut une fonction helper interne pour la recherche récursive robuste.

.PARAMETER Window
    La fenêtre WPF principale du Deployer.

.OUTPUTS
    [hashtable] Contenant les références aux objets UI.
#>
function Get-DeployerControls {
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
        Title                = $Window.FindName("ConfigTitleText")
        Site                 = $Window.FindName("BadgeSiteText")
        Lib                  = $Window.FindName("BadgeLibText")
        Template             = $Window.FindName("BadgeTemplateText")
        Warning              = $Window.FindName("PermissionWarningBorder")
        DynamicFormPanel     = $Window.FindName("DynamicFormPanel")
        Placeholder          = $Window.FindName("PlaceholderText")
        PlaceholderPanel     = $Window.FindName("PlaceholderPanel")
        DetailGrid           = $Window.FindName("DetailGrid")
        BtnDeploy            = $Window.FindName("DeployButton")
        BtnOpen              = $Window.FindName("OpenTargetButton")
        LogBox               = $Window.FindName("LogRichTextBox")
        
        ProgressBar          = $Window.FindName("MainProgressBar")
        AuthOverlay          = $Window.FindName("AuthOverlay")
        OverlayBtn           = $Window.FindName("OverlayConnectButton")
        FolderNamePreview    = $Window.FindName("FolderNamePreviewText")
        
        # Header Auth Button (pour simulation click)
        ScriptAuthTextButton = $Window.FindName("ScriptAuthTextButton")
    }

    return $Ctrl
}
