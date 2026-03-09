#Requires -Version 7.0

<#
.SYNOPSIS
    SharePoint TEST (Phase 2 - Architecture de Liaison Virtuelle Graph API)
    Utilise les Cmdlets du module Azure.
#>

$targetSiteUrl       = "https://vosgelis365.sharepoint.com/sites/TEST_PNP"
$targetLibrary       = "Shared Documents"
$parentFolderName    = "Operation_Mere_Test"
$childFolderName     = "DP_Logement_L01"
$operationId         = "ARCHI-777"

$scriptRoot  = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = (Get-Item $scriptRoot).Parent.Parent.Parent.FullName
$env:PSModulePath = "$($projectRoot)\Modules;$($projectRoot)\Vendor;$($env:PSModulePath)"

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " POC : RECHERCHE ET LIAISON INTER-DOSSIERS (Graph API)" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "[INIT] Chargement des modules..." -ForegroundColor DarkGray
Import-Module "PSSQLite", "Core", "Localization", "Logging", "Database", "Azure" -Force

Initialize-AppDatabase -ProjectRoot $projectRoot
$TenantId   = "6c6101e5-3c91-47f2-a300-570b29591d1a"
$ClientId   = "0107cfb1-a2e6-4394-b363-d25930adf7e4"
$Thumbprint = "D25A39ACC63BC2F3F1B6389568E9B5AA3726969D"

Connect-AppAzureCert -TenantId $TenantId -ClientId $ClientId -Thumbprint $Thumbprint | Out-Null
Write-Host "  > Connecté Graph." -ForegroundColor Green

try {
    # ----------------------------------------------------
    # ETAPE 0 : Résolution
    # ----------------------------------------------------
    $siteId = Get-AppGraphSiteId -SiteUrl $targetSiteUrl
    $listAndDrive = Get-AppGraphListDriveId -SiteId $siteId -ListDisplayName $targetLibrary
    $listId = $listAndDrive.ListId
    $driveId = $listAndDrive.DriveId
    Write-Host "  > Site, List & Drive localisés." -ForegroundColor DarkGray

    # ----------------------------------------------------
    # ETAPE 1 : Configuration Taxonomie
    # ----------------------------------------------------
    Write-Host "`n[1/4] Validation de la structure (Colonnes et ContentType)..." -ForegroundColor White
    $colOp = New-AppGraphSiteColumn -SiteId $siteId -Name "Vosgelis_OperationID" -DisplayName "ID Opération" -Type "Text"
    $colStatut = New-AppGraphSiteColumn -SiteId $siteId -Name "Vosgelis_Statut" -DisplayName "Statut Opération" -Type "Choice" -Choices @("Projet", "Ouvert", "Clos")
    $colRef = New-AppGraphSiteColumn -SiteId $siteId -Name "Vosgelis_RefOperation" -DisplayName "Réf Dossier Parent" -Type "Text"

    $ctId = (New-AppGraphContentType -SiteId $siteId -Name "Dossier de Liaison" -Description "Dossier applicatif avec lien de parenté" -Group "Vosgelis App" -BaseId "0x0120" -ColumnIdsToBind @($colOp.id, $colStatut.id, $colRef.id)).id
    Write-Host "  > Type de contenu prêt ($ctId)." -ForegroundColor DarkGray
    
    # FORCAGE : Ajouter le CT à la liste cible pour que les colonnes soient reconnues
    $listCtsUrl = "https://graph.microsoft.com/v1.0/sites/$siteId/lists/$listId/contentTypes"
    $listCtsRes = Invoke-MgGraphRequest -Method GET -Uri $listCtsUrl
    if (-not ($listCtsRes.value | Where-Object { $_.name -eq "Dossier de Liaison" })) {
        Write-Host "  > Ajout du Content Type à la bibliothèque..." -ForegroundColor DarkGray
        Invoke-MgGraphRequest -Method POST -Uri "$listCtsUrl/addCopy" -Body @{ contentType = $ctId } -ContentType "application/json" | Out-Null
    }

    # ----------------------------------------------------
    # ETAPE 2 : Création Dossier Parent
    # ----------------------------------------------------
    Write-Host "`n[2/4] Création du dossier PARENT ($parentFolderName)..." -ForegroundColor White
    $parentRes = New-AppGraphFolder -SiteId $siteId -DriveId $driveId -FolderName $parentFolderName
    
    # Trouver le listItemId du parent
    $parentListItemId = (Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$driveId/items/$($parentRes.id)?`$expand=listItem").listItem.id
    
    Set-AppGraphListItemMetadata -SiteId $siteId -ListId $listId -ListItemId $parentListItemId `
                                 -ContentTypeId $ctId `
                                 -Fields @{ Vosgelis_OperationID = $operationId; Vosgelis_Statut = "Ouvert" }
    Write-Host "  > Dossier parent typé et tagué avec ID: $operationId" -ForegroundColor Green

    # ----------------------------------------------------
    # ETAPE 3 : Création Dossier Enfant/Lié
    # ----------------------------------------------------
    Write-Host "`n[3/4] Création du dossier ENFANT ($childFolderName)..." -ForegroundColor White
    # On le cree volontairement à la racine pour prouver que la recherche ne dépend pas du chemin physique
    $childRes = New-AppGraphFolder -SiteId $siteId -DriveId $driveId -FolderName $childFolderName
    
    $childListItemId = (Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$driveId/items/$($childRes.id)?`$expand=listItem").listItem.id

    Set-AppGraphListItemMetadata -SiteId $siteId -ListId $listId -ListItemId $childListItemId `
                                 -ContentTypeId $ctId `
                                 -Fields @{ Vosgelis_RefOperation = $operationId }
    Write-Host "  > Dossier enfant typé et lié (Vosgelis_RefOperation = $operationId)" -ForegroundColor Green

    # ----------------------------------------------------
    # ETAPE 4 : Preuve de concept -> RECHERCHE INVERSE
    # ----------------------------------------------------
    Write-Host "`n[4/4] Test de la recherche inter-dossiers par TAG..." -ForegroundColor White
    Write-Host "  > Recherche de tous les dossiers liés à l'opération '$operationId'..." -ForegroundColor DarkGray
    
    $linkedFolders = Find-AppGraphFolderByTag -SiteId $siteId -ListId $listId -TagFilters @{ "Vosgelis_RefOperation" = $operationId }
    
    if ($linkedFolders.Count -gt 0) {
        Write-Host "  > SUCCÈS : $($linkedFolders.Count) documents/dossiers trouvés !" -ForegroundColor Green
        foreach ($f in $linkedFolders) {
            # Affichage du WebUrl pour valider (on va chercher le webUrl de l'item Drive via l'id ListItem)
            $driveInfo = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/lists/$listId/items/$($f.id)/driveItem?`$select=webUrl,name"
            Write-Host "    - Nom : $($driveInfo.name) -> $($driveInfo.webUrl)" -ForegroundColor Green
        }
    } else {
        Write-Host "  > ECHEC : Aucun dossier enfant trouvé." -ForegroundColor Red
    }

    Write-Host "`n============================================================" -ForegroundColor Cyan
    Write-Host " TEST ARCHITECTURE TERMINE" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan

} catch {
    Write-Host "`n========================== ÉCHEC ==========================" -ForegroundColor Red
    Write-Host "Message : $($_.Exception.Message)" -ForegroundColor Red
    if ($_.ErrorDetails) { Write-Host "Détails : $($_.ErrorDetails.Message)" -ForegroundColor Red }
}
