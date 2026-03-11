#Requires -Version 7.0

<#
.SYNOPSIS
    TEST 12 : Test spécifique d'application de métadonnées et d'Append (Choix Multiple)
.DESCRIPTION
    Applique des métadonnées de différents types (Date, Texte, Booléen, Choix) sur
    un dossier précis, puis démontre comment ajouter une valeur à un choix 
    Multiple sans écraser les précédentes.
#>

$testRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $testRoot "..\Shared\Init-TestEnvironment.ps1")

$modPath = Join-Path $testRoot "..\..\..\..\Modules\Toolbox.SharePoint\Toolbox.SharePoint.psd1"
Import-Module $modPath -Force

Write-Host "--- TEST 12 : METADONNEES ET APPEND ---" -ForegroundColor Yellow

$siteUrl = $Global:TestTargetSiteUrl
$libName = $Global:TestTargetLibrary
$folderName = "Validation_Visuelle_20260311_112715"

try {
    $siteId = Get-AppGraphSiteId -SiteUrl $siteUrl
    $listAndDrive = Get-AppGraphListDriveId -SiteId $siteId -ListDisplayName $libName
    $driveId = $listAndDrive.DriveId
    $listId = $listAndDrive.ListId

    Write-Host "Etape 1 : Récupération de l'ID ListItem du dossier $folderName..." -ForegroundColor White
    
    # On cherche le dossier à la racine
    $rootItems = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$driveId/root/children?`$filter=name eq '$folderName'"
    if ($rootItems.value.Count -eq 0) {
        throw "Dossier $folderName introuvable à la racine de la bibliothèque."
    }
    
    $folderItemId = $rootItems.value[0].id
    $liReq = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$driveId/items/$folderItemId/listItem?`$select=id"
    $listItemId = $liReq.id

    Write-Host "  > ListItem ID récupéré : $listItemId" -ForegroundColor Green

    Write-Host "`nEtape 2 : Application initiale des métadonnées..." -ForegroundColor White
    # Pour Graph API, les Choix multiples doivent être envoyés sous forme de tableau (array de strings)
    # Les champs Date doivent être au format ISO 8601
    
    $fieldsStep1 = @{
        "DateDeploiement"     = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
        "Rubriques"           = "Test de rubrique (accentué) éàç&()^$ @ !"
        "TestBoolean"         = $true
        # Notation pour collection de chaines de caractères exigée par Graph Beta pour les Choice multi :
        "Services@odata.type" = "Collection(Edm.String)"
        "Services"            = @("Direction Generale")
        "Year@odata.type"     = "Collection(Edm.String)"
        "Year"                = @("2026")
    }

    $patchBody1 = $fieldsStep1 | ConvertTo-Json -Compress
    Write-Host "  > Envoi du PATCH 1 : $patchBody1" -ForegroundColor DarkGray
    
    Invoke-MgGraphRequest -Method PATCH -Uri "https://graph.microsoft.com/beta/sites/$siteId/lists/$listId/items/$listItemId/fields" -Body $patchBody1 -ContentType "application/json" | Out-Null
    Write-Host "  > Succès de l'application initiale." -ForegroundColor Green

    Start-Sleep -Seconds 3

    Write-Host "`nEtape 3 : Tentative d'Append (Mise à jour sans écrasement) sur Services et Year..." -ForegroundColor White
    <# 
       Dans Graph API (comme dans beaucoup d'API REST), le verbe PATCH sur une propriété de type "Array/Collection"
       remplace totalement la collection existante par la nouvelle. Il n'existe pas d'opérateur "Add" direct
       dans le payload du PATCH de Fields de ListItems.
       La stratégie correcte ("Read-Modify-Write") est de :
       1. Récupérer les valeurs courantes
       2. Ajouter notre nouvelle valeur au tableau si elle n'y est pas
       3. Renvoyer le tableau complet
    #>

    Write-Host "  > 3a. Lecture des champs existants (GET)..." -ForegroundColor Cyan
    $currentFields = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/sites/$siteId/lists/$listId/items/$listItemId/fields?`$select=Services,Year"
    
    # Extraction sécurisée et cast strict en array (Graph retourne parfois une string simple s'il n'y a qu'1 choix, ou un PSObject unrolled)
    [string[]]$currentServices = if ($currentFields.Services) { $currentFields.Services } else { @() }
    [string[]]$currentYears = if ($currentFields.Year) { $currentFields.Year } else { @() }

    # Ajout de nos nouvelles valeurs
    $valServiceToAdd = "RH"
    $valYearToAdd = "2027"

    if ($currentServices -notcontains $valServiceToAdd) { $currentServices += $valServiceToAdd }
    if ($currentYears -notcontains $valYearToAdd) { $currentYears += $valYearToAdd }

    Write-Host "  > 3b. Valeurs fusionnées : Services [$($currentServices -join ', ')] | Year [$($currentYears -join ', ')]" -ForegroundColor Cyan
    Write-Host "  > 3c. Préparation du PATCH 2 avec la nouvelle liste..." -ForegroundColor Cyan
    
    $fieldsStep2 = @{
        "Services@odata.type" = "Collection(Edm.String)"
        "Services"            = $currentServices
        "Year@odata.type"     = "Collection(Edm.String)"
        "Year"                = $currentYears
    }

    $patchBody2 = $fieldsStep2 | ConvertTo-Json -Compress
    Write-Host "  > Envoi du PATCH 2 : $patchBody2" -ForegroundColor DarkGray
    
    Invoke-MgGraphRequest -Method PATCH -Uri "https://graph.microsoft.com/beta/sites/$siteId/lists/$listId/items/$listItemId/fields" -Body $patchBody2 -ContentType "application/json" | Out-Null
    Write-Host "  > Succès de l'Append. Vous pouvez vérifier sur SharePoint." -ForegroundColor Green

}
catch {
    Write-Host "`n[ECHEC] : $($_.Exception.Message)" -ForegroundColor Red
    if ($_.ErrorDetails) { Write-Host "Détails: $($_.ErrorDetails.Message)" -ForegroundColor Red }
}
