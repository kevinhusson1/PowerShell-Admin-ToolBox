# Scripts/Sharepoint/SharepointTEST/Tests/test-graph-v1.ps1
Start-Transcript -Path (Join-Path $PSScriptRoot "test-graph-v1.log") -Force

$testRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $testRoot "..\Shared\Init-TestEnvironment.ps1")

# On n'importe pas le module Toolbox.SharePoint pour tester les commandes brutes Invoke-MgGraphRequest en v1.0
# On utilise les variables globales de Init-TestEnvironment ($SiteId, etc.)

# Résolution dynamique des IDs pour le test
Write-Host "[0] Résolution des IDs de test..." -ForegroundColor DarkGray
$Global:TestSiteId = Get-AppGraphSiteId -SiteUrl $Global:TestTargetSiteUrl
$Global:TestRes = Get-AppGraphListDriveId -SiteId $Global:TestSiteId -ListDisplayName $Global:TestTargetLibrary
$Global:TestDriveId = $Global:TestRes.DriveId

$TestSiteId = $Global:TestSiteId
$TestDriveId = $Global:TestDriveId

if (-not $TestSiteId) {
    Write-Error "TestSiteId non défini. Lancez d'abord Init-TestEnvironment."
    exit
}

Write-Host "--- TEST GRAPH v1.0 ---" -ForegroundColor Cyan

# 1. Test Site Columns (v1.0)
Write-Host "[1] Test Site Columns GET & POST (v1.0)..."
$colsUrl = "https://graph.microsoft.com/v1.0/sites/$TestSiteId/columns"
try {
    $resCols = Invoke-MgGraphRequest -Method GET -Uri $colsUrl -ErrorAction Stop
    Write-Host "   ✅ GET Columns v1.0 : OK ($($resCols.value.Count) colonnes)" -ForegroundColor Green
    
    # Tentative de création d'une colonne de test
    $testColName = "TestColV1_" + (Get-Date -Format "mmSS")
    $bodyCol = @{
        name = $testColName
        displayName = "Test Column V1"
        # En v1.0, ne pas mettre l'objet de type (text/choice) s'il est vide lors du POST initial
        # ou utiliser une structure minimale explicite
        text = @{} 
    }
    # Correctif v1.0 : Structure simplifiée pour le texte
    $bodyCol = @{
        name = $testColName
        displayName = "Test Column V1"
        text = @{} # Une hashtable vide suffit en v1.0
    }
    $newCol = Invoke-MgGraphRequest -Method POST -Uri $colsUrl -Body $bodyCol -ContentType "application/json" -ErrorAction Stop
    Write-Host "   ✅ POST Column v1.0 : OK (ID: $($newCol.id))" -ForegroundColor Green
    $Global:CreatedColId = $newCol.id
}
catch {
    Write-Host "   ❌ Erreur Columns v1.0 : $($_.Exception.Message)" -ForegroundColor Red
    if ($_.ErrorDetails) { Write-Host "   Détails API : $($_.ErrorDetails | Out-String)" -ForegroundColor DarkRed }
}

# 2. Test Content Types (v1.0)
Write-Host "[2] Test Content Types GET & POST (v1.0)..."
$ctsUrl = "https://graph.microsoft.com/v1.0/sites/$TestSiteId/contentTypes"
try {
    $resCts = Invoke-MgGraphRequest -Method GET -Uri $ctsUrl -ErrorAction Stop
    Write-Host "   ✅ GET ContentTypes v1.0 : OK ($($resCts.value.Count) types)" -ForegroundColor Green
    
    # Création CT de test
    $testCtName = "TestCTV1_" + (Get-Date -Format "mmSS")
    $bodyCT = @{
        name = $testCtName
        description = "Test CT V1"
        base = @{ id = "0x01" } # Item de base
    }
    $newCT = Invoke-MgGraphRequest -Method POST -Uri $ctsUrl -Body $bodyCT -ContentType "application/json" -ErrorAction Stop
    Write-Host "   ✅ POST ContentType v1.0 : OK (ID: $($newCT.id))" -ForegroundColor Green
    $Global:CreatedCTId = $newCT.id

    # Test OData Bind (Add column to CT)
    if ($Global:CreatedColId) {
        Write-Host "   [2.1] Test OData Bind column to CT v1.0..."
        $bindUrl = "https://graph.microsoft.com/v1.0/sites/$TestSiteId/contentTypes/$($newCT.id)/columns"
        $bindBody = @{
            "sourceColumn@odata.bind" = "https://graph.microsoft.com/v1.0/sites/$TestSiteId/columns/$($Global:CreatedColId)"
        }
        Invoke-MgGraphRequest -Method POST -Uri $bindUrl -Body $bindBody -ContentType "application/json" -ErrorAction Stop | Out-Null
        Write-Host "   ✅ OData Bind v1.0 : OK" -ForegroundColor Green
    }
}
catch {
    Write-Host "   ❌ Erreur ContentTypes v1.0 : $($_.Exception.Message)" -ForegroundColor Red
    if ($_.ErrorDetails) { Write-Host "   Détails API : $($_.ErrorDetails | Out-String)" -ForegroundColor DarkRed }
}

# 3. Test ListItem Fields (v1.0)
Write-Host "[3] Test ListItem Fields PATCH (v1.0)..."
try {
    # On récupère la liste liée au drive
    $listReq = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$TestSiteId/drives/$TestDriveId/list" -ErrorAction Stop
    $listId = $listReq.id
    
    # On récupère un item au hasard (le premier)
    $itemsReq = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$TestSiteId/lists/$listId/items?top=1" -ErrorAction Stop
    if ($itemsReq.value) {
        $itemId = $itemsReq.value[0].id
        $fieldsUrl = "https://graph.microsoft.com/v1.0/sites/$TestSiteId/lists/$listId/items/$itemId/fields"
        
        # On tente de mettre à jour le Title (champ standard v1.0)
        $updateBody = @{ Title = "Test Update V1 " + (Get-Date -Format "HH:mm:ss") }
        Invoke-MgGraphRequest -Method PATCH -Uri $fieldsUrl -Body $updateBody -ContentType "application/json" -ErrorAction Stop | Out-Null
        Write-Host "   ✅ PATCH Fields v1.0 : OK (ItemId: $itemId)" -ForegroundColor Green
    }
    else {
        Write-Warning "   ⚠️ Aucun item trouvé dans la liste pour tester le PATCH fields."
    }
}
catch {
    Write-Host "   ❌ Erreur Fields v1.0 : $($_.Exception.Message)" -ForegroundColor Red
    if ($_.ErrorDetails) { Write-Host "   Détails API : $($_.ErrorDetails | Out-String)" -ForegroundColor DarkRed }
}

Write-Host "--- FIN DES TESTS ---" -ForegroundColor Cyan
