# test-binding-strategies.ps1
$testRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $testRoot "..\Shared\Init-TestEnvironment.ps1")
$siteId = Get-AppGraphSiteId -SiteUrl $Global:TestTargetSiteUrl
$libDrive = Get-AppGraphListDriveId -SiteId $siteId -ListDisplayName $Global:TestTargetLibrary
$listId = $libDrive.ListId

Write-Host "`n--- TEST BINDING STRATEGIES (Robuste) ---" -ForegroundColor Cyan

# 1. Création d'une colonne de site
$colName = "StratTest_" + (Get-Date -Format "mmSS")
$resCol = New-AppGraphSiteColumn -SiteId $siteId -Name $colName -DisplayName "$colName Display" -Type "Text"
$cId = $resCol.Column.id
Write-Host "Created Site Col: $colName ($cId)"

function Try-Binding($Label, $Body) {
    Write-Host "`n>>> Tentative : $Label" -ForegroundColor DarkCyan
    $url = "https://graph.microsoft.com/v1.0/sites/$siteId/lists/$listId/columns"
    try {
        $res = Invoke-MgGraphRequest -Method POST -Uri $url -Body ($Body | ConvertTo-Json -Compress) -ContentType "application/json" -ErrorAction Stop
        Write-Host "✅ SUCCESS!" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "❌ FAILED: $($_.Exception.Message)" -ForegroundColor Red
        if ($_.ErrorDetails) { Write-Host "Détails: $($_.ErrorDetails.Message)" -ForegroundColor Red }
        return $false
    }
}

# Scenario A: ID Direct
Try-Binding "ID Direct" @{ id = $cId }

# Scenario B: Second attempt (Conflict simulation)
Write-Host "`n--- Simulation Conflit (Bind à nouveau) ---" -ForegroundColor Yellow
Try-Binding "ID Direct (Second time)" @{ id = $cId }

# Scenario C: sourceColumn
$colName2 = $colName + "V2"
$resCol2 = New-AppGraphSiteColumn -SiteId $siteId -Name $colName2 -DisplayName "$colName2 Display" -Type "Text"
$cId2 = $resCol2.Column.id
Try-Binding "sourceColumn" @{ sourceColumn = @{ id = $cId2 } }

Write-Host "`n--- Vérification finale des colonnes de la liste ---" -ForegroundColor Gray
$cols = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/lists/$listId/columns"
$cols.value | Where-Object { $_.name -match "StratTest" } | Select-Object name, displayName, id | Format-Table
