# Définir les chemins source et destination
$source = "C:\CLOUD\Github\PowerShell_Scripts\Toolbox"
$destination = "C:\CLOUD\OneDrive\OneDrive - VOSGELIS\Bureau\A TRANSFERER"

# Répertoires à exclure (chemins relatifs ou noms de dossiers)
$repExclus = @("Vendor", "ICONS", "PNG", "CONFIG")


# Créer le dossier de destination s'il n'existe pas
if (!(Test-Path $destination)) {
    New-Item -ItemType Directory -Path $destination -Force
}

# Récupérer tous les fichiers de l'arborescence
$fichiers = Get-ChildItem -Path $source -File -Recurse | Where-Object {
    $cheminFichier = $_.FullName
    $exclure = $false
    foreach ($rep in $repExclus) {
        if ($cheminFichier -like "*\$rep\*") {
            $exclure = $true
            break
        }
    }
    -not $exclure
}

# Hashtable pour suivre les noms de fichiers déjà utilisés
$nomsUtilises = @{}

foreach ($fichier in $fichiers) {
    # Nom complet du fichier (avec son extension d'origine)
    $nomComplet = $fichier.Name
    
    # Nom du dossier parent
    $dossierParent = $fichier.Directory.Name
    
    # Nouveau nom : nom_original.ext (dossier).txt
    $nouveauNom = "$nomComplet ($dossierParent).txt"
    
    # Si le nom existe déjà, ajouter un compteur
    $compteur = 1
    while ($nomsUtilises.ContainsKey($nouveauNom.ToLower())) {
        $nouveauNom = "$nomComplet ($dossierParent) ($compteur).txt"
        $compteur++
    }
    
    # Enregistrer le nom comme utilisé
    $nomsUtilises[$nouveauNom.ToLower()] = $true
    
    # Chemin complet de destination
    $cheminDestination = Join-Path $destination $nouveauNom
    
    # Copier le fichier
    Copy-Item -Path $fichier.FullName -Destination $cheminDestination -Force
    
    Write-Host "Copié: $($fichier.Name) -> $nouveauNom"
}

Write-Host "`nTerminé! $($fichiers.Count) fichiers copiés."