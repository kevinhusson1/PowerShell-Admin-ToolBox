#Requires -Version 7.0

<#
.SYNOPSIS
    TEST 08 : Implémentation du Batching (Masse)
.DESCRIPTION
    Prouve l'efficacité de l'endpoint `$batch` de Graph API
    en créant 20 dossiers cibles simultanément dans une seule requête HTTP.
#>

$testRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $testRoot "..\Shared\Init-TestEnvironment.ps1")

Write-Host "--- EXECUTION DU TEST 08 : GRAPH BATCHING (MASSE) ---" -ForegroundColor Yellow

$siteUrl = $Global:TestTargetSiteUrl
$libName = $Global:TestTargetLibrary

try {
    Write-Host "Etape 0 : Préparation..." -ForegroundColor DarkGray
    $siteId = Get-AppGraphSiteId -SiteUrl $siteUrl
    $listAndDrive = Get-AppGraphListDriveId -SiteId $siteId -ListDisplayName $libName
    $driveId = $listAndDrive.DriveId

    $parentFolderName = "TEST08_Batch_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    $parentRes = New-AppGraphFolder -SiteId $siteId -DriveId $driveId -FolderName $parentFolderName -ParentFolderId "root"
    if (-not $parentRes) { throw "Impossible de créer la racine." }
    Write-Host "  > Racine du batch créée: $parentFolderName" -ForegroundColor DarkGray

    # --- ETAPE 1 : PREPARATION DU BATCH ---
    Write-Host "Etape 1 : Préparation de 20 requêtes (Max autorisé par Graph)..." -ForegroundColor White
    $requests = @()
    for ($i = 1; $i -le 20; $i++) {
        $folderName = "SousDossier_Mass_$i"
        $body = @{
            name                                = $folderName
            folder                              = @{}
            "@microsoft.graph.conflictBehavior" = "rename"
        }

        $requests += @{
            id      = $i.ToString()
            method  = "POST"
            url     = "/drives/$driveId/items/$($parentRes.id)/children"
            body    = $body
            headers = @{ "Content-Type" = "application/json" }
        }
    }

    $batchPayload = @{ requests = $requests } | ConvertTo-Json -Depth 5

    # --- ETAPE 2 : ENVOI DU BATCH ---
    Write-Host "Etape 2 : Envoi du Batch (1 seule requête HTTP)..." -ForegroundColor White
    $batchUri = "https://graph.microsoft.com/v1.0/`$batch"
    
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $batchRes = Invoke-MgGraphRequest -Method POST -Uri $batchUri -Body $batchPayload -ContentType "application/json"
    $stopwatch.Stop()
    
    # Validation des réponses
    $successCount = 0
    foreach ($resp in $batchRes.responses) {
        if ($resp.status -ge 200 -and $resp.status -lt 300) {
            $successCount++
        }
        else {
            Write-Host "  > Erreur sur la requête $($resp.id) : $($resp.status)" -ForegroundColor Red
        }
    }

    if ($successCount -eq 20) {
        Write-Host "  > Succès ! 20 dossiers créés en $($stopwatch.ElapsedMilliseconds) ms." -ForegroundColor Green
    }
    else {
        throw "Le batch n'a pas réussi complètement ($successCount/20 succès)."
    }

    Write-Host "`n>> OPERATION REUSSIE. DEBUT DU ROLLBACK." -ForegroundColor Cyan

    Write-Host "Etape 3 : Rollback - Suppression du dossier racine..." -ForegroundColor DarkGray
    $delUri = "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$driveId/items/$($parentRes.id)"
    Invoke-MgGraphRequest -Method DELETE -Uri $delUri
    Write-Host "  > Arborescence supprimée." -ForegroundColor Green

    Write-Host "`n[TEST REUSSI]" -ForegroundColor Green
}
catch {
    Write-Host "`n[ECHEC DU TEST] : $($_.Exception.Message)" -ForegroundColor Red
    if ($_.ErrorDetails) { Write-Host "Détails: $($_.ErrorDetails.Message)" -ForegroundColor Red }
    
    if ($parentRes -and $parentRes.id) {
        Write-Host "--- TENTATIVE DE SAUVETAGE / NETTOYAGE MANUEL A FAIRE ---" -ForegroundColor Yellow
        Write-Host "Identifiant parent créé : $($parentRes.id)"
    }
    exit 1
}
