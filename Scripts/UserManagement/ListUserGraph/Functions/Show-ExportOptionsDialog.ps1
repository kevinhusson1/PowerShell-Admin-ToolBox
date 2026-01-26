function Show-ExportOptionsDialog {
    <#
    .SYNOPSIS
        Affiche une boîte de dialogue modale pour configurer l'exportation des données.

    .DESCRIPTION
        Cette fonction génère dynamiquement une fenêtre XAML permettant de sélectionner
        les colonnes à exporter et le format de fichier (CSV, HTML, JSON).

    .PARAMETER AllAvailableFields
        Liste des noms de champs disponibles pour l'export.

    .PARAMETER DefaultSelectedFields
        Liste des noms de champs à cocher par défaut.

    .PARAMETER OwnerWindow
        La fenêtre parente pour centrer le dialogue.

    .OUTPUTS
        Hashtable ou $null. Contient { SelectedFields, Format, FilePath }.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$AllAvailableFields,

        [Parameter(Mandatory = $true)]
        [string[]]$DefaultSelectedFields,

        [System.Windows.Window]$OwnerWindow
    )

    # Note: On utilise les ressources globales de l'application (Styles)
    # L'OwnerWindow nous assure que ce dialogue restera au dessus.

    # Textes Localisés
    $txtTitle = Get-AppText 'export_dialog.title'
    $txtHeaderTitle = Get-AppText 'export_dialog.header_title'
    $txtHeaderDesc = Get-AppText 'export_dialog.header_desc'
    $txtFormatLabel = Get-AppText 'export_dialog.format_label'
    $txtFormatCsv = Get-AppText 'export_dialog.format_csv'
    $txtFormatHtml = Get-AppText 'export_dialog.format_html'
    $txtFormatJson = Get-AppText 'export_dialog.format_json'
    $txtBtnCancel = Get-AppText 'export_dialog.btn_cancel'
    $txtBtnExport = Get-AppText 'export_dialog.btn_export'

    [xml]$xamlExportOptions = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$txtTitle" Height="500" Width="450"
        WindowStartupLocation="CenterOwner" ResizeMode="NoResize" ShowInTaskbar="False"
        Background="{DynamicResource WhiteBrush}" TextOptions.TextFormattingMode="Display" UseLayoutRounding="True">
    
    <Grid Margin="20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <!-- Header -->
            <RowDefinition Height="*"/>   
            <!-- Champs -->
            <RowDefinition Height="Auto"/>
            <!-- Format Header -->
            <RowDefinition Height="Auto"/>
            <!-- Format Choice -->
            <RowDefinition Height="Auto"/> 
            <!-- Buttons -->
        </Grid.RowDefinitions>

        <!-- HEADER -->
        <StackPanel Grid.Row="0" Margin="0,0,0,15">
            <TextBlock Text="$txtHeaderTitle" FontSize="18" FontWeight="SemiBold" Foreground="{DynamicResource TextPrimaryBrush}"/>
            <TextBlock Text="$txtHeaderDesc" FontSize="14" Foreground="{DynamicResource TextSecondaryBrush}" Margin="0,5,0,0"/>
        </StackPanel>

        <!-- CHAMPS -->
        <Border Grid.Row="1" Background="{DynamicResource BackgroundLightBrush}" CornerRadius="4" BorderBrush="{DynamicResource BorderLightBrush}" BorderThickness="1" Padding="10" Margin="0,0,0,20">
            <ScrollViewer VerticalScrollBarVisibility="Auto">
                <ItemsControl x:Name="FieldsItemsControl">
                    <ItemsControl.ItemTemplate>
                        <DataTemplate>
                            <CheckBox Content="{Binding Name}" IsChecked="{Binding IsSelected, Mode=TwoWay}" Margin="2,4"
                                      Style="{DynamicResource StandardCheckBoxStyle}" Foreground="{DynamicResource TextPrimaryBrush}"/>
                        </DataTemplate>
                    </ItemsControl.ItemTemplate>
                </ItemsControl>
            </ScrollViewer>
        </Border>

        <!-- FORMAT -->
        <TextBlock Grid.Row="2" Text="$txtFormatLabel" FontSize="14" FontWeight="SemiBold" Foreground="{DynamicResource TextPrimaryBrush}" Margin="0,0,0,10"/>
        
        <StackPanel Grid.Row="3" Orientation="Horizontal" Margin="0,0,0,30">
            <RadioButton x:Name="FormatCsvRadio" Content="$txtFormatCsv" GroupName="ExportFormat" IsChecked="True" 
                         Style="{DynamicResource StandardRadioButtonStyle}" Margin="0,0,20,0"/>
                         
            <RadioButton x:Name="FormatHtmlRadio" Content="$txtFormatHtml" GroupName="ExportFormat" 
                         Style="{DynamicResource StandardRadioButtonStyle}" Margin="0,0,20,0"/>

             <!-- Placeholder pour Excel natif plus tard -->
             <RadioButton x:Name="FormatJsonRadio" Content="$txtFormatJson" GroupName="ExportFormat" 
                         Style="{DynamicResource StandardRadioButtonStyle}"/>
        </StackPanel>

        <!-- BOUTONS -->
        <Grid Grid.Row="4">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            
            <Button x:Name="ButtonCancelExport" Grid.Column="0" Content="$txtBtnCancel" IsCancel="True" Style="{DynamicResource SecondaryButtonStyle}" Margin="0,0,5,0" Height="36"/>
            <Button x:Name="ButtonConfirmExport" Grid.Column="1" Content="$txtBtnExport" IsDefault="True" Style="{DynamicResource PrimaryButtonStyle}" Margin="5,0,0,0" Height="36"/>
        </Grid>
    </Grid>
</Window>
"@ 

    $readerExport = New-Object System.Xml.XmlNodeReader $xamlExportOptions
    $exportOptionsWindow = $null
    try {
        $exportOptionsWindow = [Windows.Markup.XamlReader]::Load($readerExport)
    }
    catch {
        Write-Error "ERREUR XAML (Show-ExportOptionsDialog): $($_.Exception.Message)"
        [System.Windows.MessageBox]::Show("Erreur critique XAML Export.`n$($_.Exception.Message)", "Erreur", "OK", "Error")
        return $null
    }

    # Fusion des ressources globales si disponibles (Styles V3)
    if ($OwnerWindow) {
        $exportOptionsWindow.Owner = $OwnerWindow
        foreach ($dic in $OwnerWindow.Resources.MergedDictionaries) {
            $exportOptionsWindow.Resources.MergedDictionaries.Add($dic)
        }
    }

    # Mapping
    $fieldsItemsControl = $exportOptionsWindow.FindName("FieldsItemsControl")
    $formatCsvRadio = $exportOptionsWindow.FindName("FormatCsvRadio")
    $formatHtmlRadio = $exportOptionsWindow.FindName("FormatHtmlRadio")
    $buttonConfirmExport = $exportOptionsWindow.FindName("ButtonConfirmExport")
    $buttonCancel = $exportOptionsWindow.FindName("ButtonCancelExport")

    # Préparation Données (ViewModel)
    $fieldSelectionObjects = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    
    $AllAvailableFields | Sort-Object | ForEach-Object {
        $fieldName = $_
        $selected = ($DefaultSelectedFields -contains $fieldName)
        
        $fieldSelectionObjects.Add([PSCustomObject]@{
                Name       = $fieldName
                IsSelected = $selected
            })
    }
    
    # Tri: Sélectionnés en premier, puis alphabétique
    $sortedView = $fieldSelectionObjects | Sort-Object IsSelected, Name -Descending
    $fieldsItemsControl.ItemsSource = $sortedView

    # Output variable script scope pour récupérer le résultat de l'event
    $script:ShowExportDialog_ResultData = $null 

    $buttonConfirmExport.Add_Click({
            $selectedFieldsForExport = $fieldsItemsControl.ItemsSource | Where-Object { $_.IsSelected } | Select-Object -ExpandProperty Name
        
            if ($selectedFieldsForExport.Count -eq 0) {
                [System.Windows.MessageBox]::Show($exportOptionsWindow, (Get-AppText 'export_dialog.error_no_selection'), (Get-AppText 'export_dialog.header_selection_error'), "OK", "Warning")
                return 
            }
        
            $chosenFormat = if ($formatCsvRadio.IsChecked) { "CSV" } elseif ($formatHtmlRadio.IsChecked) { "HTML" } else { "JSON" }
        
            # Save File Dialog
            $saveFileDialog = New-Object Microsoft.Win32.SaveFileDialog
            $saveFileDialog.InitialDirectory = [Environment]::GetFolderPath("MyDocuments")
            $timestamp = Get-Date -Format 'yyyyMMdd_HHmm'
        
            switch ($chosenFormat) {
                "CSV" { $saveFileDialog.Filter = "Fichiers CSV (*.csv)|*.csv"; $saveFileDialog.DefaultExt = ".csv"; $saveFileDialog.FileName = "Export_Annuaire_$timestamp.csv" }
                "HTML" { $saveFileDialog.Filter = "Fichiers HTML (*.html)|*.html"; $saveFileDialog.DefaultExt = ".html"; $saveFileDialog.FileName = "Rapport_Annuaire_$timestamp.html" }
                "JSON" { $saveFileDialog.Filter = "Fichiers JSON (*.json)|*.json"; $saveFileDialog.DefaultExt = ".json"; $saveFileDialog.FileName = "Export_Annuaire_$timestamp.json" }
            }

            if ($saveFileDialog.ShowDialog() -eq $true) { 
                $script:ShowExportDialog_ResultData = @{
                    SelectedFields = $selectedFieldsForExport
                    Format         = $chosenFormat
                    FilePath       = $saveFileDialog.FileName 
                }
                $exportOptionsWindow.DialogResult = $true
                $exportOptionsWindow.Close()
            }
        })
    
    $buttonCancel.Add_Click({
            $exportOptionsWindow.DialogResult = $false
            $exportOptionsWindow.Close()
        })

    $dialogResultShow = $exportOptionsWindow.ShowDialog()

    if ($dialogResultShow -eq $true -and $script:ShowExportDialog_ResultData) {
        return $script:ShowExportDialog_ResultData
    } 
    return $null
}
