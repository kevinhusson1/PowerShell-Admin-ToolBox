#Requires -Version 7.0

<#
.SYNOPSIS
    TEST 11 (V2) : Nettoyage Post-Validation Visuelle
.DESCRIPTION
    Script utilitaire détruisant spécifiquement l'arborescence
    "Validation_Visuelle_*" et le ContentType "SBuilder_TestModele" créés
    par le script 11_DeployVisualValidation.ps1.
#>

$testRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $testRoot "..\Shared\Init-TestEnvironment.ps1")

Write-Host "--- NETTOYAGE MANUEL DU TEST 11 ---" -ForegroundColor Yellow

$siteUrl = $Global:TestTargetSiteUrl
$libName = $Global:TestTargetLibrary

try {
    # On récupère le nom du schéma depuis le JSON original pour savoir quoi clean
    $schemaPath = Join-Path $testRoot "..\Data\sp_folder_schemas.json"
    $schemaData = Get-Content $schemaPath -Raw | ConvertFrom-Json
    $deploySchema = $schemaData[0]

    Write-Host "Etape 1 : Connexion à Graph..." -ForegroundColor DarkGray
    $siteId = Get-AppGraphSiteId -SiteUrl $siteUrl
    $listAndDrive = Get-AppGraphListDriveId -SiteId $siteId -ListDisplayName $libName
    $driveId = $listAndDrive.DriveId
    $listId = $listAndDrive.ListId

    Write-Host "Etape 2 : Recherche et suppression des dossiers de Validation..." -ForegroundColor DarkGray
    $libsToClean = @($libName, "Partage")
    
    foreach ($targetLib in $libsToClean) {
        Write-Host "  Nettoyage de la bibliothèque : $targetLib" -ForegroundColor DarkGray
        try {
            $tDrive = Get-AppGraphListDriveId -SiteId $siteId -ListDisplayName $targetLib
            if ($tDrive -and $tDrive.DriveId) {
                $rootItems = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$($tDrive.DriveId)/root/children?`$filter=startswith(name, 'Validation_Visuelle_')"
                if ($rootItems.value.Count -gt 0) {
                    foreach ($d in $rootItems.value) {
                        Invoke-MgGraphRequest -Method DELETE -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$($tDrive.DriveId)/items/$($d.id)"
                        Write-Host "    > Dossier $($d.name) totalement supprimé de $targetLib." -ForegroundColor Green
                    }
                }
            }
        }
        catch {
            Write-Host "    > Erreur lors du nettoyage de $targetLib : $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    Write-Host "Etape 3 : Nettoyage du Schéma 'TestModele'..." -ForegroundColor DarkGray
    $ctSafeName = "SBuilder_" + ($deploySchema.DisplayName -replace '[\\/:*?"<>|#%]', '_')
    $colNames = $deploySchema.ColumnsJson | ConvertFrom-Json | Select-Object -ExpandProperty Name
    
    # Detachement Liste
    try {
        $ctsList = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/lists/$listId/contentTypes"
        $ctListTrouve = $ctsList.value | Where-Object { $_.name -eq $ctSafeName }
        if ($ctListTrouve) { Invoke-MgGraphRequest -Method DELETE -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/lists/$listId/contentTypes/$($ctListTrouve.id)"; Write-Host "  > CT Liste détruit" }
    }
    catch {}

    # Colonnes Liste
    try {
        $colsList = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/lists/$listId/columns"
        foreach ($c in ($colsList.value | Where-Object { $colNames -contains $_.name })) {
            Invoke-MgGraphRequest -Method DELETE -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/lists/$listId/columns/$($c.id)"
        }
    }
    catch {}

    # CT Site
    try {
        $ctsSite = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/contentTypes"
        $ctSiteTrouve = $ctsSite.value | Where-Object { $_.name -eq $ctSafeName }
        if ($ctSiteTrouve) { Invoke-MgGraphRequest -Method DELETE -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/contentTypes/$($ctSiteTrouve.id)"; Write-Host "  > CT Site détruit" }
    }
    catch {}

    # Colonnes Site
    try {
        $colsSite = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/columns"
        foreach ($c in ($colsSite.value | Where-Object { $colNames -contains $_.name })) {
            Invoke-MgGraphRequest -Method DELETE -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/columns/$($c.id)"
        }
    }
    catch {}
    
    Write-Host "  > Schéma purgé." -ForegroundColor Green

    Write-Host "`n[NETTOYAGE REUSSI] L'environnement est prêt pour la suite." -ForegroundColor Green

}
catch {
    Write-Host "`n[ECHEC DU NETTOYAGE] : $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
