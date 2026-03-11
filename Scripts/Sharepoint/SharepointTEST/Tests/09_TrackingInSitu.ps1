#Requires -Version 7.0

<#
.SYNOPSIS
    TEST 09 : Tracking des Déploiements (In-Situ)
.DESCRIPTION
    Crée un fichier de "State" JSON simulant un plan de déploiement enrichi
    avec les IDs réels issus de Microsoft Graph API.
    Upload ce fichier au format JSON dans un dossier caché '_sbuilder_system'
    situé à la racine de la bibliothèque de destination.
#>

$testRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $testRoot "..\Shared\Init-TestEnvironment.ps1")

Write-Host "--- EXECUTION DU TEST 09 : TRACKING IN-SITU ---" -ForegroundColor Yellow

$siteUrl = $Global:TestTargetSiteUrl
$libName = $Global:TestTargetLibrary

try {
    Write-Host "Etape 0 : Préparation..." -ForegroundColor DarkGray
    $siteId = Get-AppGraphSiteId -SiteUrl $siteUrl
    $listAndDrive = Get-AppGraphListDriveId -SiteId $siteId -ListDisplayName $libName
    $driveId = $listAndDrive.DriveId

    $sysFolderName = "_sbuilder_system"
    $deployId = "DEPLOY_" + (Get-Date -Format 'yyyyMMdd_HHmmss')
    $stateFileName = "$deployId.state.json"

    # --- ETAPE 1 : VERIFICATION/CREATION DU DOSSIER SYSTEME ---
    Write-Host "Etape 1 : Vérification/Création du dossier système ($sysFolderName)..." -ForegroundColor White
    
    # On cherche s'il existe à la racine
    $rootItems = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$driveId/root/children?`$filter=name eq '$sysFolderName'"
    
    $sysFolderId = $null
    if ($rootItems.value.Count -gt 0) {
        $sysFolderId = $rootItems.value[0].id
        Write-Host "  > Dossier système existant trouvé (ID: $sysFolderId)" -ForegroundColor Cyan
    }
    else {
        # S'il n'existe pas, on le crée
        $bodyFolder = @{
            name                                = $sysFolderName
            folder                              = @{}
            "@microsoft.graph.conflictBehavior" = "fail"
        }
        $newSys = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$driveId/root/children" -Body $bodyFolder -ContentType "application/json"
        $sysFolderId = $newSys.id
        Write-Host "  > Dossier système créé à la racine (ID: $sysFolderId)" -ForegroundColor Green

        # (Optionnel mais recommandé In-Situ) Le cacher ? 
        # Cacher un dossier nativement via Graph sur SPO n'est pas simple (nécessite de virer les droits visiteur ou manipuler SP.Folder).
        # On assume que la convention de nommage avec "_" suffit dans un premier temps pour un dossier système.
    }

    if (-not $sysFolderId) { throw "Impossible d'obtenir l'ID du dossier système." }

    # --- ETAPE 2 : GENERATION D'UN STATE JSON FACTICE ---
    Write-Host "Etape 2 : Génération du Plan enrichi (State)..." -ForegroundColor White
    $mockState = @{
        DeploymentId       = $deployId
        DateCreated        = (Get-Date).ToString("o")
        TemplateUsed       = "TestModele_v1"
        DeployedGraphNodes = @(
            @{ Type = "Folder"; OriginalName = "Dossier 1"; GraphItemId = "abc-123"; Tags = @{ "Year" = "2026" } },
            @{ Type = "Folder"; OriginalName = "Dossier 2"; GraphItemId = "xyz-789"; Tags = @{} }
        )
    }

    $stateJsonString = $mockState | ConvertTo-Json -Depth 10
    $stateBytes = [System.Text.Encoding]::UTF8.GetBytes($stateJsonString)

    # --- ETAPE 3 : UPLOAD DU STATE DANS LE DOSSIER SYSTEME ---
    Write-Host "Etape 3 : Upload du State JSON ($stateFileName)..." -ForegroundColor White
    # URL = /drives/{driveId}/items/{systemFolderId}:/{filename}:/content
    $uploadUri = "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$driveId/items/$sysFolderId`:/$stateFileName`:/content"
    
    $uploadRes = Invoke-MgGraphRequest -Method PUT -Uri $uploadUri -Body $stateBytes -ContentType "application/json"
    
    if ($uploadRes -and $uploadRes.id) {
        $stateFileId = $uploadRes.id
        Write-Host "  > Fichier State uploade avec succes ! (ID: $stateFileId)" -ForegroundColor Green
    }
    else {
        throw "L'upload du fichier State a echoué."
    }

    Write-Host "`n>> OPERATION REUSSIE. DEBUT DU ROLLBACK." -ForegroundColor Cyan

    Write-Host "Etape 4 : Rollback - Suppression du fichier State de test..." -ForegroundColor DarkGray
    Invoke-MgGraphRequest -Method DELETE -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$driveId/items/$stateFileId"
    Write-Host "  > Fichier State $stateFileName supprimé." -ForegroundColor Green

    # Optionnel: Supprimer le _sbuilder_system pour laisser propre le test
    Write-Host "Etape 5 : Rollback - Suppression du dossier système pour nettoyage complet..." -ForegroundColor DarkGray
    Invoke-MgGraphRequest -Method DELETE -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$driveId/items/$sysFolderId"
    Write-Host "  > Dossier système supprimé." -ForegroundColor Green


    Write-Host "`n[TEST REUSSI]" -ForegroundColor Green
}
catch {
    Write-Host "`n[ECHEC DU TEST] : $($_.Exception.Message)" -ForegroundColor Red
    if ($_.ErrorDetails) { Write-Host "Détails: $($_.ErrorDetails.Message)" -ForegroundColor Red }
    exit 1
}
