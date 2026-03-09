#Requires -Version 7.0

<#
.SYNOPSIS
    TEST 05 : Gestion des Permissions (Optimisation)
.DESCRIPTION
    Créé un dossier et gère finement les permissions. Teste l'attribution
    d'un droit spécifique, la vérification de l'ajout, et enfin la suppression
    de cette permission pour restaurer l'état (Rollback ciblé).
#>

$testRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $testRoot "..\Shared\Init-TestEnvironment.ps1")

Write-Host "--- EXECUTION DU TEST 05 : GESTION DES PERMISSIONS ---" -ForegroundColor Yellow

$siteUrl = $Global:TestTargetSiteUrl
$libName = $Global:TestTargetLibrary
# Attention: un email valide du locataire pour tester. Le compte khusson@vosgelis.fr était dans le JSON.
$testUserEmail = "khusson@vosgelis.fr"

try {
    Write-Host "Etape 0 : Préparation..." -ForegroundColor DarkGray
    $siteId = Get-AppGraphSiteId -SiteUrl $siteUrl
    $listAndDrive = Get-AppGraphListDriveId -SiteId $siteId -ListDisplayName $libName
    $driveId = $listAndDrive.DriveId

    $folderName = "TEST05_Perms_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    
    Write-Host "Etape 1 : Création du dossier test ($folderName)..." -ForegroundColor DarkGray
    $folderRes = New-AppGraphFolder -SiteId $siteId -DriveId $driveId -FolderName $folderName -ParentFolderId "root"
    if (-not $folderRes) { throw "Impossible de créer le dossier." }
    $itemId = $folderRes.id

    Write-Host "Etape 2 : Attribution de la permission (Read) via Invite (sans mail)..." -ForegroundColor DarkGray
    $inviteBody = @{
        recipients      = @( @{ email = $testUserEmail } )
        roles           = @("read")
        requireSignIn   = $true
        sendSignInPromo = $false
    } | ConvertTo-Json -Depth 5
    
    $inviteRes = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$driveId/items/$itemId/invite" -Body $inviteBody -ContentType "application/json"
    Write-Host "  > API Invite exécutée avec succès." -ForegroundColor Green

    Write-Host "Etape 3 : Récupération et vérification des permissions..." -ForegroundColor DarkGray
    if (-not $inviteRes -or -not $inviteRes.value) { throw "La réponse de l'API invite est vide." }
    $targetPermId = $inviteRes.value[0].id
    
    if (-not $targetPermId) { throw "La permission n'a pas été trouvée dans la réponse." }
    Write-Host "  > Permission trouvée (ID: $targetPermId)." -ForegroundColor Green

    Write-Host "`n>> OPERATION REUSSIE. DEBUT DU ROLLBACK." -ForegroundColor Cyan

    Write-Host "Etape 4 : Rollback - Suppression de la permission spécifique..." -ForegroundColor DarkGray
    $delPermUri = "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$driveId/items/$itemId/permissions/$targetPermId"
    Invoke-MgGraphRequest -Method DELETE -Uri $delPermUri
    Write-Host "  > Permission ID $($targetPerm.id) retirée." -ForegroundColor Green

    Write-Host "Etape 5 : Rollback - Suppression du dossier de test..." -ForegroundColor DarkGray
    Invoke-MgGraphRequest -Method DELETE -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$driveId/items/$itemId"
    Write-Host "  > Dossier $folderName supprimé." -ForegroundColor Green

    Write-Host "`n[TEST REUSSI]" -ForegroundColor Green
}
catch {
    Write-Host "`n[ECHEC DU TEST] : $($_.Exception.Message)" -ForegroundColor Red
    if ($_.ErrorDetails) { Write-Host "Détails: $($_.ErrorDetails.Message)" -ForegroundColor Red }
    exit 1
}
