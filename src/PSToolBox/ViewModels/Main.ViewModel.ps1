# ViewModel pour la fenêtre principale (MainWindow)

# Créer la fonction de découverte des outils (inchangée)
function Discover-Tools {
    param($ViewModel)
    Write-Verbose "Début de la découverte des outils..."
    $ViewModel.Tools.Clear()
    $toolsRootPath = (Get-Module PSToolBox.Core).ModuleBase | Split-Path | Join-Path -ChildPath "Tools"
    $manifestFiles = Get-ChildItem -Path $toolsRootPath -Filter "*.Tool.psd1" -Recurse
    foreach ($manifestFile in $manifestFiles) {
        try {
            $toolManifest = Invoke-Expression (Get-Content -Path $manifestFile.FullName -Raw)
            $toolDirectory = $manifestFile.Directory.FullName
            $toolManifest | Add-Member -MemberType NoteProperty -Name 'ToolPath' -Value $toolDirectory
            $absoluteIconPath = [System.IO.Path]::GetFullPath((Join-Path $toolDirectory $toolManifest.DisplayIcon))
            $toolManifest | Add-Member -MemberType NoteProperty -Name 'AbsoluteDisplayIconPath' -Value $absoluteIconPath
            Write-Verbose "Outil trouvé : $($toolManifest.Name)"
            $ViewModel.Tools.Add($toolManifest)
        }
        catch {
            Write-ToolBoxLog -Message "Erreur lors de la lecture du manifeste '$($manifestFile.FullName)'" -Level ERROR
        }
    }
    Write-Verbose "$($ViewModel.Tools.Count) outil(s) chargé(s)."
}

# =========================================================================
# NOUVELLE PARTIE : Logique de Lancement
# =========================================================================

# Ceci est la fonction qui sera exécutée par le bouton "Lancer l'outil"
$LaunchToolAction = {
    param($ViewModel) # On passe le ViewModel en paramètre pour qu'il ait accès à ses propres propriétés

    if ($null -eq $ViewModel.SelectedTool) {
        Write-ToolBoxLog -Message "Tentative de lancement sans outil sélectionné." -Level WARNING
        return
    }

    $selectedTool = $ViewModel.SelectedTool
    Write-ToolBoxLog -Message "Lancement de l'outil '$($selectedTool.Name)'..."

    # Étape 1 : Construire les chemins pour la vue et l'icône de l'outil
    $toolViewPath = Join-Path $selectedTool.ToolPath $selectedTool.RootView
    $toolIconPath = Join-Path $selectedTool.ToolPath $selectedTool.WindowIcon
    
    # Étape 2 : Préparer un ViewModel pour l'outil
    # Pour l'instant, c'est un ViewModel vide. Plus tard, chaque outil aura son propre script ViewModel.
    $toolViewModel = [PSCustomObject]@{
        WindowTitle = $selectedTool.Name # On passe le nom de l'outil comme titre de la fenêtre
    }
    
    # Étape 3 : Lancer la fenêtre de l'outil via notre service Core
    Show-ToolBoxWindow -ViewPath $toolViewPath -ViewModel $toolViewModel -WindowIconPath $toolIconPath
    # Note : On n'utilise pas -IsDialog pour que le lanceur principal ne soit pas bloqué.
}

# =========================================================================
# Création de l'objet ViewModel final
# =========================================================================

$mainViewModel = [PSCustomObject]@{
    Tools = [System.Collections.ObjectModel.ObservableCollection[PSCustomObject]]::new()
    SelectedTool = $null
    
    # NOUVEAU : On attache la fonction de lancement au ViewModel
    LaunchToolCommand = $LaunchToolAction
    
    # NOUVEAU : Une propriété booléenne pour activer/désactiver le bouton
    # Note : ceci est une simple propriété. Pour une réactivité parfaite, il faudrait un objet
    # qui implémente INotifyPropertyChanged, mais c'est une complexité pour plus tard.
    IsToolSelected = $false
}

# Exécuter la découverte au chargement du ViewModel
Discover-Tools -ViewModel $mainViewModel