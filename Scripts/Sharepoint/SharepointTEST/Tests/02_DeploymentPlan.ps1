#Requires -Version 7.0

<#
.SYNOPSIS
    TEST 02 : Génération du Plan (Get-AppSPDeploymentPlan)
.DESCRIPTION
    Valide l'aplatissement du JSON hiérarchique en une liste linéaire d'opérations.
    Valide la résolution des tags dynamiques selon un formulaire.
#>

$testRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $testRoot "..\Shared\Init-TestEnvironment.ps1")

Write-Host "--- EXECUTION DU TEST 02 : GENERATION DU PLAN ---" -ForegroundColor Yellow

# Mock des données de saisie de l'utilisateur
$mockFormValues = @{
    Services  = "Informatique"
    Rubriques = "Développement & Tests"
    Year      = "2026"
}

try {
    # On lit le template JSON
    $templatePath = Join-Path $testRoot "..\Data\sp_templates.json"
    $templateJsonArray = Get-Content $templatePath -Raw | ConvertFrom-Json
    
    # On prend le premier template
    $templateStructJson = $templateJsonArray[0].StructureJson
    
    Write-Host "Etape 1 : Appel de Get-AppSPDeploymentPlan..." -ForegroundColor DarkGray
    $plan = Get-AppSPDeploymentPlan -StructureJson $templateStructJson -FormValues $mockFormValues
    
    if (-not $plan -or $plan.Count -eq 0) { throw "Le plan est vide." }
    Write-Host "  > Plan généré avec succès ($($plan.Count) opérations)." -ForegroundColor Green
    
    Write-Host "Etape 2 : Vérification de l'aplatissement..." -ForegroundColor DarkGray
    $foldersCount = ($plan | Where-Object { $_.Type -eq 'Folder' }).Count
    Write-Host "  > Nombre de dossiers : $foldersCount" -ForegroundColor Green
    
    Write-Host "Etape 3 : Vérification de la résolution des tags dynamiques..." -ForegroundColor DarkGray
    # On cherche le dossier /CONCEPTION qui a des tags dynamiques pour voir s'ils ont pris les valeurs du Mock
    $conceptionNode = $plan | Where-Object { $_.Path -eq '/CONCEPTION' }
    if ($conceptionNode -and $conceptionNode.Tags) {
        $rubriqueTag = $conceptionNode.Tags | Where-Object { $_.Name -eq 'Rubriques' }
        $serviceTag = $conceptionNode.Tags | Where-Object { $_.Name -eq 'Services' }
        
        Write-Host "  > Tag 'Rubriques' résolu : $($rubriqueTag.Value)" -ForegroundColor Cyan
        Write-Host "  > Tag 'Services' résolu : $($serviceTag.Value)" -ForegroundColor Cyan
        
        if ($rubriqueTag.Value -ne $mockFormValues.Rubriques) { throw "Erreur de résolution du tag Rubriques." }
    }
    else {
        throw "Noeud /CONCEPTION ou ses tags introuvables."
    }
    
    Write-Host "`n[TEST REUSSI]" -ForegroundColor Green
}
catch {
    Write-Host "`n[ECHEC DU TEST] : $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
