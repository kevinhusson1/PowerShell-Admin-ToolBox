# Scripts/SharePoint/SharePointBuilder/Functions/Logic/Get-BuilderControls.ps1

function Get-BuilderControls {
    param([System.Windows.Window]$Window)

    $Ctrl = @{
        # --- INPUTS ---
        CbSites              = $Window.FindName("SiteComboBox")
        CbLibs               = $Window.FindName("LibraryComboBox")
        CbTemplates          = $Window.FindName("TemplateComboBox")
        
        # --- CONFIG DOSSIER ---
        ChkCreateFolder      = $Window.FindName("CreateFolderCheckBox") # <--- CRITIQUE
        CbFolderTemplates    = $Window.FindName("FolderTemplateComboBox")
        
        # --- FORMULAIRE ---
        TxtDesc              = $Window.FindName("TemplateDescText")
        PanelForm            = $Window.FindName("DynamicFormPanel")
        TxtPreview           = $Window.FindName("FolderNamePreviewText")
        
        # --- OPTIONS AVANCÉES ---
        ChkOverwrite         = $Window.FindName("OverwritePermissionsCheckBox")
        BtnReset             = $Window.FindName("ResetUIButton")
        BtnExport            = $Window.FindName("ExportConfigButton")

        # --- ACTIONS ---
        BtnDeploy            = $Window.FindName("DeployButton")
        
        # --- POST DÉPLOIEMENT ---
        PanelActions         = $Window.FindName("PostDeployActionsPanel")
        BtnCopyUrl           = $Window.FindName("CopyUrlButton")
        BtnOpenUrl           = $Window.FindName("OpenUrlButton")

        # --- OUTPUTS ---
        LogBox               = $Window.FindName("LogRichTextBox")
        ProgressBar          = $Window.FindName("MainProgressBar")
        TxtStatus            = $Window.FindName("ProgressStatusText")
        TreeView             = $Window.FindName("PreviewTreeView")
        CbLogLevel           = $Window.FindName("LogLevelComboBox")

        # --- EDITEUR (Toolbar) ---
        EdLoadCb             = $Window.FindName("EditorLoadComboBox")
        EdBtnLoad            = $Window.FindName("EditorLoadButton")
        EdBtnNew             = $Window.FindName("EditorNewButton")
        EdBtnSave            = $Window.FindName("EditorSaveButton")
        EdBtnDeleteTpl       = $Window.FindName("EditorDeleteTemplateButton")

        # --- EDITEUR (Tree) ---
        EdTree               = $Window.FindName("EditorTreeView")
        EdBtnRoot            = $Window.FindName("EditorAddRootButton")
        EdBtnChild           = $Window.FindName("EditorAddChildButton")
        EdBtnDel             = $Window.FindName("EditorDeleteNodeButton")

        # --- EDITEUR (Props) ---
        EdPropPanel          = $Window.FindName("EditorPropertiesPanel")
        EdNoSelPanel         = $Window.FindName("EditorNoSelectionPanel")
        EdNameBox            = $Window.FindName("EditorFolderNameTextBox")

        # --- EDITEUR --- Permissions
        EdPermissionsListBox = $Window.FindName("EditorPermissionsListBox")
        EdBtnAddPerm         = $Window.FindName("EditorAddPermButton")
        
        # --- EDITEUR --- Tags
        EdTagsListBox        = $Window.FindName("EditorTagsListBox")
        EdBtnAddTag          = $Window.FindName("EditorAddTagButton")

        # Liens (NOUVEAU)
        EdLinksListBox       = $Window.FindName("EditorLinksListBox")
        EdBtnAddLink         = $Window.FindName("EditorAddLinkButton")
    }

    if (-not $Ctrl.CbSites -or -not $Ctrl.BtnDeploy) { return $null }

    return $Ctrl
}