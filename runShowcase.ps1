# _runShowcase.ps1
# Version 7 - Finalisée, sans C# et avec corrections

# --- Initialisation de l'environnement ---
$ProjectRoot = $PSScriptRoot
$StylesPath = Join-Path $ProjectRoot "src/PSToolBox/Assets/Styles/Global.xaml"
$ShowcaseViewPath = Join-Path $ProjectRoot "src/Modules/Tools/ComponentShowcase/Views/ComponentShowcase.View.xaml"

Add-Type -AssemblyName PresentationFramework

# --- Création des données de test ---
$SampleDataGridData = [System.Collections.ObjectModel.ObservableCollection[object]]::new(@([PSCustomObject]@{ IsSelected = $false; Name = "Alice"; Email = "alice@example.com"; Status = "Actif" },[PSCustomObject]@{ IsSelected = $true; Name = "Bob"; Email = "bob@example.com"; Status = "Inactif" },[PSCustomObject]@{ IsSelected = $false; Name = "Charlie"; Email = "charlie@example.com"; Status = "Actif" },[PSCustomObject]@{ IsSelected = $false; Name = "Diana"; Email = "diana.long.email.address@example.com"; Status = "En attente" }))

# --- Logique de lancement de la fenêtre ---
try {
    # On supprime complètement le bloc Add-Type C#
    
    [xml]$stylesXml = Get-Content -Path $StylesPath -Raw
    $stylesReader = New-Object System.Xml.XmlNodeReader $stylesXml
    $GlobalStyles = [System.Windows.Markup.XamlReader]::Load($stylesReader)

    [xml]$showcaseXml = Get-Content -Path $ShowcaseViewPath -Raw
    $showcaseReader = New-Object System.Xml.XmlNodeReader $showcaseXml
    $ShowcaseWindow = [System.Windows.Markup.XamlReader]::Load($showcaseReader)

    $ShowcaseWindow.Resources.MergedDictionaries.Add($GlobalStyles)

    # --- Peupler les contrôles ---
    $DataGrid = $ShowcaseWindow.FindName("ShowcaseDataGrid")
    if ($DataGrid) { $DataGrid.ItemsSource = $SampleDataGridData }

    $TreeView = $ShowcaseWindow.FindName("ShowcaseTreeView")
    if ($TreeView) {
        $root = New-Object System.Windows.Controls.TreeViewItem -Property @{ Header = "Racine" }
        $child1 = New-Object System.Windows.Controls.TreeViewItem -Property @{ Header = "Fichier A" }
        $child2 = New-Object System.Windows.Controls.TreeViewItem -Property @{ Header = "Dossier 1"; IsExpanded = $true }
        $grandchild1 = New-Object System.Windows.Controls.TreeViewItem -Property @{ Header = "Sous-Fichier B" }
        $child2.Items.Add($grandchild1)
        $root.Items.Add($child1)
        $root.Items.Add($child2)
        $TreeView.Items.Add($root)
    }

    $LogBox = $ShowcaseWindow.FindName("ShowcaseLogBox")
    if ($LogBox) {
        $paragraph = New-Object System.Windows.Documents.Paragraph
        $paragraph.Inlines.Add("Ceci est un message d'information.")
        $LogBox.Document.Blocks.Add($paragraph)
    }

    $ProgressBar = $ShowcaseWindow.FindName("ShowcaseProgressBar")
    if ($ProgressBar) { $ProgressBar.Value = 60 }

    Write-Host "Affichage de la vitrine des composants..." -ForegroundColor Green
    $ShowcaseWindow.ShowDialog() | Out-Null

} catch {
    Write-Error "Une erreur est survenue : $($_.Exception.Message)"
    $currentException = $_.Exception
    while ($currentException.InnerException) {
        # CORRECTION : .InnerException et non .Inner-Exception
        $currentException = $currentException.InnerException
        Write-Error "  -> InnerException: $($currentException.Message)"
    }
    [System.Windows.MessageBox]::Show($_.Exception.Message, "Erreur", "OK", "Error")
}