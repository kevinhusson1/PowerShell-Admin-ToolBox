# Scripts/Sharepoint/SharepointTEST/Tests/test-v1-syntax-discovery.ps1
$testRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $testRoot "..\Shared\Init-TestEnvironment.ps1")

$SiteId = Get-AppGraphSiteId -SiteUrl $Global:TestTargetSiteUrl

function Try-V1Creation($Label, $BodyObj) {
    Write-Host "`n>>> Test : $Label" -ForegroundColor Cyan
    $url = "https://graph.microsoft.com/v1.0/sites/$SiteId/columns"
    $body = $BodyObj | ConvertTo-Json -Compress
    try {
        $res = Invoke-MgGraphRequest -Method POST -Uri $url -Body $body -ContentType "application/json" -ErrorAction Stop
        Write-Host "✅ Succès !" -ForegroundColor Green
        $res | Select-Object name, @{n='Multi'; e={$_.allowMultipleValues}}, @{n='ChoiceMulti'; e={$_.choice.allowMultipleValues}} | Format-Table
    } catch {
        Write-Host "❌ Échec : $($_.Exception.Message)" -ForegroundColor Red
        if ($_.ErrorDetails) { Write-Host "Détails: $($_.ErrorDetails.Message)" -ForegroundColor Red }
    }
}

# Variante 1: Root (La plus probable selon docs)
Try-V1Creation "allowMultipleValues à la racine" @{
    name = "V1_Root_" + (Get-Date -Format "HHmm")
    displayName = "V1 Root"
    choice = @{ choices = @("A", "B") }
    allowMultipleValues = $true
}

# Variante 2: Dans choice
Try-V1Creation "allowMultipleValues dans choice" @{
    name = "V1_InChoice_" + (Get-Date -Format "HHmm")
    displayName = "V1 In Choice"
    choice = @{ 
        choices = @("A", "B")
        allowMultipleValues = $true
    }
}

# Variante 3: Sans displayAs, juste allowMultipleValues
Try-V1Creation "Minimaliste Root" @{
    name = "V1_Min_" + (Get-Date -Format "HHmm")
    displayName = "V1 Min"
    choice = @{ choices = @("A") }
    allowMultipleValues = $true
}
