<#
.SYNOPSIS
    Met à jour les dépendances externes (Vendor) du projet.
.DESCRIPTION
    Ce script vérifie la présence de nouvelles versions pour les modules embarqués dans le dossier 'Vendor'.
    Actuellement gère : PSSQLite.
    
    ATTENTION : Ce script doit être exécuté "à froid", c'est-à-dire sans que le Launcher ou d'autres scripts
    utilisant les modules ne soient en cours d'exécution, afin d'éviter les verrous de fichiers (DLL).
.EXAMPLE
    .\Update-VendorDependencies.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$projectRoot = "$PSScriptRoot\..\.."
$vendorPath = Join-Path $projectRoot "Vendor"

Write-Host "=== Script Tools Box - Mise à jour des dépendances ===" -ForegroundColor Cyan
Write-Host "Racine du projet : $projectRoot" -ForegroundColor Gray

# --- PSSQLite ---
$moduleName = "PSSQLite"
$localModulePath = Join-Path $vendorPath $moduleName
$psd1Path = Join-Path $localModulePath "$moduleName.psd1"

Write-Host "`nVérification de $moduleName..." -ForegroundColor Yellow

if (Test-Path $psd1Path) {
    $localManifest = Import-PowerShellDataFile -Path $psd1Path
    $currentVersion = [version]$localManifest.ModuleVersion
    Write-Host "  Version locale : $currentVersion" -ForegroundColor Gray
}
else {
    $currentVersion = [version]"0.0.0"
    Write-Host "  Version locale : Non installé" -ForegroundColor DarkGray
    # Si le dossier n'existe pas, on le crée
    if (-not (Test-Path $localModulePath)) { New-Item -ItemType Directory -Path $localModulePath | Out-Null }
}

try {
    Write-Host "  Recherche sur PSGallery..." -NoNewline
    $onlineModule = Find-Module -Name $moduleName -Repository PSGallery -ErrorAction Stop
    Write-Host " OK ($($onlineModule.Version))" -ForegroundColor Green

    if ($onlineModule.Version -gt $currentVersion) {
        Write-Host "  >> Une mise à jour est disponible !" -ForegroundColor Green
        
        $confirm = Read-Host "  Voulez-vous mettre à jour maintenant ? (O/N)"
        if ($confirm -eq 'O') {
            Write-Host "  Téléchargement de la mise à jour..."
            
            $tempDir = Join-Path $env:TEMP "STB_VendorUpdate_$([guid]::NewGuid())"
            New-Item -ItemType Directory -Path $tempDir | Out-Null
            
            try {
                # Téléchargement
                Save-Module -Name $moduleName -Path $tempDir -Force
                
                # Le module est téléchargé dans $tempDir/PSSQLite/<version> OU $tempDir/PSSQLite directement selon la version de PSGet
                # Généralement Save-Module crée : $tempDir\PSSQLite\
                $downloadedModulePath = Join-Path $tempDir $moduleName
                
                if (Test-Path $downloadedModulePath) {
                    # Copie vers Vendor
                    Write-Host "  Installation dans $localModulePath..."
                    
                    # On supprime l'ancien contenu pour être propre (sauf si verrouillé)
                    # Get-ChildItem -Path $localModulePath -Recurse | Remove-Item -Force -Recurse
                    # Note : Copy-Item -Force écrase, c'est souvent suffisant et moins risqué si partiel
                    
                    Copy-Item -Path "$downloadedModulePath\*" -Destination $localModulePath -Recurse -Force
                    
                    Write-Host "  ✅ Mise à jour terminée avec succès ($($onlineModule.Version))." -ForegroundColor Green
                }
                else {
                    throw "Le dossier téléchargé est introuvable."
                }
            }
            finally {
                # Nettoyage
                if (Test-Path $tempDir) { Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
            }
        }
    }
    else {
        Write-Host "  Le module est déjà à jour." -ForegroundColor Green
    }
}
catch {
    Write-Warning "  Erreur lors de la vérification/mise à jour : $($_.Exception.Message)"
}

Write-Host "`nTerminé." -ForegroundColor Cyan
