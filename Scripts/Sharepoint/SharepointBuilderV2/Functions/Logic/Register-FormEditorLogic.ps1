# Scripts/SharePoint/SharePointBuilder/Functions/Logic/Register-FormEditorLogic.ps1

<#
.SYNOPSIS
    Gère toute la logique de l'éditeur de formulaires (onglet "Éditeur de Formulaire").

.DESCRIPTION
    Permet à l'utilisateur de construire dynamiquement un formulaire de saisie pour les règles de nommage de dossiers.
    - Ajout de champs (Labels, TextBox, ComboBox).
    - Modification des propriétés des champs (Nom, Valeur par défaut, Largeur, Options).
    - Prévisualisation en temps réel du résultat.
    - Sauvegarde et chargement des définitions JSON.

.PARAMETER Ctrl
    La Hashtable des contrôles UI.

.PARAMETER Window
    La fenêtre WPF principale.
#>
function Register-FormEditorLogic {
    param(
        [hashtable]$Ctrl,
        [System.Windows.Window]$Window
    )

    # ==========================================================================
    # 0. HELPER : STATUS
    # ==========================================================================
    $SetFormStatus = {
        param([string]$Msg, [string]$Type = "Normal")
        if ($Ctrl.FormStatusText) {
            $Ctrl.FormStatusText.Text = $Msg
            $brushKey = switch ($Type) {
                "Success" { "SuccessBrush" }
                "Error" { "DangerBrush" }
                "Warning" { "WarningBrush" }
                Default { "TextSecondaryBrush" }
            }
            try { $Ctrl.FormStatusText.Foreground = $Window.FindResource($brushKey) } catch { }
        }
    }.GetNewClosure()

    # ==========================================================================
    # 1. RENDU DE LA PREVIEW (DÉPORTÉ v4.18)
    # ==========================================================================
    # Les fonctions globales Invoke-AppSPFormUpdatePreview et Invoke-AppSPFormRecalculate
    # sont chargées depuis Invoke-AppSPFormEditor.ps1

    # ==========================================================================
    # 2. HELPER : METADATA & RENDU LISTE
    # ==========================================================================
    
    # Helper pour peupler la combobox des cibles
    $PopulateMetaTargets = {
        $schemaId = $Ctrl.FormTargetSchemaDisplay.Tag
        if (-not $schemaId) { return }
        
        $schemaObj = @(Get-AppSPFolderSchema) | Where-Object { $_.SchemaId -eq $schemaId } | Select-Object -First 1
        if (-not $schemaObj) { return }
        
        $columns = $schemaObj.ColumnsJson | ConvertFrom-Json
        if ($columns) {
            $Ctrl.PropMetaTargetBox.ItemsSource = $columns
            $Ctrl.PropMetaTargetBox.DisplayMemberPath = "Name"
            $Ctrl.PropMetaTargetBox.SelectedValuePath = "Name"
        }
    }.GetNewClosure()

    $RenderListItem = {
        param($Data) 

        $item = New-Object System.Windows.Controls.ListBoxItem
        $item.Tag = $Data
        
        $stack = New-Object System.Windows.Controls.StackPanel -Property @{ Orientation = "Horizontal" }
        $border = New-Object System.Windows.Controls.Border -Property @{ CornerRadius = 4; Padding = "6,2"; Margin = "0,0,10,0" }
        $txtType = New-Object System.Windows.Controls.TextBlock -Property @{ FontSize = 10; FontWeight = "Bold" }
        
        switch ($Data.Type) {
            "Label" { $border.Background = "#E5E7EB"; $txtType.Text = "TXT"; $txtType.Foreground = "#374151" }
            "TextBox" { $border.Background = "#DBEAFE"; $txtType.Text = "INP"; $txtType.Foreground = "#1E40AF" }
            "ComboBox" { $border.Background = "#D1FAE5"; $txtType.Text = "LST"; $txtType.Foreground = "#065F46" }
        }
        $border.Child = $txtType

        $desc = ""
        if ($Data.Type -eq "Label") { $desc = "'$($Data.Content)'" }
        else { $desc = "$($Data.Name) (Def: '$($Data.DefaultValue)')" }
        
        $txtDesc = New-Object System.Windows.Controls.TextBlock -Property @{ Text = $desc; VerticalAlignment = "Center" }
        
        # Indicateur Visuel [MAJ]
        if ($Data.IsUppercase) {
            $txtDesc.Text += " [MAJ]"
            $txtDesc.Foreground = [System.Windows.Media.Brushes]::Orange
        }

        # Indicateur Visuel [META]
        if ($Data.IsMetadata) {
            $txtDesc.Text += " [META]"
            $txtDesc.Foreground = [System.Windows.Media.Brushes]::Teal
            $txtDesc.FontWeight = "Bold"
        }

        $stack.Children.Add($border) | Out-Null
        $stack.Children.Add($txtDesc) | Out-Null
        
        $item.Content = $stack
        $Ctrl.FormList.Items.Add($item) | Out-Null
        
        $item.IsSelected = $true
        Invoke-AppSPFormUpdatePreview -Ctrl $Ctrl -Window $Window
    }.GetNewClosure()

    # ==========================================================================
    # 3. BOUTONS D'AJOUT
    # ==========================================================================
    $Ctrl.FormBtnAddLbl.Add_Click({
            $obj = [PSCustomObject]@{ Type = "Label"; Content = "-"; Width = ""; Name = ""; DefaultValue = ""; Options = @(); IsMetadata = $false }
            & $RenderListItem -Data $obj
        }.GetNewClosure())

    $Ctrl.FormBtnAddTxt.Add_Click({
            $obj = [PSCustomObject]@{ Type = "TextBox"; Name = "Variable"; DefaultValue = ""; Width = "100"; Content = ""; Options = @(); IsUppercase = $false; IsMetadata = $false }
            & $RenderListItem -Data $obj
        }.GetNewClosure())

    $Ctrl.FormBtnAddCmb.Add_Click({
            $obj = [PSCustomObject]@{ Type = "ComboBox"; Name = "Choix"; DefaultValue = ""; Width = "120"; Options = @("A", "B"); Content = ""; IsMetadata = $false }
            & $RenderListItem -Data $obj
        }.GetNewClosure())

    # ==========================================================================
    # 4. ACTIONS LISTE (Move / Delete)
    # ==========================================================================
    $Ctrl.FormBtnDel.Add_Click({
            $sel = $Ctrl.FormList.SelectedItem
            if ($sel) { 
                $Ctrl.FormList.Items.Remove($sel)
                Invoke-AppSPFormUpdatePreview -Ctrl $Ctrl -Window $Window
            }
        }.GetNewClosure())

    $Ctrl.FormBtnUp.Add_Click({
            $idx = $Ctrl.FormList.SelectedIndex
            if ($idx -gt 0) {
                $item = $Ctrl.FormList.Items[$idx]
                $Ctrl.FormList.Items.RemoveAt($idx)
                $Ctrl.FormList.Items.Insert($idx - 1, $item)
                $item.IsSelected = $true
                Invoke-AppSPFormUpdatePreview -Ctrl $Ctrl -Window $Window
            }
        }.GetNewClosure())

    $Ctrl.FormBtnDown.Add_Click({
            $idx = $Ctrl.FormList.SelectedIndex
            if ($idx -ne -1 -and $idx -lt ($Ctrl.FormList.Items.Count - 1)) {
                $item = $Ctrl.FormList.Items[$idx]
                $Ctrl.FormList.Items.RemoveAt($idx)
                $Ctrl.FormList.Items.Insert($idx + 1, $item)
                $item.IsSelected = $true
                Invoke-AppSPFormUpdatePreview -Ctrl $Ctrl -Window $Window
            }
        }.GetNewClosure())

    # ==========================================================================
    # 5. GESTION SÉLECTION & PROPRIÉTÉS
    # ==========================================================================
    $Ctrl.FormPropPanel.Tag = "Ready" 
    $Ctrl.FormList.Add_SelectionChanged({
            $sel = $Ctrl.FormList.SelectedItem
            $Ctrl.FormPropPanel.Tag = "Loading"

            if ($null -eq $sel) {
                $Ctrl.FormNoSelPanel.Visibility = "Visible"; $Ctrl.FormPropPanel.Visibility = "Collapsed"
            }
            else {
                $Ctrl.FormNoSelPanel.Visibility = "Collapsed"; $Ctrl.FormPropPanel.Visibility = "Visible"
                $data = $sel.Tag

                $Ctrl.PropName.Text = if ($data.Name) { $data.Name } else { "" }
                $Ctrl.PropWidth.Text = if ($data.Width) { $data.Width } else { "" }
                $Ctrl.PropContent.Text = if ($data.Content) { $data.Content } else { "" }
                $Ctrl.PropDefault.Text = if ($data.DefaultValue) { $data.DefaultValue } else { "" }
                $Ctrl.PropOptions.Text = if ($data.Options) { $data.Options -join "," } else { "" }

                $visName = "Visible" # Always allow Name (useful for Metadata key even for Label)
                $visContent = if ($data.Type -eq "Label") { "Visible" } else { "Collapsed" }
                $visDefault = if ($data.Type -eq "Label") { "Collapsed" } else { "Visible" }
                $visOptions = if ($data.Type -eq "ComboBox") { "Visible" } else { "Collapsed" }
                $visUpper = if ($data.Type -eq "TextBox") { "Visible" } else { "Collapsed" }

                if ($Ctrl.PanelName) { $Ctrl.PanelName.Visibility = $visName }
                if ($Ctrl.PanelContent) { $Ctrl.PanelContent.Visibility = $visContent }
                if ($Ctrl.PanelDefault) { $Ctrl.PanelDefault.Visibility = $visDefault }
                if ($Ctrl.PanelOptions) { $Ctrl.PanelOptions.Visibility = $visOptions }
                if ($Ctrl.PanelWidth) { $Ctrl.PanelWidth.Visibility = "Visible" } 
                if ($Ctrl.PanelForceUpper) { $Ctrl.PanelForceUpper.Visibility = $visUpper }
                
                # Metadata available for ALL types (including Label)
                if ($Ctrl.PanelIsMetadata) { 
                    $Ctrl.PanelIsMetadata.Visibility = "Visible"
                }
                
                # Binding Valeur Checkbox
                if ($Ctrl.PropForceUpper) {
                    $Ctrl.PropForceUpper.IsChecked = if ($data.IsUppercase) { $true } else { $false }
                }
                if ($Ctrl.PropIsMetadataCheck) {
                    $Ctrl.PropIsMetadataCheck.IsChecked = if ($data.IsMetadata) { $true } else { $false }
                }
                
                # Mise à jour visuelle du panel destination et de son contenu
                if ($data.IsMetadata) {
                    $Ctrl.PanelPropMetaTarget.Visibility = "Visible"
                    & $PopulateMetaTargets
                    $match = $Ctrl.PropMetaTargetBox.ItemsSource | Where-Object { $_.Name -eq $data.TargetColumnInternalName } | Select-Object -First 1
                    $Ctrl.PropMetaTargetBox.SelectedItem = $match
                }
                else {
                    $Ctrl.PanelPropMetaTarget.Visibility = "Collapsed"
                    $Ctrl.PropMetaTargetBox.SelectedItem = $null
                }
            }
            $Ctrl.FormPropPanel.Tag = "Ready"
        }.GetNewClosure())

    # ==========================================================================
    # 6. MODIFICATION PROPRIÉTÉS
    # ==========================================================================
    
    $RefreshListItem = {
        if ($Ctrl.FormPropPanel.Tag -eq "Loading") { return }
        $sel = $Ctrl.FormList.SelectedItem
        if ($sel) {
            $d = $sel.Tag
            $stack = $sel.Content
            $txt = $stack.Children[1]
            if ($d.Type -eq "Label") { 
                $txt.Text = "'$($d.Content)'" 
            }
            else { 
                $txt.Text = "$($d.Name) (Def: '$($d.DefaultValue)')" 
            }
            
            $color = [System.Windows.Media.Brushes]::Black

            if ($d.IsUppercase) { 
                $txt.Text += " [MAJ]" 
                $color = [System.Windows.Media.Brushes]::Orange 
            }
            
            # V3 : target column
            if ($null -eq $d.PSObject.Properties["TargetColumnInternalName"]) {
                $d | Add-Member -MemberType NoteProperty -Name "TargetColumnInternalName" -Value "" -Force
            }
            
            if ($d.IsMetadata) { 
                $txt.Text += " [META]" 
                $color = [System.Windows.Media.Brushes]::Teal 
                
                $Ctrl.PanelPropMetaTarget.Visibility = 'Visible'
                & $PopulateMetaTargets
                
                $match = $Ctrl.PropMetaTargetBox.ItemsSource | Where-Object { $_.InternalName -eq $d.TargetColumnInternalName } | Select-Object -First 1
                $Ctrl.PropMetaTargetBox.SelectedItem = $match
            }
            else {
                $Ctrl.PanelPropMetaTarget.Visibility = 'Collapsed'
                $Ctrl.PropMetaTargetBox.SelectedItem = $null
            }
            
            # Gestion de la couleur : Si les deux, on peut vouloir distinguer.
            if ($d.IsUppercase -and $d.IsMetadata) { $color = [System.Windows.Media.Brushes]::DarkViolet }
            
            $txt.Foreground = $color
            Invoke-AppSPFormUpdatePreview -Ctrl $Ctrl -Window $Window
        }
    }.GetNewClosure()

    $Ctrl.PropName.Add_TextChanged({ if ($Ctrl.FormList.SelectedItem) { $Ctrl.FormList.SelectedItem.Tag.Name = $this.Text; & $RefreshListItem } }.GetNewClosure())
    $Ctrl.PropContent.Add_TextChanged({ if ($Ctrl.FormList.SelectedItem) { $Ctrl.FormList.SelectedItem.Tag.Content = $this.Text; & $RefreshListItem } }.GetNewClosure())
    $Ctrl.PropDefault.Add_TextChanged({ if ($Ctrl.FormList.SelectedItem) { $Ctrl.FormList.SelectedItem.Tag.DefaultValue = $this.Text; & $RefreshListItem } }.GetNewClosure())
    $Ctrl.PropWidth.Add_TextChanged({ if ($Ctrl.FormList.SelectedItem) { $Ctrl.FormList.SelectedItem.Tag.Width = $this.Text; & $RefreshListItem } }.GetNewClosure())
    $Ctrl.PropOptions.Add_TextChanged({ 
            if ($Ctrl.FormList.SelectedItem) { 
                $arr = $this.Text.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                $Ctrl.FormList.SelectedItem.Tag.Options = $arr
                & $RefreshListItem 
            } 
        }.GetNewClosure())

    $Ctrl.PropForceUpper.Add_Checked({ 
            if ($Ctrl.FormPropPanel.Tag -eq "Loading") { return }
            if ($Ctrl.FormList.SelectedItem) { 
                # Ensure propery exists
                $t = $Ctrl.FormList.SelectedItem.Tag
                if ($null -eq $t.PSObject.Properties["IsUppercase"]) {
                    $t | Add-Member -MemberType NoteProperty -Name "IsUppercase" -Value $true -Force
                }
                else {
                    $t.IsUppercase = $true
                }
                $Ctrl.FormList.SelectedItem.Tag = $t
                & $RefreshListItem 
            } 
        }.GetNewClosure())

    $Ctrl.PropForceUpper.Add_Unchecked({ 
            if ($Ctrl.FormPropPanel.Tag -eq "Loading") { return }
            if ($Ctrl.FormList.SelectedItem) { 
                $t = $Ctrl.FormList.SelectedItem.Tag
                if ($null -eq $t.PSObject.Properties["IsUppercase"]) {
                    $t | Add-Member -MemberType NoteProperty -Name "IsUppercase" -Value $false -Force
                }
                else {
                    $t.IsUppercase = $false
                }
                $Ctrl.FormList.SelectedItem.Tag = $t
                & $RefreshListItem 
            } 
        }.GetNewClosure())



    $Ctrl.PropIsMetadataCheck.Add_Checked({ 
            if ($Ctrl.FormPropPanel.Tag -eq "Loading") { return }
            if ($Ctrl.FormList.SelectedItem) {
                $t = $Ctrl.FormList.SelectedItem.Tag

                if ($null -eq $t.PSObject.Properties["IsMetadata"]) {
                    $t | Add-Member -MemberType NoteProperty -Name "IsMetadata" -Value $true -Force
                }
                else {
                    $t.IsMetadata = $true
                }
                
                $Ctrl.PanelPropMetaTarget.Visibility = 'Visible'
                & $PopulateMetaTargets

                $Ctrl.FormList.SelectedItem.Tag = $t
                & $RefreshListItem 
            }
        }.GetNewClosure())
        
    $Ctrl.PropIsMetadataCheck.Add_Unchecked({ 
            if ($Ctrl.FormPropPanel.Tag -eq "Loading") { return }
            if ($Ctrl.FormList.SelectedItem) {
                $t = $Ctrl.FormList.SelectedItem.Tag

                if ($null -eq $t.PSObject.Properties["IsMetadata"]) {
                    $t | Add-Member -MemberType NoteProperty -Name "IsMetadata" -Value $false -Force
                }
                else {
                    $t.IsMetadata = $false
                }
                
                $Ctrl.PanelPropMetaTarget.Visibility = 'Collapsed'

                $Ctrl.FormList.SelectedItem.Tag = $t
                & $RefreshListItem 
            }
        }.GetNewClosure())

    $Ctrl.PropMetaTargetBox.Add_SelectionChanged({
            if ($Ctrl.FormPropPanel.Tag -eq "Loading") { return }
            if ($Ctrl.FormList.SelectedItem -and $this.SelectedItem) {
                $t = $Ctrl.FormList.SelectedItem.Tag
                if ($null -eq $t.PSObject.Properties["TargetColumnInternalName"]) {
                    $t | Add-Member -MemberType NoteProperty -Name "TargetColumnInternalName" -Value $this.SelectedItem.Name -Force
                }
                else {
                    $t.TargetColumnInternalName = $this.SelectedItem.Name
                }
                $Ctrl.FormList.SelectedItem.Tag = $t
            }
        }.GetNewClosure())

    # ==========================================================================
    # 7. PERSISTANCE (LOAD / SAVE / NEW / DELETE)
    # ==========================================================================
    
    # A. CHARGEMENT LISTE (CLEAN)
    $LoadFormList = {
        $rules = @(Get-AppNamingRules) # Appel Module Database
        $Ctrl.FormLoadCb.ItemsSource = $rules
        $Ctrl.FormLoadCb.DisplayMemberPath = "RuleId"
    }.GetNewClosure()
    & $LoadFormList

    # B. NOUVEAU (V3: Ouvre la popup de choix du schéma)
    $Ctrl.FormBtnNew.Add_Click({
            if ($Ctrl.FormList.Items.Count -gt 0) {
                if ([System.Windows.MessageBox]::Show("Créer un nouveau formulaire remplacera le formulaire actuel non sauvegardé. Continuer ?", "Confirmer", "YesNo", "Warning") -eq 'No') { return }
            }
            
            # Charger les schémas dans la combobox de la popup
            $schemas = @(Get-AppSPFolderSchema)
            if ($schemas.Count -eq 0) {
                [System.Windows.MessageBox]::Show("Il n'y a aucun Schéma Avancé (Modèle) en base. Veuillez en créer un d'abord.", "Erreur", "OK", "Error")
                return
            }
            
            $Ctrl.FormNewPopupSchemaCb.ItemsSource = $schemas
            $Ctrl.FormNewPopupSchemaCb.DisplayMemberPath = "DisplayName"
            $Ctrl.FormNewPopupConfirmBtn.IsEnabled = $false
            
            $Ctrl.FormNewPopupOverlay.Visibility = 'Visible'
        }.GetNewClosure())

    # B.1. POPUP NOUVEAU : SELECTION CHANGED
    $Ctrl.FormNewPopupSchemaCb.Add_SelectionChanged({
            $Ctrl.FormNewPopupConfirmBtn.IsEnabled = ($null -ne $this.SelectedItem)
        }.GetNewClosure())

    # B.2. POPUP NOUVEAU : ANNULER
    $Ctrl.FormNewPopupCancelBtn.Add_Click({
            $Ctrl.FormNewPopupOverlay.Visibility = 'Collapsed'
            $Ctrl.FormNewPopupSchemaCb.SelectedItem = $null
        }.GetNewClosure())

    # B.3. POPUP NOUVEAU : CONFIRMER
    $Ctrl.FormNewPopupConfirmBtn.Add_Click({
            $selSchema = $Ctrl.FormNewPopupSchemaCb.SelectedItem
            if (-not $selSchema) { return }

            $Ctrl.FormList.Items.Clear()
            $Ctrl.FormLoadCb.Tag = $null
            $Ctrl.FormLoadCb.SelectedIndex = -1
        
            # Déverrouiller l'interface et enregistrer le schéma cible en mémoire
            $Ctrl.FormWorkspaceLockOverlay.Visibility = 'Collapsed'
            $Ctrl.FormTargetSchemaDisplay.Text = $selSchema.DisplayName
            $Ctrl.FormTargetSchemaDisplay.Tag = $selSchema.SchemaId
            $Ctrl.FormBtnSave.IsEnabled = $true

            $Ctrl.FormNewPopupOverlay.Visibility = 'Collapsed'
            $Ctrl.FormNewPopupSchemaCb.SelectedItem = $null

            Invoke-AppSPFormUpdatePreview -Ctrl $Ctrl -Window $Window
            & $SetFormStatus -Msg "Nouveau formulaire lié au schéma '$($selSchema.DisplayName)' prêt."
        }.GetNewClosure())

    # C. SAUVEGARDE (CLEAN)
    $Ctrl.FormBtnSave.Add_Click({
            if ($Ctrl.FormList.Items.Count -eq 0) { & $SetFormStatus -Msg "Le formulaire est vide." -Type "Warning"; return }
            
            # Récupération du Schema Target ID
            $schemaId = $Ctrl.FormTargetSchemaDisplay.Tag
            if (-not $schemaId) {
                [System.Windows.MessageBox]::Show("Erreur interne : Aucun Schéma Cible défini pour ce formulaire.", "Erreur", "OK", "Error")
                return
            }

            $layoutList = @()
            foreach ($item in $Ctrl.FormList.Items) { $layoutList += $item.Tag }
            
            # V3 : Injection du TargetSchemaId à la racine
            $finalObj = @{ TargetSchemaId = $schemaId; Layout = $layoutList; Description = "Règle personnalisée" }
            $json = $finalObj | ConvertTo-Json -Depth 5 -Compress
        
            # Note : Le .Replace() est géré par le module Database, on envoie le JSON brut
        
            $currentId = $Ctrl.FormLoadCb.Tag
            if ($currentId) {
                # Mode "Enregistrer Sous" ou "Écraser" si c'est déjà un modèle existant
                $msg = "La règle '$currentId' est chargée.`n`nOUI : Écraser`nNON : Enregistrer copie`nANNULER : Retour"
                $choice = [System.Windows.MessageBox]::Show($msg, "Sauvegarde", [System.Windows.MessageBoxButton]::YesNoCancel, [System.Windows.MessageBoxImage]::Question)
                switch ($choice) {
                    'Cancel' { return }
                    'No' {
                        $currentId = $null # Force nouvelle saisie
                    }
                }
            }

            if (-not $currentId) {
                Add-Type -AssemblyName Microsoft.VisualBasic
                $name = [Microsoft.VisualBasic.Interaction]::InputBox("Nom de la règle (ID unique) :", "Sauvegarder", "Rule-Custom-01")
                if ([string]::IsNullOrWhiteSpace($name)) { return }
                $currentId = $name
            }

            try {
                # APPEL PROPRE MODULE DATABASE
                Set-AppNamingRule -RuleId $currentId -DefinitionJson $json
                
                # REFRESH GLOBAL CONFIG (CRITICAL for Dynamic Tag Selector)
                if (Get-Command "Get-AppNamingRules" -ErrorAction SilentlyContinue) {
                    $rules = @(Get-AppNamingRules)
                    if ($Global:AppConfig -and $Global:AppConfig.PSObject.Properties.Match("namingRules").Count -eq 0) {
                        $Global:AppConfig | Add-Member -MemberType NoteProperty -Name "namingRules" -Value $rules -Force
                    }
                    elseif ($Global:AppConfig) {
                        $Global:AppConfig.namingRules = $rules
                    }
                } 
                elseif (Get-Command "Get-AppConfig" -ErrorAction SilentlyContinue) {
                    # Fallback reload
                    $Global:AppConfig = Get-AppConfig
                }
            
                & $SetFormStatus -Msg "Règle '$currentId' sauvegardée avec succès." -Type "Success"
            
                & $LoadFormList
                $newItem = $Ctrl.FormLoadCb.ItemsSource | Where-Object { $_.RuleId -eq $currentId } | Select-Object -First 1
                if ($newItem) { 
                    $Ctrl.FormLoadCb.SelectedItem = $newItem 
                    $Ctrl.FormLoadCb.Tag = $currentId
                }

            }
            catch { & $SetFormStatus -Msg "Erreur lors de la sauvegarde : $($_.Exception.Message)" -Type "Error" }
        }.GetNewClosure())

    # D. CHARGER
    $Ctrl.FormBtnLoad.Add_Click({
            $sel = $Ctrl.FormLoadCb.SelectedItem
            if (-not $sel) { return }
        
            $Ctrl.FormList.Items.Clear()
            $Ctrl.FormLoadCb.Tag = $sel.RuleId

            try {
                $parsed = $sel.DefinitionJson | ConvertFrom-Json
                $layout = $parsed.Layout
                
                # Récupération et affichage du Schéma (V3)
                $schemaId = $parsed.TargetSchemaId
                if ($schemaId) {
                    $schemaObj = @(Get-AppSPFolderSchema) | Where-Object { $_.SchemaId -eq $schemaId } | Select-Object -First 1
                    if ($schemaObj) {
                        $Ctrl.FormTargetSchemaDisplay.Text = $schemaObj.DisplayName
                        $Ctrl.FormTargetSchemaDisplay.Tag = $schemaObj.SchemaId
                    }
                    else {
                        $Ctrl.FormTargetSchemaDisplay.Text = "Schéma orphelin ($schemaId)"
                        $Ctrl.FormTargetSchemaDisplay.Tag = $schemaId
                    }
                }
                else {
                    $Ctrl.FormTargetSchemaDisplay.Text = "Non lié (Legacy)"
                    $Ctrl.FormTargetSchemaDisplay.Tag = $null
                }

                # Déverrouiller l'interface
                $Ctrl.FormWorkspaceLockOverlay.Visibility = 'Collapsed'
                $Ctrl.FormBtnSave.IsEnabled = $true

                foreach ($field in $layout) {
                    $obj = [PSCustomObject]@{
                        Type                     = $field.Type
                        Name                     = if ($field.Name) { $field.Name }else { "" }
                        Content                  = if ($field.Content) { $field.Content }else { "" }
                        DefaultValue             = if ($field.DefaultValue) { $field.DefaultValue }else { "" }
                        Width                    = if ($field.Width) { $field.Width }else { "100" }
                        Options                  = if ($field.Options) { $field.Options }else { @() }
                        IsUppercase              = if ($field.IsUppercase) { $field.IsUppercase } else { $false }
                        IsMetadata               = if ($field.IsMetadata) { $field.IsMetadata } else { $false }
                        TargetColumnInternalName = if ($field.TargetColumnInternalName) { $field.TargetColumnInternalName } else { "" }
                    }
                    & $RenderListItem -Data $obj
                }
                & $SetFormStatus -Msg "Règle '$($sel.RuleId)' chargée." -Type "Success"
            }
            catch { & $SetFormStatus -Msg "Erreur chargement : $_" -Type "Error" }

        }.GetNewClosure())
    
    # E. SUPPRIMER (CLEAN)
    if ($Ctrl.FormBtnDelTpl) {
        $Ctrl.FormBtnDelTpl.Add_Click({
                $id = $Ctrl.FormLoadCb.Tag
                if (-not $id -and $Ctrl.FormLoadCb.SelectedItem) { $id = $Ctrl.FormLoadCb.SelectedItem.RuleId }
                if (-not $id) { return }

                if ([System.Windows.MessageBox]::Show("Supprimer la règle '$id' ?", "Confirmer", "YesNo", "Error") -eq 'Yes') {
                    try {
                        # APPEL PROPRE MODULE DATABASE
                        Remove-AppNamingRule -RuleId $id
                    
                        $Ctrl.FormList.Items.Clear()
                        $Ctrl.FormLoadCb.Tag = $null
                        & $LoadFormList
                        Invoke-AppSPFormUpdatePreview -Ctrl $Ctrl -Window $Window
                        & $SetFormStatus -Msg "Règle '$id' supprimée." -Type "Normal"
                    }
                    catch { & $SetFormStatus -Msg "Erreur suppression : $($_.Exception.Message)" -Type "Error" }
                }
            }.GetNewClosure())
    }
}
