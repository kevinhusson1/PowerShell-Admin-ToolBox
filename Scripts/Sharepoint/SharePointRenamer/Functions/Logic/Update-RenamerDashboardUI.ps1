<#
.SYNOPSIS
    Met à jour l'interface du Dashboard après l'analyse d'un projet.
#>
function Global:Update-RenamerDashboardUI {
    param(
        [hashtable]$Ctrl,
        [System.Windows.Window]$Window,
        [PSCustomObject]$AnalysisResult,
        [scriptblock]$LogMethod
    )
    
    # Masquer le chargement
    if ($Ctrl.LoadingPanel) { $Ctrl.LoadingPanel.Visibility = "Collapsed" }
    if ($Ctrl.BtnAnalyze) { $Ctrl.BtnAnalyze.IsEnabled = $true }

    # Erreur globale
    if ($AnalysisResult.Error) {
        if ($Ctrl.ErrorPanel) { $Ctrl.ErrorPanel.Visibility = "Visible" }
        if ($Ctrl.ErrorText) { $Ctrl.ErrorText.Text = $AnalysisResult.Error }
        if ($LogMethod) { & $LogMethod "Echec: $($AnalysisResult.Error)" "Error" }
        return
    }

    # Afficher le Dashboard
    if ($Ctrl.DashboardPanel) { $Ctrl.DashboardPanel.Visibility = "Visible" }

    # Titre du Projet
    $title = "Dossier Inconnu"
    if ($AnalysisResult.FolderName) { $title = $AnalysisResult.FolderName }
    elseif ($AnalysisResult.FolderItem) {
        if ($AnalysisResult.FolderItem.Title) { $title = $AnalysisResult.FolderItem.Title }
        elseif ($AnalysisResult.FolderItem.FileLeafRef) { $title = $AnalysisResult.FolderItem.FileLeafRef }
    }
    
    if ($Ctrl.ProjectTitle) { $Ctrl.ProjectTitle.Text = $title }
    
    $ctx = Get-RenamerContext
    if ($Ctrl.ProjectUrl) { $Ctrl.ProjectUrl.Text = $ctx.FolderUrl }

    # Logique Tracking
    if (-not $AnalysisResult.IsTracked) {
        if ($Ctrl.TextStatus) {
            $Ctrl.TextStatus.Text = "NON GÉRÉ"
            $Ctrl.TextStatus.Foreground = [System.Windows.Media.Brushes]::Gray
        }
        if ($Ctrl.TextConfig) { $Ctrl.TextConfig.Text = "Aucune configuration" }
        if ($Ctrl.MetaGrid) { $Ctrl.MetaGrid.Children.Clear() }
        if ($Ctrl.StructureGrid) { $Ctrl.StructureGrid.Children.Clear() }
        return
    }

    # Tracking actif
    $jsonSafe = $null
    if ($AnalysisResult.HistoryItem.FormValuesJson) {
        $jsonSafe = $AnalysisResult.HistoryItem.FormValuesJson | ConvertFrom-Json
    }

    # Drift du Titre
    if ($jsonSafe -and $jsonSafe.PreviewText) {
        $expectedName = $jsonSafe.PreviewText
        if ($expectedName -ne $title) {
            if ($Ctrl.ProjectTitle) {
                $Ctrl.ProjectTitle.Text = "$title"
                $Ctrl.ProjectTitle.Foreground = [System.Windows.Media.Brushes]::OrangeRed
            }
            if ($Ctrl.ProjectUrl) {
                $Ctrl.ProjectUrl.Text = "⚠️ Nom attendu : $expectedName`n$($ctx.FolderUrl)"
                $Ctrl.ProjectUrl.Foreground = [System.Windows.Media.Brushes]::Red
            }
        }
    }

    # Version et Date
    $ver = if ($AnalysisResult.HistoryItem) { $AnalysisResult.HistoryItem.TemplateVersion } else { "?" }
    if ($Ctrl.TextStatus) {
        $Ctrl.TextStatus.Text = "SUIVI (v$ver)"
        $Ctrl.TextStatus.Foreground = [System.Windows.Media.Brushes]::Green
    }
    if ($Ctrl.TextConfig) { $Ctrl.TextConfig.Text = "Config: $($AnalysisResult.HistoryItem.ConfigName)" }
    if ($Ctrl.TextDate) { $Ctrl.TextDate.Text = "Déployé le: $($AnalysisResult.HistoryItem.DeployedDate)" }

    # KPI & Grilles
    if ($AnalysisResult.Drift) {
        Set-RenamerDriftKPI -Ctrl $Ctrl -Drift $AnalysisResult.Drift
        Set-RenamerMetadataGrid -Ctrl $Ctrl -Drift $AnalysisResult.Drift -JsonSafe $jsonSafe
        Set-RenamerStructureGrid -Ctrl $Ctrl -Drift $AnalysisResult.Drift -LogMethod $LogMethod
    }
}

function Global:Set-RenamerDriftKPI {
    param([hashtable]$Ctrl, [PSCustomObject]$Drift)
    
    # Structure
    if ($Drift.StructureStatus -eq "OK") {
        $Ctrl.KpiStructure.Text = "Conforme"
        $Ctrl.KpiStructure.Foreground = [System.Windows.Media.Brushes]::Green
    }
    else {
        $count = if ($Drift.StructureMisses) { $Drift.StructureMisses.Count } else { 0 }
        $Ctrl.KpiStructure.Text = "Non-conforme ($count)"
        $Ctrl.KpiStructure.Foreground = [System.Windows.Media.Brushes]::Red
    }

    # Metadata
    if ($Drift.MetaStatus -eq "OK") {
        $Ctrl.KpiMeta.Text = "Sync"
        $Ctrl.KpiMeta.Foreground = [System.Windows.Media.Brushes]::Green
    } 
    elseif ($Drift.MetaStatus -eq "DRIFT") {
        $count = if ($Drift.MetaDrifts) { $Drift.MetaDrifts.Count } else { 0 }
        $Ctrl.KpiMeta.Text = "Divergence ($count)"
        $Ctrl.KpiMeta.Foreground = [System.Windows.Media.Brushes]::OrangeRed
    }
    else {
        $Ctrl.KpiMeta.Text = $Drift.MetaStatus
        $Ctrl.KpiMeta.Foreground = [System.Windows.Media.Brushes]::Gray
    }
}

function Global:Set-RenamerMetadataGrid {
    param([hashtable]$Ctrl, [PSCustomObject]$Drift, [PSCustomObject]$JsonSafe)
    
    if (-not $Ctrl.MetaGrid) { return }
    $Ctrl.MetaGrid.Children.Clear()
    if (-not $JsonSafe) { return }

    $formattedDrift = Format-RenamerMetadataDrift -MetaDrifts $Drift.MetaDrifts
    $row = 0

    # Fonction locale pour injecter une ligne
    function Append-GridRow {
        param($keyName, $baseVal)
        $Ctrl.MetaGrid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{Height = "Auto" }))
        
        $lbl = New-Object System.Windows.Controls.TextBlock
        $lbl.Text = "${keyName}:"
        $lbl.FontWeight = "SemiBold"
        $lbl.Foreground = [System.Windows.Media.Brushes]::Gray
        $lbl.Margin = "0,0,10,5"
        [System.Windows.Controls.Grid]::SetRow($lbl, $row)
        [System.Windows.Controls.Grid]::SetColumn($lbl, 0)
        
        $val = New-Object System.Windows.Controls.TextBlock
        $val.TextWrapping = "Wrap"
        [System.Windows.Controls.Grid]::SetRow($val, $row)
        [System.Windows.Controls.Grid]::SetColumn($val, 1)

        if ($formattedDrift.ContainsKey($keyName)) {
            $dInfo = $formattedDrift[$keyName]
            
            $runFound = New-Object System.Windows.Documents.Run
            $runFound.Text = $dInfo.Found + " "
            $runFound.Foreground = [System.Windows.Media.Brushes]::OrangeRed
            $runFound.FontWeight = "Bold"
            
            $runExp = New-Object System.Windows.Documents.Run
            $runExp.Text = "(Attendu: $($dInfo.Expected))"
            $runExp.Foreground = [System.Windows.Media.Brushes]::Gray
            $runExp.FontSize = 10
            $runExp.FontStyle = "Italic"
            
            $val.Inlines.Add($runFound)
            $val.Inlines.Add($runExp)
            
            $lbl.Foreground = [System.Windows.Media.Brushes]::OrangeRed
        }
        else {
            $val.Text = $baseVal
        }

        $Ctrl.MetaGrid.Children.Add($lbl)
        $Ctrl.MetaGrid.Children.Add($val)
        Set-Variable -Name row -Value ($row + 1) -Scope 1
    }

    # Injection forcée du "Nom du Dossier" si en divergence (virtuel)
    if ($formattedDrift.ContainsKey("Nom du Dossier")) {
        Append-GridRow -keyName "Nom du Dossier" -baseVal ""
    }

    foreach ($prop in $JsonSafe.PSObject.Properties) {
        Append-GridRow -keyName $prop.Name -baseVal $prop.Value
    }
}

function Global:Set-RenamerStructureGrid {
    param([hashtable]$Ctrl, [PSCustomObject]$Drift, [scriptblock]$LogMethod)
    
    if (-not $Ctrl.StructureGrid) { return }
    $Ctrl.StructureGrid.Children.Clear()

    if ($Drift.StructureStatus -eq "OK") {
        $okTxt = New-Object System.Windows.Controls.TextBlock
        $okTxt.Text = "✅ Structure Complète"
        $okTxt.Foreground = [System.Windows.Media.Brushes]::Green
        $Ctrl.StructureGrid.Children.Add($okTxt)
        return
    }

    $formattedMisses = Format-RenamerStructureDrift -StructureMisses $Drift.StructureMisses

    if ($formattedMisses.Count -gt 0) {
        if ($LogMethod) { & $LogMethod "Populating StructureGrid with $($formattedMisses.Count) missing items." "Debug" }
        $head = New-Object System.Windows.Controls.TextBlock
        $head.Text = "Eléments manquants ou incorrects :"
        $head.FontWeight = "Bold"
        $head.Foreground = [System.Windows.Media.Brushes]::Red
        $head.Margin = "0,0,0,5"
        $Ctrl.StructureGrid.Children.Add($head)

        foreach ($miss in $formattedMisses) {
            $errTxt = New-Object System.Windows.Controls.TextBlock
            $errTxt.Text = $miss.Raw
            $errTxt.Foreground = [System.Windows.Media.Brushes]::Red
            $errTxt.TextWrapping = "Wrap"
            $errTxt.Margin = "0,2,0,5"
            $Ctrl.StructureGrid.Children.Add($errTxt)
        }
    }
}
