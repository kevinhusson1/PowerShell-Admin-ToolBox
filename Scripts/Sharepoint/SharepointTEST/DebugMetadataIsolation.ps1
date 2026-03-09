# Scripts/Sharepoint/SharepointTEST/DebugMetadataIsolation.ps1
# Version 4.33 - Diagnostic Approfondi (Facettes & Choix)

# 1. Résolution des chemins
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = (Get-Item $scriptRoot).Parent.Parent.Parent.FullName
$env:PSModulePath = "$($projectRoot)\Modules;$($projectRoot)\Vendor;$($env:PSModulePath)"

# 2. Import des modules indispensables
Import-Module "Core", "Logging", "Database", "Localization", "Azure" -Force

# 3. Initialisation Environnement
Initialize-AppDatabase -ProjectRoot $projectRoot
$cfg = Get-AppConfiguration
Initialize-AppLocalization -ProjectRoot $projectRoot -Language $cfg.defaultLanguage

# 4. Paramètres Auth
$TenantId = $cfg.azure.tenantName
$ClientId = $cfg.azure.authentication.userAuth.appId
$Thumbprint = $cfg.azure.certThumbprint

Write-Host "--- Connexion Graph ($TenantId) ---" -ForegroundColor Cyan
Connect-AppAzureCert -TenantId $TenantId -ClientId $ClientId -Thumbprint $Thumbprint | Out-Null

# Paramètres Cible
$SiteUrl = "https://vosgelis365.sharepoint.com/sites/TEST_PNP" 
$ListTitle = "Documents"
$ItemId = "2725" 

try {
    $siteId = Get-AppGraphSiteId -SiteUrl $SiteUrl
    if (-not $siteId) { throw "Site non résolu." }
    
    $lib = Get-AppGraphListDriveId -SiteId $siteId -ListDisplayName $ListTitle
    $listId = $lib.ListId

    Write-Host "`n--- Inspection Détaillée des Colonnes ---" -ForegroundColor Cyan
    $colsUrl = "https://graph.microsoft.com/v1.0/sites/$siteId/lists/$listId/columns"
    $cols = Invoke-MgGraphRequest -Method GET -Uri $colsUrl
    
    $targetCols = $cols.value | Where-Object { $_.name -match "Year|Services|Rubrique|Operations" }
    
    foreach ($c in $targetCols) {
        Write-Host "Propriétés de '$($c.name)' :" -ForegroundColor Yellow
        Write-Host " - DisplayName: $($c.displayName)"
        Write-Host " - ReadOnly: $($c.readOnly)"
        if ($c.choice) {
            Write-Host " - Type: Choice"
            Write-Host " - AllowMultiple: $($c.allowMultipleValues)"
            Write-Host " - Choix valides: $($c.choice.choices -join ', ')"
        }
        elseif ($c.number) {
            Write-Host " - Type: Number"
        }
        else {
            Write-Host " - Type: Autre ($($c.id))"
        }
    }

    Write-Host "`n--- Test Isolation Champs (Focus Choice) ---" -ForegroundColor Cyan

    # On récupère un choix valide pour Services s'il y en a un
    $validChoice = "Choix 1"
    $servicesCol = $targetCols | Where-Object { $_.name -eq "Services" }
    if ($servicesCol -and $servicesCol.choice -and $servicesCol.choice.choices.Count -gt 0) {
        $validChoice = $servicesCol.choice.choices[0]
    }

    $Tests = @(
        @{ Name = "Services (Choix Valide Array)"; Value = @{ "Services" = @($validChoice) } },
        @{ Name = "Services (Choix Valide String)"; Value = @{ "Services" = $validChoice } },
        @{ Name = "Services (Null)"; Value = @{ "Services" = $null } },
        @{ Name = "Services (Empty Array)"; Value = @{ "Services" = @() } }
    )

    foreach ($t in $Tests) {
        Write-Host "Test: $($t.Name) (Valeur: $($t.Value.Services))... " -NoNewline
        try {
            $fieldsUrl = "https://graph.microsoft.com/v1.0/sites/$siteId/lists/$listId/items/$($ItemId)/fields"
            Invoke-MgGraphRequest -Method PATCH -Uri $fieldsUrl -Body $t.Value -ContentType "application/json" -ErrorAction Stop | Out-Null
            Write-Host "SUCCESS" -ForegroundColor Green
        }
        catch {
            Write-Host "FAILED" -ForegroundColor Red
            if ($_.Exception.Message) { Write-Host "   Msg: $($_.Exception.Message)" }
            if ($_.ErrorDetails) { Write-Host "   Détails API: $($_.ErrorDetails.Message)" }
        }
    }
}
catch {
    Write-Host "`n[ERREUR] : $($_.Exception.Message)" -ForegroundColor Red
    if ($_.ErrorDetails) { Write-Host "Détails: $($_.ErrorDetails.Message)" }
}
