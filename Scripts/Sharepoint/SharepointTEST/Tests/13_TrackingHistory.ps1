# Requires -Version 7.0
# Scripts/Sharepoint/SharepointTest/Tests/13_TrackingHistory.ps1

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir "..\Shared\Init-TestEnvironment.ps1")

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " TEST 13 : HISTORIQUE DE DEPLOIEMENT (TRACKING GRAPH API)" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$siteId = Get-AppGraphSiteId -SiteUrl $Global:TestTargetSiteUrl
Write-Host "Site cible : $Global:TestTargetSiteUrl ($siteId)" -ForegroundColor DarkGray

$listName = "SharePointBuilder_Tracking"
$listId = $null

try {
    Write-Host "`nETAPE 1 : Verification / Creation de la liste '$listName'" -ForegroundColor Yellow
    $listsReq = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/lists?`$select=id,displayName"
    $found = $listsReq.value | Where-Object { $_.displayName -eq $listName }
    
    if ($found) {
        $listId = $found.id
        Write-Host "  > Liste trouvée ($listId)." -ForegroundColor Green
    }
} catch {
    Write-Host "  > Erreur lors de la lecture des listes : $_" -ForegroundColor Red
}

if (-not $listId) {
    Write-Host "  > Création de la liste '$listName' en cours..." -ForegroundColor Cyan
    
    $listDef = @{
        displayName = $listName
        columns = @(
            @{ name = "TargetUrl"; text = @{} },
            @{ name = "TemplateId"; text = @{} },
            @{ name = "TemplateVersion"; text = @{} },
            @{ name = "ConfigName"; text = @{} },
            @{ name = "NamingRuleId"; text = @{} },
            @{ name = "DeployedBy"; text = @{} },
            @{ name = "TemplateJson"; text = @{ allowMultipleLines = $true } },
            @{ name = "FormValuesJson"; text = @{ allowMultipleLines = $true } },
            @{ name = "FormDefinitionJson"; text = @{ allowMultipleLines = $true } },
            @{ name = "FolderSchemaJson"; text = @{ allowMultipleLines = $true } },
            @{ name = "DeployedDate"; dateTime = @{} }
        )
        list = @{
            template = "genericList"
            hidden = $true
        }
    }
    
    $bodyJson = $listDef | ConvertTo-Json -Depth 5 -Compress
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($bodyJson)
    
    try {
        $res = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/lists" -Body $bodyBytes -ContentType "application/json" -ErrorAction Stop
        $listId = $res.id
        Write-Host "  > Liste créée avec succès ($listId)." -ForegroundColor Green
    } catch {
        Write-Host "  > ERREUR Création liste : $_" -ForegroundColor Red
        if ($_.ErrorDetails) { Write-Host $_.ErrorDetails.Message -ForegroundColor Red }
        exit
    }
}

try {
    Write-Host "`nETAPE 2 : Injection des données Mock (Historique Complet)" -ForegroundColor Yellow
    
    $mockTemplateJson = '{"Id":"e7102563-b9bd-400b-bcb7-6c2e8f84064e","Structure":"Mock"}'
    $mockFormValues = '{"Année":"2029","Rubriques":"PPI2","Services":"TEST"}'
    $mockFormDef = '{"Layout":[{"Name":"Année","TargetColumnInternalName":"Year"}]}'
    $mockSchemaJson = '[{"Name":"Year","Type":"Texte"},{"Name":"Services","Type":"Choix Multiples"}]'

    $itemData = @{
        fields = @{
            Title = "e7102563-b9bd-400b-bcb7-6c2e8f84064e"
            TargetUrl = "$Global:TestTargetSiteUrl/Shared Documents/General/TEST-2029-PPI2"
            TemplateId = "Test_DossierAvance"
            TemplateVersion = "v5.0"
            ConfigName = "MaConfigurationTEST"
            NamingRuleId = "Regle_TEST-001"
            DeployedBy = $env:USERNAME
            TemplateJson = $mockTemplateJson
            FormValuesJson = $mockFormValues
            FormDefinitionJson = $mockFormDef
            FolderSchemaJson = $mockSchemaJson
            DeployedDate = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        }
    }

    $itemJson = $itemData | ConvertTo-Json -Depth 5 -Compress
    $itemBytes = [System.Text.Encoding]::UTF8.GetBytes($itemJson)

    $itemRes = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/lists/$listId/items" -Body $itemBytes -ContentType "application/json" -ErrorAction Stop
    Write-Host "  > Historique de déploiement ajouté avec succès ! (ListItem ID: $($itemRes.id))" -ForegroundColor Green

} catch {
    Write-Host "  > ERREUR lors de l'ajout de l'item : $_" -ForegroundColor Red
    if ($_.ErrorDetails) { Write-Host $_.ErrorDetails.Message -ForegroundColor Red }
}

Write-Host "`nTEST TERMINE." -ForegroundColor Cyan
