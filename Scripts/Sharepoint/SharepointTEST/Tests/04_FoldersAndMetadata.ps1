#Requires -Version 7.0

<#
.SYNOPSIS
    TEST 04 : Création/Suppression de Dossiers et Application de Métadonnées
.DESCRIPTION
    Création d'une arborescence basique d'un dossier parent et enfant.
    Application de métadonnées (ici on va utiliser un champ standard SharePoint "Title").
    Verification et nettoyage total.
#>

$testRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $testRoot "..\Shared\Init-TestEnvironment.ps1")

Write-Host "--- EXECUTION DU TEST 04 : DOSSIERS ET METADONNEES ---" -ForegroundColor Yellow

$siteUrl = $Global:TestTargetSiteUrl
$libName = $Global:TestTargetLibrary

try {
    Write-Host "Etape 0 : Préparation..." -ForegroundColor DarkGray
    $siteId = Get-AppGraphSiteId -SiteUrl $siteUrl
    $listAndDrive = Get-AppGraphListDriveId -SiteId $siteId -ListDisplayName $libName
    $listId = $listAndDrive.ListId
    $driveId = $listAndDrive.DriveId

    $parentFolderName = "TEST04_Racine_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    $childFolderName = "SousDossier"
    
    # ----------------------------------------------------
    Write-Host "Etape 1 : Création du dossier Parent ($parentFolderName)..." -ForegroundColor DarkGray
    $parentRes = New-AppGraphFolder -SiteId $siteId -DriveId $driveId -FolderName $parentFolderName -ParentFolderId "root"
    if (-not $parentRes -or -not $parentRes.id) { throw "Impossible de créer le dossier parent." }
    Write-Host "  > Dossier parent créé (ID: $($parentRes.id))." -ForegroundColor Green

    Write-Host "Etape 2 : Création du dossier Enfant ($childFolderName)..." -ForegroundColor DarkGray
    $childRes = New-AppGraphFolder -SiteId $siteId -DriveId $driveId -FolderName $childFolderName -ParentFolderId $parentRes.id
    if (-not $childRes -or -not $childRes.id) { throw "Impossible de créer le dossier enfant." }
    Write-Host "  > Dossier enfant créé (ID: $($childRes.id))." -ForegroundColor Green

    Write-Host "Etape 3 : Application des Métadonnées sur le dossier Enfant..." -ForegroundColor DarkGray
    # Pour récupérer l'ID List Item du dossier
    $driveItemContext = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$driveId/items/$($childRes.id)?`$expand=listItem"
    $childListItemId = $driveItemContext.listItem.id

    # Title est un champ de base qu'on peut tester sans créer de nouveau schéma
    $fieldsToUpdate = @{ Title = "Test metadata injectée via Graph API" }
    $metaRes = Set-AppGraphListItemMetadata -SiteId $siteId -ListId $listId -ListItemId $childListItemId -Fields $fieldsToUpdate
    
    # Vérification
    $checkItem = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/lists/$listId/items/$childListItemId"
    if ($checkItem.fields.Title -ne "Test metadata injectée via Graph API") {
        throw "L'application de métadonnées a échoué (Title ne correspond pas)."
    }
    Write-Host "  > Métadonnées appliquées et vérifiées avec succès !" -ForegroundColor Green

    Write-Host "`n>> OPERATION REUSSIE. DEBUT DU ROLLBACK." -ForegroundColor Cyan

    Write-Host "Etape 4 : Rollback - Suppression du dossier Parent (et de son contenu)..." -ForegroundColor DarkGray
    # Graph API supprime l'arbre si on supprime le parent
    $delUri = "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$driveId/items/$($parentRes.id)"
    Invoke-MgGraphRequest -Method DELETE -Uri $delUri
    Write-Host "  > Arborescence supprimée." -ForegroundColor Green

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
