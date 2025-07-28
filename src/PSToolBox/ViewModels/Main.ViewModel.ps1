# ViewModel pour la fenêtre principale (MainWindow)

# Créer les propriétés qui seront liées à la vue
$mainViewModel = [PSCustomObject]@{
    # Une collection "intelligente" pour stocker les outils découverts
    Tools = [System.Collections.ObjectModel.ObservableCollection[PSCustomObject]]::new()

    # L'outil actuellement sélectionné dans l'interface
    SelectedTool = $null
}

# Créer la fonction de découverte des outils
function Discover-Tools {
    param($ViewModel)

    Write-Verbose "Début de la découverte des outils..."
    $ViewModel.Tools.Clear() # Vider la liste avant de la remplir

    $toolsRootPath = (Get-Module PSToolBox.Core).ModuleBase | Split-Path | Join-Path -ChildPath "Tools"

    # Chercher tous les fichiers manifestes
    $manifestFiles = Get-ChildItem -Path $toolsRootPath -Filter "*.Tool.psd1" -Recurse

    foreach ($manifestFile in $manifestFiles) {
        try {
            # Lire le contenu du manifeste
            $toolManifest = Invoke-Expression (Get-Content -Path $manifestFile.FullName -Raw)

            # --- C'EST LA NOUVELLE PARTIE ---
            # On stocke le chemin du dossier de l'outil
            $toolDirectory = $manifestFile.Directory.FullName
            $toolManifest | Add-Member -MemberType NoteProperty -Name 'ToolPath' -Value $toolDirectory
            
            # On construit le chemin ABSOLU vers l'icône d'affichage
            $absoluteIconPath = [System.IO.Path]::GetFullPath((Join-Path $toolDirectory $toolManifest.DisplayIcon))
            
            # On ajoute cette nouvelle propriété à notre objet
            $toolManifest | Add-Member -MemberType NoteProperty -Name 'AbsoluteDisplayIconPath' -Value $absoluteIconPath
            # --- FIN DE LA NOUVELLE PARTIE ---


            Write-Verbose "Outil trouvé : $($toolManifest.Name)"
            $ViewModel.Tools.Add($toolManifest)
        }
        catch {
            Write-ToolBoxLog -Message "Erreur lors de la lecture du manifeste '$($manifestFile.FullName)'" -Level ERROR
        }
    }
    Write-Verbose "$($ViewModel.Tools.Count) outil(s) chargé(s)."
}

# Exécuter la découverte au chargement du ViewModel
Discover-Tools -ViewModel $mainViewModel