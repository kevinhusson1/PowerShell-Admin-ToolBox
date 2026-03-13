# Scripts/Sharepoint/SharepointTEST/Tests/test-column-indexing.ps1
Start-Transcript -Path (Join-Path $PSScriptRoot "test-column-indexing.log") -Force

$testRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $testRoot "..\Shared\Init-TestEnvironment.ps1")

# Résolution IDs
$Global:TestSiteId = Get-AppGraphSiteId -SiteUrl $Global:TestTargetSiteUrl
$TestSiteId = $Global:TestSiteId

Write-Host "--- TEST INDEXATION COLONNES v1.0 ---" -ForegroundColor Cyan

$schemaJson = '[{"Indexed":true,"Type":"Choix Multiples","Name":"Services_Test"},{"Indexed":false,"Type":"Date et Heure","Name":"DateDeploiement_Test"},{"Indexed":true,"Type":"Choix Multiples","Name":"Year_Test"},{"Indexed":true,"Type":"Texte","Name":"Rubriques_Test"},{"Indexed":false,"Type":"Oui/Non","Name":"TestBoolean_Test"}]'
$schema = $schemaJson | ConvertFrom-Json

$colsUrl = "https://graph.microsoft.com/v1.0/sites/$TestSiteId/columns"

foreach ($col in $schema) {
    Write-Host "`n[+] Création colonne : $($col.Name) (Type: $($col.Type), Indexed: $($col.Indexed))" -ForegroundColor Cyan
    
    $body = @{
        name = $col.Name
        displayName = $col.Name
        # Propriété cruciale à tester
        indexed = $col.Indexed
    }

    # Mapping des types
    switch ($col.Type) {
        "Choix Multiples" {
            $body["choice"] = @{ choices = @("Choix A", "Choix B"); allowTextEntry = $true; displayAs = "checkBoxes" }
            $body["allowMultipleValues"] = $true
        }
        "Date et Heure" {
            $body["dateTime"] = @{}
        }
        "Texte" {
            $body["text"] = @{}
        }
        "Oui/Non" {
            $body["boolean"] = @{}
        }
    }

    try {
        $res = Invoke-MgGraphRequest -Method POST -Uri $colsUrl -Body $body -ContentType "application/json" -ErrorAction Stop
        Write-Host "   ✅ Colonne créée. ID: $($res.id)" -ForegroundColor Green
        
        if ($res.indexed -eq $col.Indexed) {
            Write-Host "   ✅ Propriété 'indexed' correcte dans la réponse : $($res.indexed)" -ForegroundColor Green
        } else {
            Write-Host "   ❌ Propriété 'indexed' incorrecte dans la réponse ! Reçu: $($res.indexed), Attendu: $($col.Indexed)" -ForegroundColor Red
        }

        # Vérification immédiate via un GET pour confirmer la persistance
        $checkRes = Invoke-MgGraphRequest -Method GET -Uri ("$colsUrl/$($res.id)") -ErrorAction Stop
        Write-Host "   🔍 Vérification via GET : indexed = $($checkRes.indexed)" -ForegroundColor Yellow
    }
    catch {
        Write-Host "   ❌ Erreur : $($_.Exception.Message)" -ForegroundColor Red
        if ($_.ErrorDetails) { Write-Host "   Détails : $($_.ErrorDetails | Out-String)" -ForegroundColor DarkRed }
    }
}

Write-Host "`n--- FIN DES TESTS INDEXATION ---" -ForegroundColor Cyan
Stop-Transcript
