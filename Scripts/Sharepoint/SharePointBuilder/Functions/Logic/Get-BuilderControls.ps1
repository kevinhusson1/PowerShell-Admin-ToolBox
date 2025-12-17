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
        EdStatusText         = $Window.FindName("EditorStatusText") # <--- AJOUT
        
        # --- EDITEUR --- Tags
        EdTagsListBox        = $Window.FindName("EditorTagsListBox")
        EdBtnAddTag          = $Window.FindName("EditorAddTagButton")

        # Liens (NOUVEAU)
        EdLinksListBox       = $Window.FindName("EditorLinksListBox")
        EdBtnAddLink         = $Window.FindName("EditorAddLinkButton")

        # --- FORMULAIRE EDITOR (Toolbar) ---
        FormLoadCb           = $Window.FindName("FormLoadComboBox")
        FormBtnLoad          = $Window.FindName("FormLoadButton")
        FormBtnNew           = $Window.FindName("FormNewButton")
        FormBtnSave          = $Window.FindName("FormSaveButton")
        FormBtnDelTpl        = $Window.FindName("FormDeleteButton")
        FormStatusText       = $Window.FindName("FormStatusText") # <--- AJOUT

        # --- FORMULAIRE EDITOR (List & Actions) ---
        FormList             = $Window.FindName("FormFieldsListBox")
        FormBtnAddLbl        = $Window.FindName("FormAddLabelBtn")
        FormBtnAddTxt        = $Window.FindName("FormAddTextBtn")
        FormBtnAddCmb        = $Window.FindName("FormAddComboBtn")
        FormBtnUp            = $Window.FindName("FormMoveUpBtn")
        FormBtnDown          = $Window.FindName("FormMoveDownBtn")
        FormBtnDel           = $Window.FindName("FormRemoveBtn")

        # --- FORMULAIRE EDITOR (Properties) ---
        FormPropPanel        = $Window.FindName("FormPropertiesPanel")
        FormNoSelPanel       = $Window.FindName("FormNoSelectionPanel")
        
        PropName             = $Window.FindName("PropNameBox")
        PropContent          = $Window.FindName("PropContentBox")
        PropDefault          = $Window.FindName("PropDefaultBox")
        PropOptions          = $Window.FindName("PropOptionsBox")
        PropWidth            = $Window.FindName("PropWidthBox")
        
        PanelName            = $Window.FindName("PanelPropName")     # <--- AJOUT
        PanelContent         = $Window.FindName("PanelPropContent")
        PanelDefault         = $Window.FindName("PanelPropDefault")
        PanelOptions         = $Window.FindName("PanelPropOptions")
        PanelWidth           = $Window.FindName("PanelPropWidth")

        # --- FORMULAIRE EDITOR (Preview) ---
        FormLivePreview      = $Window.FindName("FormLivePreviewPanel")
        FormResultText       = $Window.FindName("FormResultPreviewText") # <--- AJOUT
    }

    if (-not $Ctrl.CbSites -or -not $Ctrl.BtnDeploy) { return $null }

    return $Ctrl
}