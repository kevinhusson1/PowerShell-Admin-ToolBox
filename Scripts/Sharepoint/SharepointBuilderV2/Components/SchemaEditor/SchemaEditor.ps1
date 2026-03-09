function Register-SchemaEditorEvents {
    param($Window, $Context)

    # Récupération des contrôles avec LogicalTreeHelper pour passer la barrière des onglets dynamiques
    $BtnAddColumn = [System.Windows.LogicalTreeHelper]::FindLogicalNode($Window, "SchemaAddColumnButton")
    $ColumnsContainer = [System.Windows.LogicalTreeHelper]::FindLogicalNode($Window, "SchemaColumnsContainer")
    $BtnSave = [System.Windows.LogicalTreeHelper]::FindLogicalNode($Window, "SchemaSaveButton")
    $BtnNew = [System.Windows.LogicalTreeHelper]::FindLogicalNode($Window, "SchemaNewButton")
    $BtnLoad = [System.Windows.LogicalTreeHelper]::FindLogicalNode($Window, "SchemaLoadButton")
    $BtnDel = [System.Windows.LogicalTreeHelper]::FindLogicalNode($Window, "SchemaDeleteButton")
    $CbSchemas = [System.Windows.LogicalTreeHelper]::FindLogicalNode($Window, "SchemaLoadComboBox")
    
    $TxtSchemaName = [System.Windows.LogicalTreeHelper]::FindLogicalNode($Window, "SchemaNameTextBox")
    $TxtSchemaDesc = [System.Windows.LogicalTreeHelper]::FindLogicalNode($Window, "SchemaDescTextBox")
    
    # Validation
    if (-not $BtnAddColumn -or -not $ColumnsContainer) { return }

    $UpdateSchemaComboBox = {
        $CbSchemas.Items.Clear()
        $schemas = Get-AppSPFolderSchema
        if ($schemas) {
            foreach ($s in @($schemas)) {
                $item = New-Object System.Windows.Controls.ComboBoxItem
                $item.Content = $s.DisplayName
                $item.Tag = $s.SchemaId
                $CbSchemas.Items.Add($item) | Out-Null
            }
        }
    }.GetNewClosure()

    & $UpdateSchemaComboBox

    # Ajouter une colonne
    $BtnAddColumn.add_Click({
            # Création d'un Grid pour une ligne de colonne
            $rowGrid = New-Object System.Windows.Controls.Grid
            $rowGrid.Margin = "0,0,0,10"
        
            $colDef1 = New-Object System.Windows.Controls.ColumnDefinition
            $colDef1.Width = [System.Windows.GridLength]::new(2, [System.Windows.GridUnitType]::Star)
            $colDef2 = New-Object System.Windows.Controls.ColumnDefinition
            $colDef2.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
            $colDef3 = New-Object System.Windows.Controls.ColumnDefinition
            $colDef3.Width = [System.Windows.GridLength]::new(110, [System.Windows.GridUnitType]::Pixel)
            $colDef4 = New-Object System.Windows.Controls.ColumnDefinition
            $colDef4.Width = [System.Windows.GridLength]::new(40, [System.Windows.GridUnitType]::Pixel)
            $rowGrid.ColumnDefinitions.Add($colDef1)
            $rowGrid.ColumnDefinitions.Add($colDef2)
            $rowGrid.ColumnDefinitions.Add($colDef3)
            $rowGrid.ColumnDefinitions.Add($colDef4)

            # 1. Nom
            $txtName = New-Object System.Windows.Controls.TextBox
            $txtName.Margin = "0,0,10,0"
            $styleName = $Window.TryFindResource("StandardTextBoxStyle")
            if ($styleName -is [System.Windows.Style]) { $txtName.Style = $styleName }
            $txtName.Tag = "ColName" # pour le retrouver
            $txtName.ToolTip = "Saisissez le nom système de la colonne SharePoint (ex: NomClient, MontantHT)."
            [System.Windows.Controls.Grid]::SetColumn($txtName, 0)
        
            # 2. Type
            $cbType = New-Object System.Windows.Controls.ComboBox
            $cbType.Margin = "0,0,10,0"
            $styleType = $Window.TryFindResource("StandardComboBoxStyle")
            if ($styleType -is [System.Windows.Style]) { $cbType.Style = $styleType }
            $cbType.Items.Add("Texte") | Out-Null
            $cbType.Items.Add("Nombre") | Out-Null
            $cbType.Items.Add("Date et Heure") | Out-Null
            $cbType.Items.Add("Oui/Non") | Out-Null
            $cbType.Items.Add("Choix Multiples") | Out-Null
            $cbType.SelectedIndex = 0
            $cbType.Tag = "ColType"
            $cbType.ToolTip = "Détermine le format métier des données (Texte, Montant, Nombre de jours...)."
            [System.Windows.Controls.Grid]::SetColumn($cbType, 1)

            # 3. Indexable
            $chkIndexable = New-Object System.Windows.Controls.CheckBox
            $chkIndexable.Content = "Indexable"
            $chkIndexable.VerticalAlignment = "Center"
            $chkIndexable.Margin = "0,0,10,0"
            $styleToggle = $Window.TryFindResource("ToggleSwitchStyle")
            if ($styleToggle -is [System.Windows.Style]) { $chkIndexable.Style = $styleToggle }
            $chkIndexable.Tag = "ColIndexed"
            $chkIndexable.ToolTip = "Cochez pour indexer la colonne, ce qui accélérera les recherches SharePoint basées sur ce champ."
        
            # Astuce : Mettre le texte du CheckBox avec le style Toggle requiert parfois un StackPanel, 
            # mais le ToggleSwitchStyle a un ContentPresenter implicite qui affiche le "Content".
            [System.Windows.Controls.Grid]::SetColumn($chkIndexable, 2)

            # 4. Suppression
            $btnDelete = New-Object System.Windows.Controls.Button
            $btnDelete.Content = "❌"
            # Style bouton d'icône rouge léger pour suppression
            $styleDanger = $Window.TryFindResource("DangerButtonStyle")
            if ($styleDanger -is [System.Windows.Style]) {
                $btnDelete.Style = $styleDanger
                $btnDelete.Padding = "5"
            }
            else {
                $btnDelete.Width = 30
                $btnDelete.Height = 30
                $btnDelete.Background = "Transparent"
                $btnDelete.BorderThickness = 0
                $btnDelete.Foreground = "Red"
            }
            $btnDelete.Tag = @{ Container = $ColumnsContainer; Row = $rowGrid }
            $btnDelete.add_Click({
                    if ($_) { $_.Handled = $true }
                    $res = [System.Windows.MessageBox]::Show(
                        "Êtes-vous sûr de vouloir supprimer cette colonne du modèle SharePoint ?",
                        "Confirmation de suppression",
                        "YesNo",
                        "Warning"
                    )
                    if ($res -eq "Yes") {
                        $ctx = $this.Tag
                        $ctx.Container.Items.Remove($ctx.Row)
                    }
                })
            [System.Windows.Controls.Grid]::SetColumn($btnDelete, 3)

            $rowGrid.Children.Add($txtName) | Out-Null
            $rowGrid.Children.Add($cbType) | Out-Null
            $rowGrid.Children.Add($chkIndexable) | Out-Null
            $rowGrid.Children.Add($btnDelete) | Out-Null

            $ColumnsContainer.Items.Add($rowGrid) | Out-Null
        }.GetNewClosure())

    # Nouveau modèle
    $BtnNew.add_Click({
            $TxtSchemaName.Text = ""
            $TxtSchemaDesc.Text = ""
            $ColumnsContainer.Items.Clear()
            Write-Host "Reset Schema Editor"
        }.GetNewClosure())
    
    # Save Model (BDD SQLite)
    $BtnSave.add_Click({
            $name = $TxtSchemaName.Text
            if ([string]::IsNullOrWhiteSpace($name)) {
                [System.Windows.MessageBox]::Show("Le nom du schéma est requis.", "Erreur", "OK", "Warning")
                return
            }

            if ($ColumnsContainer.Items.Count -eq 0) {
                [System.Windows.MessageBox]::Show("Le schéma doit contenir au moins une colonne.", "Erreur", "OK", "Warning")
                return
            }
        
            $schemaObj = @{
                Name        = $name
                Description = $TxtSchemaDesc.Text
                Columns     = @()
            }

            foreach ($row in $ColumnsContainer.Items) {
                $colName = ($row.Children | Where-Object { $_.Tag -eq "ColName" }).Text
                $colType = ($row.Children | Where-Object { $_.Tag -eq "ColType" }).SelectedItem
                $isIndexed = ($row.Children | Where-Object { $_.Tag -eq "ColIndexed" }).IsChecked -eq $true

                if (-not [string]::IsNullOrWhiteSpace($colName)) {
                    $schemaObj.Columns += @{
                        Name    = $colName -replace '[^a-zA-Z0-9_]', '' # Sanitize SharePoint
                        Type    = $colType
                        Indexed = $isIndexed
                    }
                }
            }
        
            $json = $schemaObj.Columns | ConvertTo-Json -Depth 5 -Compress
            if ([string]::IsNullOrWhiteSpace($json)) {
                $json = "[]"
            }
        
            # v4.20 : Utilisation d'un GUID pour les nouveaux schémas
            $schemaId = $null
            if ($CbSchemas.SelectedItem) {
                # On garde l'ID existant si on modifie
                $schemaId = $CbSchemas.SelectedItem.Tag
            }
            else {
                # Nouveau : GUID unique
                $schemaId = [guid]::NewGuid().ToString()
            }
        
            try {
                Set-AppSPFolderSchema -SchemaId $schemaId -DisplayName $name -Description $TxtSchemaDesc.Text -ColumnsJson $json
                [System.Windows.MessageBox]::Show("Modèle '$name' sauvegardé avec succès !", "Enregistrement", "OK", "Information")
                & $UpdateSchemaComboBox
            
                # Selectionner le nouvel élément
                foreach ($item in $CbSchemas.Items) {
                    if ($item.Tag -eq $schemaId) {
                        $CbSchemas.SelectedItem = $item
                        break
                    }
                }
            }
            catch {
                [System.Windows.MessageBox]::Show("Erreur de sauvegarde : $($_.Exception.Message)", "Erreur", "OK", "Error")
            }
        }.GetNewClosure())

    # Load Model (BDD SQLite)
    $BtnLoad.add_Click({
            if ($CbSchemas.SelectedItem) {
                $schemaId = $CbSchemas.SelectedItem.Tag
                $schema = Get-AppSPFolderSchema -SchemaId $schemaId
                if ($schema) {
                    $TxtSchemaName.Text = $schema.DisplayName
                    $TxtSchemaDesc.Text = $schema.Description
                    $ColumnsContainer.Items.Clear()
                
                    $columns = $schema.ColumnsJson | ConvertFrom-Json
                    foreach ($col in $columns) {
                        # On simule un clic bouton pour générer la grille, puis on remplit
                        $BtnAddColumn.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
                        $lastGrid = $ColumnsContainer.Items[$ColumnsContainer.Items.Count - 1]
                    
                        ($lastGrid.Children | Where-Object { $_.Tag -eq "ColName" }).Text = $col.Name
                        ($lastGrid.Children | Where-Object { $_.Tag -eq "ColType" }).SelectedItem = $col.Type
                        ($lastGrid.Children | Where-Object { $_.Tag -eq "ColIndexed" }).IsChecked = $col.Indexed
                    }
                }
            }
        }.GetNewClosure())

    # Delete Model (BDD SQLite)
    $BtnDel.add_Click({
            if ($CbSchemas.SelectedItem) {
                $res = [System.Windows.MessageBox]::Show("Voulez-vous vraiment supprimer ce schéma ?", "Confirmation", "YesNo", "Warning")
                if ($res -eq "Yes") {
                    $schemaId = $CbSchemas.SelectedItem.Tag
                    try {
                        Remove-AppSPFolderSchema -SchemaId $schemaId
                        & $UpdateSchemaComboBox
                        $BtnNew.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
                    }
                    catch {
                        [System.Windows.MessageBox]::Show("Erreur de suppression : $($_.Exception.Message)", "Erreur", "OK", "Error")
                    }
                }
            }
        }.GetNewClosure())
}
