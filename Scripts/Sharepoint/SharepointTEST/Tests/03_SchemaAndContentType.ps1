#Requires -Version 7.0

<#
.SYNOPSIS
    TEST 03 : Création/Suppression (Rollback) du Schema & ContentType
.DESCRIPTION
    Valide la création de SiteColumns, d'un ContentType personnalisé
    basé sur un Schéma JSON, son attachement à une liste, et vérifie la
    possibilité de tout nettoyer (Rollback).
#>

$testRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $testRoot "..\Shared\Init-TestEnvironment.ps1")

Write-Host "--- EXECUTION DU TEST 03 : SCHEMA & CONTENT TYPE ---" -ForegroundColor Yellow

$siteUrl = $Global:TestTargetSiteUrl
$libName = $Global:TestTargetLibrary

try {
    Write-Host "Etape 0 : Préparation (Résolution des IDs)..." -ForegroundColor DarkGray
    $siteId = Get-AppGraphSiteId -SiteUrl $siteUrl
    $listAndDrive = Get-AppGraphListDriveId -SiteId $siteId -ListDisplayName $libName
    $listId = $listAndDrive.ListId
    
    # ----------------------------------------------------
    # LECTURE DU SCHEMA
    # ----------------------------------------------------
    $schemaPath = Join-Path $testRoot "..\Data\sp_folder_schemas.json"
    $schemaData = Get-Content $schemaPath -Raw | ConvertFrom-Json
    $schemaDef = $schemaData[0]
    $columnsJson = $schemaDef.ColumnsJson | ConvertFrom-Json
    $ctSafeName = "SBuilder_TEST_" + ($schemaDef.DisplayName -replace '[\\/:*?"<>|#%]', '_')

    $createdColumnIds = @()
    $createdContentTypeId = $null
    $listAttachedContentTypeId = $null

    Write-Host "Etape 1 : Création des SiteColumns..." -ForegroundColor DarkGray
    foreach ($c in $columnsJson) {
        $isMulti = ($c.Type -eq "Choix Multiples")
        $gType = switch ($c.Type) { "Nombre" { "Number" } "Choix" { "Choice" } "Choix Multiples" { "Choice" } Default { "Text" } }
        
        $choices = @()
        if ($gType -eq "Choice") { $choices = @("Valeur Test A", "Valeur Test B") }

        # Nom safe pour éviter les conflits si le test plante
        $safeColName = "TestCol_" + $c.Name
        
        $resCol = New-AppGraphSiteColumn -SiteId $siteId -Name $safeColName -DisplayName $safeColName -Type $gType -Choices $choices -AllowMultiple:$isMulti
        if ($resCol -and $resCol.Column.id) {
            $createdColumnIds += $resCol.Column.id
            Write-Host "  > Colonne '$safeColName' créée ($($resCol.Column.id))." -ForegroundColor DarkGray
        }
        else {
            throw "Impossible de créer la colonne $safeColName"
        }
    }

    Write-Host "Etape 2 : Création du ContentType ($ctSafeName)..." -ForegroundColor DarkGray
    $resCT = New-AppGraphContentType -SiteId $siteId -Name $ctSafeName -Description "CT de Test Unitaire" -Group "Vosgelis App" -BaseId "0x0120" -ColumnIdsToBind $createdColumnIds
    if (-not $resCT -or -not $resCT.ContentType.id) { throw "Impossible de créer le ContentType $ctSafeName" }
    $createdContentTypeId = $resCT.ContentType.id
    Write-Host "  > ContentType créé avec succès ($createdContentTypeId)." -ForegroundColor Green

    Write-Host "Etape 3 : Attachement du ContentType à la Liste ($listId)..." -ForegroundColor DarkGray
    $addCtUri = "https://graph.microsoft.com/v1.0/sites/$siteId/lists/$listId/contentTypes/addCopy"
    $bodyCtAdd = @{ contentType = $createdContentTypeId }
    
    $resAdd = Invoke-MgGraphRequest -Method POST -Uri $addCtUri -Body $bodyCtAdd -ContentType "application/json"
    $listAttachedContentTypeId = $resAdd.id
    Write-Host "  > ContentType attaché à la liste sous l'ID ($listAttachedContentTypeId)." -ForegroundColor Green

    # Validation (List CT exists)
    $checkCtUri = "https://graph.microsoft.com/v1.0/sites/$siteId/lists/$listId/contentTypes/$listAttachedContentTypeId"
    $checkRes = Invoke-MgGraphRequest -Method GET -Uri $checkCtUri
    if (-not $checkRes) { throw "Validation de l'attachement a échoué." }

    Write-Host "`n>> CREATION VALIDEE. DEBUT DU ROLLBACK." -ForegroundColor Cyan

    Write-Host "Etape 4 : Rollback - Détachement de la Liste..." -ForegroundColor DarkGray
    # Graph ne permet pas de DELETE un ContentType de liste s'il a été utilisé, mais on vient à peine de le créer.
    Invoke-MgGraphRequest -Method DELETE -Uri $checkCtUri
    Write-Host "  > ContentType détaché de la liste." -ForegroundColor Green

    Write-Host "Etape 5 : Rollback - Suppression du ContentType du Site..." -ForegroundColor DarkGray
    $delCtUri = "https://graph.microsoft.com/v1.0/sites/$siteId/contentTypes/$createdContentTypeId"
    Invoke-MgGraphRequest -Method DELETE -Uri $delCtUri
    Write-Host "  > ContentType supprimé du site." -ForegroundColor Green

    Write-Host "Etape 6 : Rollback - Suppression des SiteColumns..." -ForegroundColor DarkGray
    foreach ($colId in $createdColumnIds) {
        Invoke-MgGraphRequest -Method DELETE -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/columns/$colId"
        Write-Host "  > Colonne $colId supprimée." -ForegroundColor DarkGray
    }
    Write-Host "  > Toutes les colonnes temporaires supprimées." -ForegroundColor Green

    Write-Host "`n[TEST REUSSI]" -ForegroundColor Green
}
catch {
    Write-Host "`n[ECHEC DU TEST] : $($_.Exception.Message)" -ForegroundColor Red
    if ($_.ErrorDetails) { Write-Host "Détails: $($_.ErrorDetails.Message)" -ForegroundColor Red }
    
    # Tentative Minimale de Rollback Manuel
    Write-Host "--- TENTATIVE DE SAUVETAGE / NETTOYAGE MANUEL A FAIRE ---" -ForegroundColor Yellow
    exit 1
}
