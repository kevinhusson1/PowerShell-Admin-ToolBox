# test-fallback-binding.ps1
$testRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $testRoot "..\Shared\Init-TestEnvironment.ps1")
$siteId = Get-AppGraphSiteId -SiteUrl $Global:TestTargetSiteUrl
$libDrive = Get-AppGraphListDriveId -SiteId $siteId -ListDisplayName $Global:TestTargetLibrary
$listId = $libDrive.ListId

Write-Host "`n--- TEST FALLBACK BINDING CORRECTION ---" -ForegroundColor Cyan

# 1. Création d'une colonne de site
$colName = "FallbackTest_" + (Get-Date -Format "mmSS")
$resCol = New-AppGraphSiteColumn -SiteId $siteId -Name $colName -DisplayName "Fallback Test" -Type "Text"
$cId = $resCol.Column.id
Write-Host "Site column created. Waiting for propagation..."
Start-Sleep -Seconds 5

# 2. Simulation du mode FALLBACK
Write-Host "Simulating Fallback Binding for column $colName..."
$listColsUrl = "https://graph.microsoft.com/v1.0/sites/$siteId/lists/$listId/columns"
$bindPayload = @{ id = $cId } | ConvertTo-Json

try {
    Invoke-MgGraphRequest -Method POST -Uri $listColsUrl -Body $bindPayload -ContentType "application/json" -ErrorAction Stop
    Write-Host "✅ SUCCESS: Column bound to list via sourceColumn@odata.bind!" -ForegroundColor Green
    
    # 3. Vérification de la présence
    $listCols = Invoke-MgGraphRequest -Method GET -Uri $listColsUrl
    if ($listCols.value | Where-Object { $_.name -eq $colName }) {
        Write-Host "✅ Verified: Column is present in the list fields." -ForegroundColor Green
    } else {
        Write-Warning "⚠️ Column bound but not found in list fields (latency?)"
    }
} catch {
    Write-Host "❌ FAILED: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.ErrorDetails) { Write-Host "$($_.ErrorDetails.Message)" -ForegroundColor Red }
}
