# Scripts/Sharepoint/SharepointTEST/Tests/final-validation-indexing.ps1
Start-Transcript -Path (Join-Path $PSScriptRoot "final-validation-indexing.log") -Force

$testRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $testRoot "..\Shared\Init-TestEnvironment.ps1")

Write-Host "--- VALIDATION FINALE : STRUCTURE + INDEXATION ---" -ForegroundColor Cyan

$TargetSiteUrl = $Global:TestTargetSiteUrl
$TargetLibraryName = $Global:TestTargetLibrary
$FolderSchemaName = "User_Schema_Final_V7"
$FolderSchemaJson = '[{"Indexed":true,"Type":"Choix Multiples","Name":"Services_V7"},{"Indexed":false,"Type":"Date et Heure","Name":"DateDeploiement_V7"},{"Indexed":true,"Type":"Choix Multiples","Name":"Year_V7"},{"Indexed":true,"Type":"Texte","Name":"Rubriques_V7"},{"Indexed":false,"Type":"Oui/Non","Name":"TestBoolean_V7"}]'

# Simulation d'une structure simple utilisant ce schéma
$StructureJson = '[{"Id":"root","Name":"Validation_Final_V7","Type":"Folder","Tags":[{"Name":"Year_V7","Value":["2025"]},{"Name":"Services_V7","Value":["OPTIMIZED"]},{"Name":"Rubriques_V7","Value":"Success V7"}]}]'

try {
    Write-Host "[1] Lancement de New-AppSPStructure..." -ForegroundColor Yellow
    $result = New-AppSPStructure `
        -TargetSiteUrl $TargetSiteUrl `
        -TargetLibraryName $TargetLibraryName `
        -RootFolderName "Validation_Index_$(Get-Date -UFormat '%H%M%S')" `
        -StructureJson $StructureJson `
        -FolderSchemaJson $FolderSchemaJson `
        -FolderSchemaName $FolderSchemaName `
        -ClientId $Global:TestClientId `
        -Thumbprint $Global:TestThumbprint `
        -TenantName $Global:TestTenantId

    if ($result.Success) {
        Write-Host "✅ New-AppSPStructure a réussi !" -ForegroundColor Green
        
        # Vérification de l'indexation des colonnes créées
        Write-Host "`n[2] Vérification de l'indexation sur Graph..." -ForegroundColor Yellow
        $siteId = Get-AppGraphSiteId -SiteUrl $TargetSiteUrl
        $colsUrl = "https://graph.microsoft.com/v1.0/sites/$siteId/columns"
        $allCols = Invoke-MgGraphRequest -Method GET -Uri $colsUrl -ErrorAction Stop
        
        $testCols = @("Services_V7", "DateDeploiement_V7", "Year_V7", "Rubriques_V7", "TestBoolean_V7")
        foreach ($cName in $testCols) {
            $col = $allCols.value | Where-Object { $_.name -eq $cName -or $_.displayName -eq $cName }
            if ($col) {
                $expectedIndexed = ($FolderSchemaJson | ConvertFrom-Json | Where-Object Name -eq $cName).Indexed
                $color = if ($col.indexed -eq $expectedIndexed) { "Green" } else { "Red" }
                Write-Host "   Column: $($col.displayName) (internal: $($col.name)) | Indexed: $($col.indexed)" -ForegroundColor $color
            } else {
                Write-Host "   ❌ Colonne $cName introuvable !" -ForegroundColor Red
            }
        }
    } else {
        Write-Host "❌ New-AppSPStructure a échoué." -ForegroundColor Red
        $result.Errors | ForEach-Object { Write-Host "   Error: $_" -ForegroundColor DarkRed }
    }
}
catch {
    Write-Host "❌ Erreur critique : $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n--- FIN DE VALIDATION ---" -ForegroundColor Cyan
Stop-Transcript
