#Requires -Version 7.0

<#
.SYNOPSIS
    TEST 11 (V1) : Déploiement Visuel pour Validation Utilisateur
.DESCRIPTION
    Execute un déploiement E2E, mais s'arrête délibérément pour laisser
    l'arborescence, le ContentType et les colonnes intacts.
    Permet à l'utilisateur de valider visuellement le résultat.
#>

$testRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $testRoot "..\Shared\Init-TestEnvironment.ps1")

Write-Host "--- EXECUTION DU TEST 11 : DEPLOIEMENT VISUEL ---" -ForegroundColor Yellow

$siteUrl = $Global:TestTargetSiteUrl
$libName = $Global:TestTargetLibrary

try {
    $tplPath = Join-Path $testRoot "..\Data\sp_templates.json"
    $schemaPath = Join-Path $testRoot "..\Data\sp_folder_schemas.json"

    $tplData = Get-Content $tplPath -Raw | ConvertFrom-Json
    $schemaData = Get-Content $schemaPath -Raw | ConvertFrom-Json

    $deployTemplate = $tplData[0]
    $deploySchema = $schemaData[0]

    # Simulation Interface WPF
    $formValues = @{
        "Services"        = "Direction Generale"
        "Rubriques"       = "Administration"
        "DateDeploiement" = (Get-Date).ToString("yyyy-MM-dd")
        "TestBoolean"     = $true
        "Year"            = "2026"
    }

    $rootFolderName = "Validation_Visuelle_$(Get-Date -Format 'yyyyMMdd_HHmmss')"

    # IMPORT MODULE
    $modPath = Join-Path $testRoot "..\..\..\..\Modules\Toolbox.SharePoint\Toolbox.SharePoint.psd1"
    Import-Module $modPath -Force

    Write-Host "Lancement de New-AppSPStructure (Arborescence: $rootFolderName)..." -ForegroundColor White
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

    if (-not $res.Success) { throw "Echec global." }

    Write-Host "`n>> DEPLOIEMENT REUSSI !" -ForegroundColor Green
    Write-Host ">> VOUS POUVEZ ALLER INSPECTER LE RESULTAT SUR SHAREPOINT :" -ForegroundColor Cyan
    Write-Host ">> $siteUrl" -ForegroundColor Cyan
    Write-Host ">> Dossier : $rootFolderName" -ForegroundColor Cyan
    
    Write-Host "`n! ATTENTION : AUCUN NETTOYAGE N'A ETE FAIT !" -ForegroundColor Yellow
    Write-Host "Quand vous aurez fini votre inspection, lancez le script '11_CleanupVisualValidation.ps1'." -ForegroundColor Yellow

    return $res
}
catch {
    Write-Host "`n[ECHEC DU DEPLOIEMENT] : $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
