function Export-UserDirectoryData {
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
    $saveFileDialog = New-Object Microsoft.Win32.SaveFileDialog
    $saveFileDialog.Filter = "Fichier CSV (*.csv)|*.csv|Fichier HTML (*.html)|*.html"
    $saveFileDialog.FileName = "Export_Utilisateurs_$(Get-Date -Format 'yyyyMMdd')"

    if ($saveFileDialog.ShowDialog() -eq $true) {
        $path = $saveFileDialog.FileName
        $data = $DataGrid.ItemsSource

        try {
            if ($path.EndsWith(".csv")) {
                $data | Export-Csv -Path $path -NoTypeInformation -Encoding UTF8 -Delimiter ";"
            }
            else {
                $htmlBody = $data | ConvertTo-Html -As Table -Fragment
                $html = "<!DOCTYPE html><html><head><meta charset='UTF-8'><style>table{border-collapse:collapse;width:100%;font-family:Segoe UI} th,td{border:1px solid #ddd;padding:8px} th{background-color:#f2f2f2;text-align:left}</style></head><body><h1>Export</h1>$htmlBody</body></html>"
                Set-Content -Path $path -Value $html -Encoding UTF8
            }
            [System.Windows.MessageBox]::Show($OwnerWindow, (Get-AppText 'messages.export_success'), "Succès", "OK", "Information")
        }
        catch {
            $msg = (Get-AppText 'messages.export_error') -f $_.Exception.Message
            [System.Windows.MessageBox]::Show($OwnerWindow, $msg, "Erreur", "OK", "Error")
        }
    }
}
