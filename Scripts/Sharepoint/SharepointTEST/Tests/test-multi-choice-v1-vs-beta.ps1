# Scripts/Sharepoint/SharepointTEST/Tests/test-multi-choice-v1-vs-beta.ps1
$testRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $testRoot "..\Shared\Init-TestEnvironment.ps1")

$SiteId = Get-AppGraphSiteId -SiteUrl $Global:TestTargetSiteUrl

function Test-CreateColumn($Version, $ColName) {
    Write-Host "--- Test Création Multi-Choix ($Version) : $ColName ---" -ForegroundColor Cyan
    $url = "https://graph.microsoft.com/$Version/sites/$SiteId/columns"
    $body = @{
        description = "Test Multi Choice $Version"
        displayName = $ColName
        name        = $ColName
        choice      = @{
            choices = @("A", "B", "C")
            allowTextEntry = $false
            displayAs      = "checkBoxes"
        }
        allowMultipleValues = $true
    } | ConvertTo-Json -Compress

    try {
        $res = Invoke-MgGraphRequest -Method POST -Uri $url -Body $body -ContentType "application/json" -ErrorAction Stop
        Write-Host "✅ Succès ($Version)" -ForegroundColor Green
        return $res
    } catch {
        Write-Host "❌ Échec ($Version) : $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

$cV1 = Test-CreateColumn "v1.0" "MultiV1_Test"
$cBeta = Test-CreateColumn "beta" "MultiBeta_Test"

if ($cV1) {
    Write-Host "`nInspection V1 (site):"
    $cV1 | Select-Object name, displayName, indexed, allowMultipleValues | Format-List
}
if ($cBeta) {
    Write-Host "`nInspection Beta (site):"
    $cBeta | Select-Object name, displayName, indexed, allowMultipleValues | Format-List
}
