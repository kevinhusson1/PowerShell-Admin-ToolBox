# Scripts/SharePoint/SharePointBuilder/Functions/Logic/Get-BuilderControls.ps1

function Get-BuilderControls {
    param([System.Windows.Window]$Window)

    $Ctrl = @{
        CbSites     = $Window.FindName("SiteComboBox")
        CbLibs      = $Window.FindName("LibraryComboBox")
        CbTemplates = $Window.FindName("TemplateComboBox")
        TxtDesc     = $Window.FindName("TemplateDescText")
        PanelForm   = $Window.FindName("DynamicFormPanel")
        TxtPreview  = $Window.FindName("FolderNamePreviewText")
        BtnDeploy   = $Window.FindName("DeployButton")
        LogBox      = $Window.FindName("LogRichTextBox")
        ProgressBar = $Window.FindName("MainProgressBar")
        TxtStatus   = $Window.FindName("ProgressStatusText")
    }

    # Validation basique
    if (-not $Ctrl.CbSites -or -not $Ctrl.BtnDeploy) { 
        Write-Warning "Certains contrôles XAML sont introuvables."
        return $null
    }

    return $Ctrl
}# Scripts/SharePoint/SharePointBuilder/Functions/Logic/Get-BuilderControls.ps1

function Get-BuilderControls {
    param([System.Windows.Window]$Window)

    $Ctrl = @{
        # --- INPUTS ---
        CbSites     = $Window.FindName("SiteComboBox")
        CbLibs      = $Window.FindName("LibraryComboBox")
        CbTemplates = $Window.FindName("TemplateComboBox")
        
        # --- FORMULAIRE ---
        TxtDesc     = $Window.FindName("TemplateDescText")
        PanelForm   = $Window.FindName("DynamicFormPanel")
        TxtPreview  = $Window.FindName("FolderNamePreviewText")
        
        # --- OPTIONS AVANCÉES ---
        ChkOverwrite = $Window.FindName("OverwritePermissionsCheckBox")
        BtnReset     = $Window.FindName("ResetUIButton")
        BtnExport    = $Window.FindName("ExportConfigButton")

        # --- ACTIONS ---
        BtnDeploy   = $Window.FindName("DeployButton")
        
        # --- POST DÉPLOIEMENT ---
        PanelActions = $Window.FindName("PostDeployActionsPanel")
        BtnCopyUrl   = $Window.FindName("CopyUrlButton")
        BtnOpenUrl   = $Window.FindName("OpenUrlButton")

        # --- OUTPUTS ---
        LogBox      = $Window.FindName("LogRichTextBox")
        ProgressBar = $Window.FindName("MainProgressBar")
        TxtStatus   = $Window.FindName("ProgressStatusText")
        TreeView    = $Window.FindName("PreviewTreeView")
        CbLogLevel  = $Window.FindName("LogLevelComboBox")
    }

    # Validation minimale pour éviter les crashs majeurs
    if (-not $Ctrl.CbSites -or -not $Ctrl.BtnDeploy) { 
        Write-Warning "Get-BuilderControls : Certains contrôles XAML critiques sont introuvables."
        return $null
    }

    return $Ctrl
}