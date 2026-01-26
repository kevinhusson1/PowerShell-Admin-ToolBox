function Export-UserDirectoryData {
    <#
    .SYNOPSIS
        Exporte les données affichées dans l'annuaire vers un fichier (CSV, HTML, JSON).

    .DESCRIPTION
        Cette fonction récupère les données filtrées du DataGrid, demande à l'utilisateur de choisir
        les colonnes et le format via Show-ExportOptionsDialog, puis génère le fichier.
    
    .PARAMETER DataGrid
        Le contrôle DataGrid contenant les données à exporter.

    .PARAMETER OwnerWindow
        La fenêtre parente pour l'affichage des dialogues.
    #>
    param(
        [Parameter(Mandatory)]
        [object]$DataGrid, # On passe le DataGrid pour exporter ce qu'on voit
        [System.Windows.Window]$OwnerWindow
    )

    if (-not $DataGrid.ItemsSource -or $DataGrid.ItemsSource.Count -eq 0) {
        [System.Windows.MessageBox]::Show($OwnerWindow, (Get-AppText 'messages.no_data_export'), "Export", "OK", "Information")
        return
    }

    # On utilise la boîte de dialogue standard de Windows pour le chemin
    # 1. Identification des colonnes disponibles
    # On prend le premier objet pour lister les propriétés (simple et efficace)
    if ($DataGrid.ItemsSource[0] -is [PSCustomObject]) {
        $sample = $DataGrid.ItemsSource[0]
        $availableFields = $sample.PSObject.Properties.Name
    }
    else {
        # Fallback (au cas où ce ne sont pas des PSCustomObject)
        return
    }

    # Champs par défaut (ceux affichés dans la grille idéalement)
    $defaultFields = @("DisplayName", "Mail", "JobTitle", "Department", "PrimaryBusinessPhone", "MobilePhone")

    # 2. Appel du dialogue d'options
    $exportConfig = Show-ExportOptionsDialog -AllAvailableFields $availableFields -DefaultSelectedFields $defaultFields -OwnerWindow $OwnerWindow

    if ($null -ne $exportConfig) {
        $path = $exportConfig.FilePath
        $selectedFields = $exportConfig.SelectedFields
        $format = $exportConfig.Format
        
        # Filtrage des données
        $dataToExport = $DataGrid.ItemsSource | Select-Object $selectedFields

        try {
            if ($format -eq "CSV") {
                $dataToExport | Export-Csv -Path $path -NoTypeInformation -Encoding UTF8BOM -Delimiter ";"
            }
            elseif ($format -eq "HTML") {
                $htmlBody = $dataToExport | ConvertTo-Html -As Table -Fragment
                $dateGen = Get-Date -Format "dd/MM/yyyy HH:mm"
                # Style CSS minimaliste et propre
                $css = "body{font-family:'Segoe UI',sans-serif;margin:20px;color:#333} h1{color:#2563EB} table{border-collapse:collapse;width:100%;font-size:14px} th,td{border:1px solid #e2e8f0;padding:8px 12px;text-align:left} th{background-color:#f8fafc;font-weight:600} tr:nth-child(even){background-color:#fcfcfc}"
                $html = "<!DOCTYPE html><html><head><meta charset='utf-8'><title>Export Annuaire</title><style>$css</style></head><body><h1>Export Annuaire</h1><p>Généré le $dateGen</p>$htmlBody</body></html>"
                Set-Content -Path $path -Value $html -Encoding UTF8BOM
            }
            elseif ($format -eq "JSON") {
                $dataToExport | ConvertTo-Json -Depth 2 | Set-Content -Path $path -Encoding UTF8BOM
            }
            
            # Notification Succès (avec option d'ouverture)
            $res = [System.Windows.MessageBox]::Show($OwnerWindow, (Get-AppText 'messages.export_success_open'), "Succès", "YesNo", "Information")
            if ($res -eq 'Yes') {
                Start-Process $path
            }
        }
        catch {
            $msg = (Get-AppText 'messages.export_error') -f $_.Exception.Message
            [System.Windows.MessageBox]::Show($OwnerWindow, $msg, "Erreur", "OK", "Error")
        }
    }
}
