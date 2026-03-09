#Requires -Version 7.0

<#
.SYNOPSIS
    TEST 01 : Résolution des Ids (Site, List, Drive)
.DESCRIPTION
    Valide la capacité du système à résoudre l'URL du site et le nom de la bibliothèque
    en identifiants Graph natifs depuis les modules de l'application.
#>

$testRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $testRoot "..\Shared\Init-TestEnvironment.ps1")

Write-Host "--- EXECUTION DU TEST 01 : RESOLUTION ID GRAPH ---" -ForegroundColor Yellow

$siteUrl = $Global:TestTargetSiteUrl
$libName = $Global:TestTargetLibrary

try {
    Write-Host "Etape 1 : Résolution du SiteId pour $siteUrl..." -ForegroundColor DarkGray
    $siteId = Get-AppGraphSiteId -SiteUrl $siteUrl
    if (-not $siteId) { throw "SiteId introuvable ou null." }
    Write-Host "  > SiteId résolu : $siteId" -ForegroundColor Green

    Write-Host "Etape 2 : Résolution du DriveId & ListId pour $libName..." -ForegroundColor DarkGray
    $listAndDrive = Get-AppGraphListDriveId -SiteId $siteId -ListDisplayName $libName
    if (-not $listAndDrive -or -not $listAndDrive.DriveId) { throw "Drive introuvable pour la bibliothèque." }
    Write-Host "  > ListId résolu  : $($listAndDrive.ListId)" -ForegroundColor Green
    Write-Host "  > DriveId résolu : $($listAndDrive.DriveId)" -ForegroundColor Green

    Write-Host "`n[TEST REUSSI]" -ForegroundColor Cyan
}
catch {
    Write-Host "`n[ECHEC DU TEST] : $($_.Exception.Message)" -ForegroundColor Red
    if ($_.ErrorDetails) { Write-Host "Détails: $($_.ErrorDetails.Message)" -ForegroundColor Red }
    exit 1
}
