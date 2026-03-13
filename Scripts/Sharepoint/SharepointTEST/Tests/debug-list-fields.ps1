# Scripts/Sharepoint/SharepointTEST/Tests/debug-list-fields.ps1
$testRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $testRoot "..\Shared\Init-TestEnvironment.ps1")

$SiteId = Get-AppGraphSiteId -SiteUrl $Global:TestTargetSiteUrl
$logFile = Join-Path $testRoot "debug-list-fields.txt"
"--- DIAGNOSTIC SHAREPOINT TEST (V7) ---" | Out-File $logFile
"Site: $SiteId" | Out-File $logFile -Append

$listsData = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$SiteId/lists"
"--- LISTES DISPONIBLES ---" | Out-File $logFile -Append
foreach ($l in $listsData.value) {
    " - Name: $($l.name) | Display: $($l.displayName) | ID: $($l.id)" | Out-File $logFile -Append
}

$ListId = $listsData.value | Where-Object { $_.name -eq "Shared Documents" -or $_.displayName -eq "Documents" -or $_.name -eq "Documents" } | Select-Object -First 1 -ExpandProperty id
"ListId résolu: $ListId" | Out-File $logFile -Append

try {
    $url = "https://graph.microsoft.com/v1.0/sites/$SiteId/lists/$ListId/columns?`$select=name,displayName,indexed,columnGroup,text,choice,number,dateTime,boolean"
    $res = Invoke-MgGraphRequest -Method GET -Uri $url -ErrorAction Stop
    
    foreach ($col in $res.value) {
        $type = "Unknown"
        if ($col.text) { $type = "Text" }
        elseif ($col.choice) { $type = "Choice" }
        elseif ($col.number) { $type = "Number" }
        elseif ($col.dateTime) { $type = "DateTime" }
        elseif ($col.boolean) { $type = "Boolean" }
        
        $multiVal = "N/A"
        if ($col.choice) {
            if ($null -ne $col.allowMultipleValues) { $multiVal = $col.allowMultipleValues }
            elseif ($null -ne $col.choice.allowMultipleValues) { $multiVal = $col.choice.allowMultipleValues }
            else { $multiVal = "False" }
        }
        
        "Internal: $($col.name) | Display: $($col.displayName) | Type: $type | Multi: $multiVal | Indexed: $($col.indexed)" | Out-File $logFile -Append
    }
    Write-Host "✅ Diagnostic terminé : $logFile" -ForegroundColor Green
}
catch {
    "❌ Erreur : $($_.Exception.Message)" | Out-File $logFile -Append
}
