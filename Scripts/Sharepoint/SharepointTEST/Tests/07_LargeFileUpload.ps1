#Requires -Version 7.0

<#
.SYNOPSIS
    TEST 07 : Upload de gros fichiers (SMB vers SharePoint)
.DESCRIPTION
    Crée un fichier factice > 10Mo et réalise un upload en "chunked mode"
    via createUploadSession de l'API Graph.
#>

$testRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $testRoot "..\Shared\Init-TestEnvironment.ps1")

Write-Host "--- EXECUTION DU TEST 07 : UPLOAD DE GROS FICHIER ---" -ForegroundColor Yellow

$siteUrl = $Global:TestTargetSiteUrl
$libName = $Global:TestTargetLibrary

try {
    Write-Host "Etape 0 : Préparation..." -ForegroundColor DarkGray
    $siteId = Get-AppGraphSiteId -SiteUrl $siteUrl
    $listAndDrive = Get-AppGraphListDriveId -SiteId $siteId -ListDisplayName $libName
    $driveId = $listAndDrive.DriveId

    $folderName = "TEST07_Racine_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    $parentRes = New-AppGraphFolder -SiteId $siteId -DriveId $driveId -FolderName $folderName -ParentFolderId "root"
    if (-not $parentRes) { throw "Impossible de créer la racine." }

    # --- ETAPE 1 : FICHIER FACTICE ---
    $dummyFilePath = Join-Path $testRoot "..\Data\dummy_10mb.bin"
    Write-Host "Etape 1 : Génération du fichier factice (10 Mo)..." -ForegroundColor DarkGray
    $buffer = New-Object byte[] (10MB)
    (New-Object Random).NextBytes($buffer)
    [System.IO.File]::WriteAllBytes($dummyFilePath, $buffer)
    $fileInfo = Get-Item $dummyFilePath
    $totalBytes = $fileInfo.Length

    # --- ETAPE 2 : CREATE UPLOAD SESSION ---
    Write-Host "Etape 2 : Initialisation de la session d'upload (createUploadSession)..." -ForegroundColor DarkGray
    $remoteFileName = "ArchivageVolumineux.bin"
    $sessionUri = "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$driveId/items/$($parentRes.id)`:/$remoteFileName`:/createUploadSession"
    $sessionBody = @{
        item = @{
            "@microsoft.graph.conflictBehavior" = "replace"
        }
    } | ConvertTo-Json
    
    $sessionRes = Invoke-MgGraphRequest -Method POST -Uri $sessionUri -Body $sessionBody -ContentType "application/json"
    $uploadUrl = $sessionRes.uploadUrl
    if (-not $uploadUrl) { throw "Impossible d'obtenir l'URL d'upload." }

    # --- ETAPE 3 : UPLOAD EN CHUNKS ---
    Write-Host "Etape 3 : Upload par paquets (Chunks de 4 Mo)..." -ForegroundColor DarkGray
    $chunkSize = 4MB
    $fileStream = [System.IO.File]::OpenRead($dummyFilePath)
    $reader = New-Object System.IO.BinaryReader($fileStream)
    
    $startByte = 0
    $finalRes = $null

    try {
        while ($startByte -lt $totalBytes) {
            $bytesToRead = [Math]::Min($chunkSize, $totalBytes - $startByte)
            $chunk = $reader.ReadBytes($bytesToRead)
            
            $endByte = $startByte + $bytesToRead - 1
            $contentRange = "bytes $startByte-$endByte/$totalBytes"
            
            Write-Host "  > Upload du chunk : $contentRange" -ForegroundColor Cyan
            
            $chunkRequest = [System.Net.HttpWebRequest]::Create($uploadUrl)
            $chunkRequest.Method = "PUT"
            $chunkRequest.Headers.Add("Content-Range", $contentRange)
            $chunkRequest.ContentLength = $chunk.Length
            
            $reqStream = $chunkRequest.GetRequestStream()
            $reqStream.Write($chunk, 0, $chunk.Length)
            $reqStream.Close()
            
            $response = $chunkRequest.GetResponse()
            $streamReader = New-Object System.IO.StreamReader($response.GetResponseStream())
            $jsonRes = $streamReader.ReadToEnd() | ConvertFrom-Json
            $streamReader.Close()
            $response.Close()
            
            if ($jsonRes.id) {
                # C'est le dernier chunk, Graph renvoie l'item
                $finalRes = $jsonRes
            }
            $startByte += $bytesToRead
        }
    }
    finally {
        $reader.Close()
        $fileStream.Close()
    }

    if ($finalRes -and $finalRes.id) {
        Write-Host "  > Upload terminé avec succès ! (ID du fichier: $($finalRes.id))" -ForegroundColor Green
    }
    else {
        throw "L'upload n'a pas renvoyé l'item final complet."
    }

    Write-Host "`n>> OPERATION REUSSIE. DEBUT DU ROLLBACK." -ForegroundColor Cyan

    Write-Host "Etape 4 : Rollback - Suppression du fichier local et du dossier SharePoint..." -ForegroundColor DarkGray
    if (Test-Path $dummyFilePath) { Remove-Item $dummyFilePath -Force }
    $delUri = "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$driveId/items/$($parentRes.id)"
    Invoke-MgGraphRequest -Method DELETE -Uri $delUri
    Write-Host "  > Nettoyage terminé." -ForegroundColor Green

    Write-Host "`n[TEST REUSSI]" -ForegroundColor Green
}
catch {
    Write-Host "`n[ECHEC DU TEST] : $($_.Exception.Message)" -ForegroundColor Red
    if ($_.ErrorDetails) { Write-Host "Détails: $($_.ErrorDetails.Message)" -ForegroundColor Red }
    
    # Nettoyage
    $dummyFilePath = Join-Path $testRoot "..\Data\dummy_10mb.bin"
    if (Test-Path $dummyFilePath) { Remove-Item $dummyFilePath -Force -ErrorAction SilentlyContinue }
    
    if ($parentRes -and $parentRes.id) {
        Write-Host "--- TENTATIVE DE SAUVETAGE / NETTOYAGE MANUEL A FAIRE ---" -ForegroundColor Yellow
        Write-Host "Identifiant parent créé : $($parentRes.id)"
    }
    exit 1
}
