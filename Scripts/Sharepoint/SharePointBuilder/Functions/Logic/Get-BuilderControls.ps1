# Scripts/SharePoint/SharePointBuilder/Functions/Logic/Get-BuilderControls.ps1

<#
.SYNOPSIS
    Récupère et indexe tous les contrôles WPF de l'interface SharePoint Builder.

.DESCRIPTION
    Parcourt l'arbre visuel de la fenêtre pour trouver et stocker les références aux contrôles clés
    (ComboBox, Boutons, Panels) dans une Hashtable pour un accès facile dans tout le script.
    Utilise une recherche récursive robuste pour gérer les NameScopes complexes.

.PARAMETER Window
    L'objet Window WPF parent à analyser.

.OUTPUTS
    [Hashtable] Une map conteneur/contrôle nommée $Ctrl.
#>
function Get-BuilderControls {
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

    # Fallback search if FindName fails for key panels
    $Find = { param($n) 
        $o = $Window.FindName($n)
        if (-not $o) { $o = Find-ControlByName -Parent $Window -Name $n }
        return $o
    }

    $Ctrl = @{
        # --- INPUTS ---
        CbSites                    = $Window.FindName("SiteComboBox")
        CbLibs                     = $Window.FindName("LibraryComboBox")
        CbTemplates                = $Window.FindName("TemplateComboBox")
        
        # --- CONFIG DOSSIER ---
        ChkCreateFolder            = $Window.FindName("CreateFolderCheckBox")
        CbFolderTemplates          = $Window.FindName("FolderTemplateComboBox")
        
        # --- FORMULAIRE ---
        TxtDesc                    = $Window.FindName("TemplateDescText")
        PanelForm                  = $Window.FindName("DynamicFormPanel")
        TxtPreview                 = $Window.FindName("FolderNamePreviewText")
        
        # --- OPTIONS AVANCÉES ---
        ChkOverwrite               = $Window.FindName("OverwritePermissionsCheckBox")
        BtnValidate                = $Window.FindName("ValidateModelButton")
        BtnReset                   = $Window.FindName("ResetUIButton")
        BtnSaveConfig              = $Window.FindName("SaveConfigButton")
        CbDeployConfigs            = $Window.FindName("DeployConfigComboBox")
        BtnLoadConfig              = $Window.FindName("LoadConfigButton")
        BtnDeleteConfig            = $Window.FindName("DeleteConfigButton")

        # --- ACTIONS ---
        BtnDeploy                  = $Window.FindName("DeployButton")
        
        # --- POST DÉPLOIEMENT ---
        PanelActions               = $Window.FindName("PostDeployActionsPanel")
        BtnCopyUrl                 = $Window.FindName("CopyUrlButton")
        BtnOpenUrl                 = $Window.FindName("OpenUrlButton")

        # --- OUTPUTS ---
        LogBox                     = $Window.FindName("LogRichTextBox")
        ProgressBar                = $Window.FindName("MainProgressBar")
        TxtStatus                  = $Window.FindName("ProgressStatusText")
        TreeView                   = $Window.FindName("PreviewTreeView")
        CbLogLevel                 = $Window.FindName("LogLevelComboBox")

        # --- EDITEUR (Toolbar) ---
        EdLoadCb                   = $Window.FindName("EditorLoadComboBox")
        EdBtnLoad                  = $Window.FindName("EditorLoadButton")
        EdBtnNew                   = $Window.FindName("EditorNewButton")
        EdBtnSave                  = $Window.FindName("EditorSaveButton")
        EdBtnDeleteTpl             = $Window.FindName("EditorDeleteTemplateButton")

        # --- EDITEUR (Tree) ---
        EdTree                     = $Window.FindName("EditorTreeView")
        EdBtnRoot                  = $Window.FindName("EditorAddRootButton")
        EdBtnRootLink              = $Window.FindName("EditorAddRootLinkButton")
        EdBtnChild                 = $Window.FindName("EditorAddChildButton")
        EdBtnChildLink             = $Window.FindName("EditorAddChildLinkButton")
        EdBtnChildInternalLink     = $Window.FindName("EditorAddChildInternalLinkButton")
        EdBtnAddPub                = $Window.FindName("EditorAddPubButton")
        EdBtnDel                   = $Window.FindName("EditorDeleteButton")
        
        # --- ICONS ---
        IconAddRoot                = $Window.FindName("IconAddRoot")
        IconAddRootLink            = $Window.FindName("IconAddRootLink")
        IconAddChild               = $Window.FindName("IconAddChild")
        IconAddChildLink           = $Window.FindName("IconAddChildLink")
        IconAddInternalLink        = $Window.FindName("IconAddInternalLink")
        IconAddPub                 = $Window.FindName("IconAddPub")
        IconDelete                 = $Window.FindName("IconDelete")
        
        # --- NEW TOOLBAR ICONS ---
        IconAddPerm                = $Window.FindName("IconAddPerm")
        IconAddTag                 = $Window.FindName("IconAddTag")

        # --- EDITEUR (Props) ---
        # --- EDITEUR (Props Panels) ---
        # USE ROBUST FIND
        EdPropPanel                = & $Find "EdPanelFolder"
        EdPropPanelPerm            = & $Find "EdPanelPerm"
        EdPropPanelTag             = & $Find "EdPanelTag"
        EdPropPanelLink            = & $Find "EdPanelLink"
        EdPropPanelInternalLink    = & $Find "EdPanelInternalLink"
        EdPropPanelPub             = & $Find "EdPanelPub"
        EdPanelGlobalTags          = & $Find "EdPanelGlobalTags"

        EdNoSelPanel               = & $Find "EdPanelNoSel"
        
        # Folder Inputs
        EdNameBox                  = $Window.FindName("EditorFolderNameTextBox")
        EdPermissionsListBox       = $Window.FindName("EditorPermissionsListBox")
        EdBtnAddPerm               = $Window.FindName("EditorAddPermButton")
        
        # Permission Inputs
        EdPermIdentityBox          = $Window.FindName("EdPermIdentityBox")
        EdPermLevelBox             = $Window.FindName("EdPermLevelBox")
        EdPermDeleteButton         = $Window.FindName("EdPermDeleteButton")

        # Tag Inputs
        EdTagNameBox               = $Window.FindName("EdTagNameBox")
        EdTagValueBox              = $Window.FindName("EdTagValueBox")
        EdTagDeleteButton          = $Window.FindName("EdTagDeleteButton")

        # Link Inputs
        EdLinkNameBox              = $Window.FindName("EdLinkNameBox")
        EdLinkUrlBox               = $Window.FindName("EdLinkUrlBox")
        EdLinkDeleteButton         = $Window.FindName("EdLinkDeleteButton")

        # Internal Link Inputs
        EdInternalLinkNameBox      = $Window.FindName("EdInternalLinkNameBox")
        EdInternalLinkIdBox        = $Window.FindName("EdInternalLinkIdBox")
        EdInternalLinkDeleteButton = $Window.FindName("EdInternalLinkDeleteButton")

        # Publication Inputs (NEW)
        EdPubNameBox               = $Window.FindName("EdPubNameBox")
        EdPubSiteModeBox           = $Window.FindName("EdPubSiteModeBox")
        EdPubSiteUrlBox            = $Window.FindName("EdPubSiteUrlBox")
        EdPubPathBox               = $Window.FindName("EdPubPathBox")
        EdPubUseModelNameChk       = $Window.FindName("EdPubUseModelNameChk")
        EdPubUseFormMetaChk        = $Window.FindName("EdPubUseFormMetaChk")
        EdPubGrantUserBox          = $Window.FindName("EdPubGrantUserBox")
        EdPubGrantLevelBox         = $Window.FindName("EdPubGrantLevelBox")
        EdPubDeleteButton          = $Window.FindName("EdPubDeleteButton")

        EdStatusText               = $Window.FindName("EditorStatusText")
        
        # --- EDITEUR --- Tags
        EdTagsListBox              = $Window.FindName("EditorTagsListBox")
        EdBtnAddTag                = $Window.FindName("EditorAddTagButton") # OLD (To be removed or kept for legacy?)
        
        # --- TOOLBAR GLOBAL ACTIONS ---
        EdBtnGlobalAddPerm         = $Window.FindName("EditorGlobalAddPermButton")
        EdBtnGlobalAddTag          = $Window.FindName("EditorGlobalAddTagButton")



        # --- FORMULAIRE EDITOR (Toolbar) ---
        FormLoadCb                 = $Window.FindName("FormLoadComboBox")
        FormBtnLoad                = $Window.FindName("FormLoadButton")
        FormBtnNew                 = $Window.FindName("FormNewButton")
        FormBtnSave                = $Window.FindName("FormSaveButton")
        FormBtnDelTpl              = $Window.FindName("FormDeleteButton")
        FormStatusText             = $Window.FindName("FormStatusText")

        # --- FORMULAIRE EDITOR (List & Actions) ---
        FormList                   = $Window.FindName("FormFieldsListBox")
        FormBtnAddLbl              = $Window.FindName("FormAddLabelBtn")
        FormBtnAddTxt              = $Window.FindName("FormAddTextBtn")
        FormBtnAddCmb              = $Window.FindName("FormAddComboBtn")
        FormBtnUp                  = $Window.FindName("FormMoveUpBtn")
        FormBtnDown                = $Window.FindName("FormMoveDownBtn")
        FormBtnDel                 = $Window.FindName("FormRemoveBtn")

        # --- FORMULAIRE EDITOR (Properties) ---
        FormPropPanel              = $Window.FindName("FormPropertiesPanel")
        FormNoSelPanel             = $Window.FindName("FormNoSelectionPanel")
        
        PropName                   = $Window.FindName("PropNameBox")
        PropContent                = $Window.FindName("PropContentBox")
        PropDefault                = $Window.FindName("PropDefaultBox")
        PropOptions                = $Window.FindName("PropOptionsBox")
        PropWidth                  = $Window.FindName("PropWidthBox")
        
        PanelName                  = $Window.FindName("PanelPropName")
        PanelContent               = $Window.FindName("PanelPropContent")
        PanelDefault               = $Window.FindName("PanelPropDefault")
        PanelOptions               = $Window.FindName("PanelPropOptions")
        PanelWidth                 = $Window.FindName("PanelPropWidth")
        
        PropForceUpper             = $Window.FindName("PropForceUpperCheck")
        PanelForceUpper            = $Window.FindName("PanelPropForceUpper")
        
        PropIsMetadataCheck        = $Window.FindName("PropIsMetadataCheck")
        PanelIsMetadata            = $Window.FindName("PanelPropIsMetadata")

        # --- FORMULAIRE EDITOR (Preview) ---
        FormLivePreview            = $Window.FindName("FormLivePreviewPanel")
        FormResultText             = $Window.FindName("FormResultPreviewText")
    }

    if (-not $Ctrl.CbSites -or -not $Ctrl.BtnDeploy) { return $null }

    return $Ctrl
}