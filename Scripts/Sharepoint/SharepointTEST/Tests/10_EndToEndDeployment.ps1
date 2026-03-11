#Requires -Version 7.0

<#
.SYNOPSIS
    TEST 10 : Déploiement End-To-End (E2E)
.DESCRIPTION
    Validation globale du déploiement en utilisant New-AppSPStructure avec
    un vrai cas d'usage tiré des données JSON d'origine.
#>

$testRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $testRoot "..\Shared\Init-TestEnvironment.ps1")

Write-Host "--- EXECUTION DU TEST 10 : DEPLOIEMENT END-TO-END ---" -ForegroundColor Yellow

$siteUrl = $Global:TestTargetSiteUrl
$libName = $Global:TestTargetLibrary

try {
    Write-Host "Etape 0 : Préparation des données JSON mockées..." -ForegroundColor DarkGray
    $tplPath = Join-Path $testRoot "..\Data\sp_templates.json"
    $schemaPath = Join-Path $testRoot "..\Data\sp_folder_schemas.json"

    $tplData = Get-Content $tplPath -Raw | ConvertFrom-Json
    $schemaData = Get-Content $schemaPath -Raw | ConvertFrom-Json

    # On utilise le 'testModele'
    $deployTemplate = $tplData[0]
    $deploySchema = $schemaData[0]

    # Simulation des variables saisies par l'utilisateur dans l'interface WPF
    $formValues = @{
        "Services"        = "Direction Generale"
        "Rubriques"       = "Administration"
        "DateDeploiement" = (Get-Date).ToString("yyyy-MM-dd")
        "TestBoolean"     = $true
        "Year"            = "2026"
    }

    $rootFolderName = "E2E_Test_$(Get-Date -Format 'yyyyMMdd_HHmmss')"

    Write-Host "Etape 1 : Appel complet de New-AppSPStructure..." -ForegroundColor White
    
    # IMPORT du module SharePoint s'il n'est pas déjà dans la session
    $modPath = Join-Path $testRoot "..\..\..\..\Modules\Toolbox.SharePoint\Toolbox.SharePoint.psd1"
    Import-Module $modPath -Force

    $res = New-AppSPStructure -TargetSiteUrl $siteUrl `
        -TargetLibraryName $libName `
        -RootFolderName $rootFolderName `
        -StructureJson $deployTemplate.StructureJson `
        -ClientId $Global:TestClientId `
        -Thumbprint $Global:TestThumbprint `
        -TenantName $Global:TestTenantId `
        -FormValues $formValues `
        -FolderSchemaJson $deploySchema.ColumnsJson `
        -FolderSchemaName $deploySchema.DisplayName

    if (-not $res.Success) {
        Write-Host "Le déploiement a renvoyé une erreur :" -ForegroundColor Red
        $res.Errors | ForEach-Object { Write-Host " - $_" -ForegroundColor Red }
        throw "Failed E2E."
    }

    Write-Host "  > Déploiement réussi !" -ForegroundColor Green
    Write-Host "  > URL finale du dossier : $($res.FinalUrl)" -ForegroundColor Cyan
    Write-Host "  > Logs du deploiment :" -ForegroundColor DarkGray
    $res.Logs | ForEach-Object { Write-Host "    - $_" -ForegroundColor DarkGray }


    Write-Host "`n>> OPERATION REUSSIE. DEBUT DU ROLLBACK." -ForegroundColor Cyan
    
    # Résolution manuelle des IDs pour le rollback
    $siteId = Get-AppGraphSiteId -SiteUrl $siteUrl
    $listAndDrive = Get-AppGraphListDriveId -SiteId $siteId -ListDisplayName $libName
    $driveId = $listAndDrive.DriveId
    $listId = $listAndDrive.ListId

    Write-Host "Etape 2 : Rollback - Recherche et suppression du dossier racine..." -ForegroundColor DarkGray
    $rootItems = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$driveId/root/children?`$filter=name eq '$rootFolderName'"
    
    if ($rootItems.value.Count -gt 0) {
        $itemIdToDel = $rootItems.value[0].id
        Invoke-MgGraphRequest -Method DELETE -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$driveId/items/$itemIdToDel"
        Write-Host "  > Arborescence $rootFolderName totalement supprimée." -ForegroundColor Green
    }
    else {
        Write-Host "  > Cible introuvable pour la suppression." -ForegroundColor Yellow
    }

    Write-Host "Etape 3 : Rollback - Suppression du Type de Contenu et des Colonnes générés..." -ForegroundColor DarkGray
    $ctSafeName = "SBuilder_" + ($deploySchema.DisplayName -replace '[\\/:*?"<>|#%]', '_')
    $colNames = $deploySchema.ColumnsJson | ConvertFrom-Json | Select-Object -ExpandProperty Name
    
    try {
        $ctsList = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/lists/$listId/contentTypes"
        $ctListTrouve = $ctsList.value | Where-Object { $_.name -eq $ctSafeName }
        if ($ctListTrouve) { Invoke-MgGraphRequest -Method DELETE -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/lists/$listId/contentTypes/$($ctListTrouve.id)" }
    }
    catch {}

    try {
        $colsList = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/lists/$listId/columns"
        foreach ($c in ($colsList.value | Where-Object { $colNames -contains $_.name })) {
            Invoke-MgGraphRequest -Method DELETE -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/lists/$listId/columns/$($c.id)"
        }
    }
    catch {}

    try {
        $ctsSite = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/contentTypes"
        $ctSiteTrouve = $ctsSite.value | Where-Object { $_.name -eq $ctSafeName }
        if ($ctSiteTrouve) { Invoke-MgGraphRequest -Method DELETE -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/contentTypes/$($ctSiteTrouve.id)" }
    }
    catch {}

    try {
        $colsSite = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/columns"
        foreach ($c in ($colsSite.value | Where-Object { $colNames -contains $_.name })) {
            Invoke-MgGraphRequest -Method DELETE -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/columns/$($c.id)"
        }
    }
    catch {}
    Write-Host "  > Schéma de test nettoyé." -ForegroundColor Green

    Write-Host "`n[TEST REUSSI]" -ForegroundColor Green

}
catch {
    Write-Host "`n[ECHEC DU TEST] : $($_.Exception.Message)" -ForegroundColor Red
    if ($_.ErrorDetails) { Write-Host "Détails: $($_.ErrorDetails.Message)" -ForegroundColor Red }
    exit 1
}
