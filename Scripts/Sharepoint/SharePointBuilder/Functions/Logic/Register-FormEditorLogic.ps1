# Scripts/SharePoint/SharePointBuilder/Functions/Logic/Register-FormEditorLogic.ps1

function Register-FormEditorLogic {
    param(
        [hashtable]$Ctrl,
        [System.Windows.Window]$Window
    )

    # ==========================================================================
    # 1. HELPER : RENDU DE LA PREVIEW (BAS)
    # ==========================================================================
    $UpdateLivePreview = {
        if (-not $Ctrl.FormLivePreview) { return }
        
        $panel = $Ctrl.FormLivePreview
        $panel.Children.Clear()

        foreach ($item in $Ctrl.FormList.Items) {
            $data = $item.Tag
            if (-not $data) { continue }
            
            $widthVal = 100
            if ($data.Width -and [int]::TryParse($data.Width, [ref]$widthVal)) { }
            $finalWidth = [double]$widthVal
            
            if ($data.Type -eq "Label") {
                $ctrl = New-Object System.Windows.Controls.TextBlock
                $ctrl.Text = $data.Content
                $ctrl.VerticalAlignment = "Center"
                $ctrl.FontWeight = "Bold"
                $ctrl.Margin = "0,0,5,0"
                $ctrl.Foreground = $Window.FindResource("TextPrimaryBrush")
                $panel.Children.Add($ctrl) | Out-Null
            }
            elseif ($data.Type -eq "TextBox") {
                $ctrl = New-Object System.Windows.Controls.TextBox
                $ctrl.Text = $data.DefaultValue
                $ctrl.Width = $finalWidth
                $ctrl.Margin = "0,0,5,0"
                $ctrl.Style = $Window.FindResource("StandardTextBoxStyle")
                $panel.Children.Add($ctrl) | Out-Null
            }
            elseif ($data.Type -eq "ComboBox") {
                $ctrl = New-Object System.Windows.Controls.ComboBox
                $ctrl.Width = $finalWidth
                $ctrl.Margin = "0,0,5,0"
                $ctrl.Style = $Window.FindResource("StandardComboBoxStyle")
                if ($data.Options) {
                    $ctrl.ItemsSource = $data.Options
                    $ctrl.SelectedIndex = 0
                }
                $panel.Children.Add($ctrl) | Out-Null
            }
        }
    }.GetNewClosure()

    # ==========================================================================
    # 2. HELPER : RENDU LISTE GAUCHE
    # ==========================================================================
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
        
        $stack.Children.Add($border) | Out-Null
        $stack.Children.Add($txtDesc) | Out-Null
        
        $item.Content = $stack
        $Ctrl.FormList.Items.Add($item) | Out-Null
        
        $item.IsSelected = $true
        & $UpdateLivePreview
    }.GetNewClosure()

    # ==========================================================================
    # 3. BOUTONS D'AJOUT
    # ==========================================================================
    $Ctrl.FormBtnAddLbl.Add_Click({
            $obj = [PSCustomObject]@{ Type = "Label"; Content = "-"; Width = ""; Name = ""; DefaultValue = ""; Options = @() }
            & $RenderListItem -Data $obj
        }.GetNewClosure())

    $Ctrl.FormBtnAddTxt.Add_Click({
            $obj = [PSCustomObject]@{ Type = "TextBox"; Name = "Variable"; DefaultValue = ""; Width = "100"; Content = ""; Options = @() }
            & $RenderListItem -Data $obj
        }.GetNewClosure())

    $Ctrl.FormBtnAddCmb.Add_Click({
            $obj = [PSCustomObject]@{ Type = "ComboBox"; Name = "Choix"; DefaultValue = ""; Width = "120"; Options = @("A", "B"); Content = "" }
            & $RenderListItem -Data $obj
        }.GetNewClosure())

    # ==========================================================================
    # 4. ACTIONS LISTE (Move / Delete)
    # ==========================================================================
    $Ctrl.FormBtnDel.Add_Click({
            $sel = $Ctrl.FormList.SelectedItem
            if ($sel) { $Ctrl.FormList.Items.Remove($sel); & $UpdateLivePreview }
        }.GetNewClosure())

    $Ctrl.FormBtnUp.Add_Click({
            $idx = $Ctrl.FormList.SelectedIndex
            if ($idx -gt 0) {
                $item = $Ctrl.FormList.Items[$idx]
                $Ctrl.FormList.Items.RemoveAt($idx)
                $Ctrl.FormList.Items.Insert($idx - 1, $item)
                $item.IsSelected = $true
                & $UpdateLivePreview
            }
        }.GetNewClosure())

    $Ctrl.FormBtnDown.Add_Click({
            $idx = $Ctrl.FormList.SelectedIndex
            if ($idx -ne -1 -and $idx -lt ($Ctrl.FormList.Items.Count - 1)) {
                $item = $Ctrl.FormList.Items[$idx]
                $Ctrl.FormList.Items.RemoveAt($idx)
                $Ctrl.FormList.Items.Insert($idx + 1, $item)
                $item.IsSelected = $true
                & $UpdateLivePreview
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
                $Ctrl.FormNoSelPanel.Visibility = "Visible"
                $Ctrl.FormPropPanel.Visibility = "Collapsed"
            }
            else {
                $Ctrl.FormNoSelPanel.Visibility = "Collapsed"
                $Ctrl.FormPropPanel.Visibility = "Visible"
            
                $data = $sel.Tag

                # Chargement Valeurs
                $Ctrl.PropName.Text = if ($data.Name) { $data.Name } else { "" }
                $Ctrl.PropWidth.Text = if ($data.Width) { $data.Width } else { "" }
                $Ctrl.PropContent.Text = if ($data.Content) { $data.Content } else { "" }
                $Ctrl.PropDefault.Text = if ($data.DefaultValue) { $data.DefaultValue } else { "" }
                $Ctrl.PropOptions.Text = if ($data.Options) { $data.Options -join "," } else { "" }

                # Gestion Visibilité selon Type
                $visName = "Collapsed"
                $visContent = "Collapsed"
                $visDefault = "Collapsed"
                $visOptions = "Collapsed"
                $visWidth = "Collapsed"

                switch ($data.Type) {
                    "Label" {
                        $visContent = "Visible" # Texte Fixe
                        # Pas de nom, pas de default, pas de width pour un label simple
                    }
                    "TextBox" {
                        $visName = "Visible"
                        $visDefault = "Visible"
                        $visWidth = "Visible"
                    }
                    "ComboBox" {
                        $visName = "Visible"
                        $visOptions = "Visible"
                        $visDefault = "Visible"
                        $visWidth = "Visible"
                    }
                }

                # Application sur les PANNEAUX nommés (Plus de .Parent hasardeux)
                if ($Ctrl.PanelName) { $Ctrl.PanelName.Visibility = $visName }
                if ($Ctrl.PanelContent) { $Ctrl.PanelContent.Visibility = $visContent }
                if ($Ctrl.PanelDefault) { $Ctrl.PanelDefault.Visibility = $visDefault }
                if ($Ctrl.PanelOptions) { $Ctrl.PanelOptions.Visibility = $visOptions }
                if ($Ctrl.PanelWidth) { $Ctrl.PanelWidth.Visibility = $visWidth }
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
            if ($d.Type -eq "Label") { $txt.Text = "'$($d.Content)'" }
            else { $txt.Text = "$($d.Name) (Def: '$($d.DefaultValue)')" }
            & $UpdateLivePreview
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

    # ==========================================================================
    # 7. PERSISTANCE (SAUVEGARDE INTELLIGENTE)
    # ==========================================================================
    
    $LoadFormList = {
        try {
            $rules = @(Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query "SELECT * FROM sp_naming_rules")
            $Ctrl.FormLoadCb.ItemsSource = $rules
            $Ctrl.FormLoadCb.DisplayMemberPath = "RuleId"
        }
        catch { }
    }.GetNewClosure()
    & $LoadFormList

    # NOUVEAU
    $Ctrl.FormBtnNew.Add_Click({
            if ([System.Windows.MessageBox]::Show("Vider le formulaire ?", "Confirmer", "YesNo", "Warning") -eq 'Yes') {
                $Ctrl.FormList.Items.Clear()
                $Ctrl.FormLoadCb.Tag = $null
                $Ctrl.FormLoadCb.SelectedIndex = -1
                & $UpdateLivePreview
            }
        }.GetNewClosure())

    # SAUVEGARDE (Logique mise à jour)
    $Ctrl.FormBtnSave.Add_Click({
            if ($Ctrl.FormList.Items.Count -eq 0) { return }

            $layoutList = @()
            foreach ($item in $Ctrl.FormList.Items) { $layoutList += $item.Tag }
            $finalObj = @{ Layout = $layoutList; Description = "Règle personnalisée" }
            $json = $finalObj | ConvertTo-Json -Depth 5 -Compress
            $cleanJson = $json.Replace("'", "''")

            $currentId = $Ctrl.FormLoadCb.Tag
            $currentName = if ($Ctrl.FormLoadCb.SelectedItem) { $Ctrl.FormLoadCb.SelectedItem.RuleId } else { "" }

            # 1. Logique de choix si existant
            if ($currentId) {
                $msg = "La règle '$currentName' est actuellement chargée.`n`nVoulez-vous écraser les modifications ?`n`nOUI : Écraser l'existant`nNON : Créer une copie (Enregistrer sous)`nANNULER : Ne rien faire"
                $choice = [System.Windows.MessageBox]::Show($msg, "Sauvegarde", [System.Windows.MessageBoxButton]::YesNoCancel, [System.Windows.MessageBoxImage]::Question)

                switch ($choice) {
                    'Cancel' { return }
                    'No' {
                        # Save As
                        $currentId = $null
                        Add-Type -AssemblyName Microsoft.VisualBasic
                        $newName = [Microsoft.VisualBasic.Interaction]::InputBox("Nom de la nouvelle règle (ID) :", "Enregistrer une copie", "$currentName-Copie")
                        if ([string]::IsNullOrWhiteSpace($newName)) { return }
                        $currentId = $newName
                    }
                    'Yes' { 
                        # Overwrite : on garde l'ID
                    }
                }
            }

            # 2. Logique Nouveau
            if (-not $currentId) {
                Add-Type -AssemblyName Microsoft.VisualBasic
                $newName = [Microsoft.VisualBasic.Interaction]::InputBox("Nom de la règle (ID unique) :", "Sauvegarder", "Rule-Custom-01")
                if ([string]::IsNullOrWhiteSpace($newName)) { return }
                $currentId = $newName
            }

            # 3. SQL
            try {
                $query = "INSERT OR REPLACE INTO sp_naming_rules (RuleId, DefinitionJson) VALUES ('$currentId', '$cleanJson');"
                Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $query
                [System.Windows.MessageBox]::Show("Règle sauvegardée !", "Succès", "OK", "Information")
            
                & $LoadFormList
            
                $newItem = $Ctrl.FormLoadCb.ItemsSource | Where-Object { $_.RuleId -eq $currentId } | Select-Object -First 1
                if ($newItem) { 
                    $Ctrl.FormLoadCb.SelectedItem = $newItem 
                    $Ctrl.FormLoadCb.Tag = $currentId
                }

            }
            catch { [System.Windows.MessageBox]::Show("Erreur : $($_.Exception.Message)", "Erreur", "OK", "Error") }
        }.GetNewClosure())

    # CHARGER
    $Ctrl.FormBtnLoad.Add_Click({
            $sel = $Ctrl.FormLoadCb.SelectedItem
            if (-not $sel) { return }
        
            if ($Ctrl.FormList.Items.Count -gt 0) {
                if ([System.Windows.MessageBox]::Show("Charger va écraser le formulaire actuel.", "Attention", "YesNo", "Warning") -ne 'Yes') { return }
            }

            $Ctrl.FormList.Items.Clear()
            $Ctrl.FormLoadCb.Tag = $sel.RuleId

            try {
                $layout = ($sel.DefinitionJson | ConvertFrom-Json).Layout
                foreach ($field in $layout) {
                    $obj = [PSCustomObject]@{
                        Type         = $field.Type
                        Name         = if ($field.Name) { $field.Name }else { "" }
                        Content      = if ($field.Content) { $field.Content }else { "" }
                        DefaultValue = if ($field.DefaultValue) { $field.DefaultValue }else { "" }
                        Width        = if ($field.Width) { $field.Width }else { "100" }
                        Options      = if ($field.Options) { $field.Options }else { @() }
                    }
                    & $RenderListItem -Data $obj
                }
            }
            catch { Write-AppLog "Erreur chargement règle : $_" }

        }.GetNewClosure())
    
    # SUPPRIMER
    if ($Ctrl.FormBtnDelTpl) {
        $Ctrl.FormBtnDelTpl.Add_Click({
                $id = $Ctrl.FormLoadCb.Tag
                if (-not $id -and $Ctrl.FormLoadCb.SelectedItem) { $id = $Ctrl.FormLoadCb.SelectedItem.RuleId }
                if (-not $id) { return }

                if ([System.Windows.MessageBox]::Show("Supprimer la règle '$id' ?", "Confirmer", "YesNo", "Error") -eq 'Yes') {
                    Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query "DELETE FROM sp_naming_rules WHERE RuleId = '$id'"
                    $Ctrl.FormList.Items.Clear()
                    $Ctrl.FormLoadCb.Tag = $null
                    & $LoadFormList
                    & $UpdateLivePreview
                }
            }.GetNewClosure())
    }
}