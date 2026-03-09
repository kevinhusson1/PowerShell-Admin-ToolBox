#Requires -Version 7.0

<#
.SYNOPSIS
    TEST 06 : Résolution et création des Liens (Internes et Externes)
.DESCRIPTION
    Valide la création de raccourcis SharePoint sous forme de fichiers .url.
    Vérifie la capacité à rechercher le lien web (webUrl) d'un dossier
    récemment créé pour générer un InternalLink dynamique.
#>

$testRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $testRoot "..\Shared\Init-TestEnvironment.ps1")

Write-Host "--- EXECUTION DU TEST 06 : GESTION DES LIENS ---" -ForegroundColor Yellow

$siteUrl = $Global:TestTargetSiteUrl
$libName = $Global:TestTargetLibrary

try {
    Write-Host "Etape 0 : Préparation..." -ForegroundColor DarkGray
    $siteId = Get-AppGraphSiteId -SiteUrl $siteUrl
    $listAndDrive = Get-AppGraphListDriveId -SiteId $siteId -ListDisplayName $libName
    $driveId = $listAndDrive.DriveId

    $parentFolderName = "TEST06_Racine_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    $cibleFolderName = "CibleLienInterne"
    
    # --- ETAPE 1 : ARBORESCENCE ---
    Write-Host "Etape 1 : Création de la racine et du dossier cible..." -ForegroundColor DarkGray
    $parentRes = New-AppGraphFolder -SiteId $siteId -DriveId $driveId -FolderName $parentFolderName -ParentFolderId "root"
    if (-not $parentRes) { throw "Impossible de créer la racine." }
    
    $cibleRes = New-AppGraphFolder -SiteId $siteId -DriveId $driveId -FolderName $cibleFolderName -ParentFolderId $parentRes.id
    if (-not $cibleRes) { throw "Impossible de créer la cible interne." }
    
    # Graph API renvoie directement webUrl dans la réponse de création !
    $cibleWebUrl = $cibleRes.webUrl
    Write-Host "  > Dossier Cible créé. WebUrl récupérée : $cibleWebUrl" -ForegroundColor Cyan

    # --- ETAPE 2 : LIEN EXTERNE ---
    Write-Host "Etape 2 : Création d'un lien externe (.url)..." -ForegroundColor DarkGray
    $extLinkName = "Google.url"
    $extLinkContent = "[InternetShortcut]`nURL=https://www.google.fr"
    $bytesExt = [System.Text.Encoding]::UTF8.GetBytes($extLinkContent)
    $uriExt = "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$driveId/items/$($parentRes.id)`:/$extLinkName`:/content"
    
    $resExt = Invoke-MgGraphRequest -Method PUT -Uri $uriExt -Body $bytesExt -ContentType "text/plain"
    if (-not $resExt -or -not $resExt.id) { throw "Echec de l'upload du lien externe." }
    Write-Host "  > Lien Externe créé ($extLinkName)." -ForegroundColor Green

    # --- ETAPE 3 : LIEN INTERNE ---
    Write-Host "Etape 3 : Création d'un lien interne (.url)..." -ForegroundColor DarkGray
    $intLinkName = "Accès_Cible.url"
    $intLinkContent = "[InternetShortcut]`nURL=$cibleWebUrl"
    $bytesInt = [System.Text.Encoding]::UTF8.GetBytes($intLinkContent)
    $uriInt = "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$driveId/items/$($parentRes.id)`:/$intLinkName`:/content"
    
    $resInt = Invoke-MgGraphRequest -Method PUT -Uri $uriInt -Body $bytesInt -ContentType "text/plain"
    if (-not $resInt -or -not $resInt.id) { throw "Echec de l'upload du lien interne." }
    Write-Host "  > Lien Interne créé ($intLinkName)." -ForegroundColor Green

    # --- VALIDATION ---
    Write-Host "Etape 4 : Validation (Lecture du contenu du lien interne)..." -ForegroundColor DarkGray
    $downloadUri = $resInt.'@microsoft.graph.downloadUrl'
    if ($downloadUri) {
        $client = New-Object System.Net.Http.HttpClient
        $downloadedContent = $client.GetStringAsync($downloadUri).Result
        if ($downloadedContent -match $cibleWebUrl) {
            Write-Host "  > Succès : le fichier téléchargé contient bien la bonne URL cible." -ForegroundColor Green
        }
        else {
            throw "Le contenu du lien interne ne correspond pas à la cible attendue."
        }
    }
    else {
        Write-Host "  > Attention : Pas d'URL de téléchargement directe, validation indirecte via création réussie." -ForegroundColor Yellow
    }

    Write-Host "`n>> OPERATION REUSSIE. DEBUT DU ROLLBACK." -ForegroundColor Cyan

    Write-Host "Etape 5 : Rollback - Suppression du dossier racine..." -ForegroundColor DarkGray
    $delUri = "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$driveId/items/$($parentRes.id)"
    Invoke-MgGraphRequest -Method DELETE -Uri $delUri
    Write-Host "  > Arborescence supprimée (incluant les liens et la cible)." -ForegroundColor Green

    Write-Host "`n[TEST REUSSI]" -ForegroundColor Green
}
catch {
    Write-Host "`n[ECHEC DU TEST] : $($_.Exception.Message)" -ForegroundColor Red
    if ($_.ErrorDetails) { Write-Host "Détails: $($_.ErrorDetails.Message)" -ForegroundColor Red }
    
    if ($parentRes -and $parentRes.id) {
        Write-Host "--- TENTATIVE DE SAUVETAGE / NETTOYAGE MANUEL A FAIRE ---" -ForegroundColor Yellow
        Write-Host "Identifiant parent créé : $($parentRes.id)"
    }
    exit 1
}
