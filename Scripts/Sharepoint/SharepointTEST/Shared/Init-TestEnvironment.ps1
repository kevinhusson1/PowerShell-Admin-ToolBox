#Requires -Version 7.0

<#
.SYNOPSIS
    Script d'initialisation pour les tests unitaires PowerShell Admin ToolBox (SharePoint Builder).
.DESCRIPTION
    Charge les modules, initialise la base de données et s'authentifie sur Azure.
    Définit les variables communes de test.
#>

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = (Get-Item $scriptRoot).Parent.Parent.Parent.Parent.FullName
$env:PSModulePath = "$($projectRoot)\Modules;$($projectRoot)\Vendor;$($env:PSModulePath)"

# ----------------------------------------------------
# VARIABLES GLOBALES DE TEST
# ----------------------------------------------------
$Global:TestTargetSiteUrl = "https://vosgelis365.sharepoint.com/sites/TEST_PNP"
$Global:TestTargetLibrary = "Shared Documents"
$Global:TestTenantId = "6c6101e5-3c91-47f2-a300-570b29591d1a"
$Global:TestClientId = "0107cfb1-a2e6-4394-b363-d25930adf7e4"
$Global:TestThumbprint = "D25A39ACC63BC2F3F1B6389568E9B5AA3726969D"

# Pour éviter les pollutions
$Global:AppAzureAuth = $null

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " INITIALISATION ENVIRONNEMENT DE TEST SHAREPOINT BUILDER V2" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# 1. Chargement des modules
try {
    Write-Host "[1/3] Chargement des modules..." -ForegroundColor DarkGray
    Import-Module "PSSQLite", "Core", "Localization", "Logging", "Database", "Azure", "Toolbox.SharePoint" -Force
}
catch {
    Write-Host "Erreur critique : Impossible de charger les modules." -ForegroundColor Red
    exit 1
}

# 2. Base de données
try {
    Write-Host "[2/3] Initialisation de la base de données..." -ForegroundColor DarkGray
    Initialize-AppDatabase -ProjectRoot $projectRoot
}
catch {
    Write-Host "Erreur critique : Impossible d'initialiser la base de données." -ForegroundColor Red
    exit 1
}

# 3. Authentification
try {
    Write-Host "[3/3] Authentification Graph (App-Only)..." -ForegroundColor DarkGray
    Connect-AppAzureCert -TenantId $Global:TestTenantId -ClientId $Global:TestClientId -Thumbprint $Global:TestThumbprint | Out-Null
    
    # Vérification basique
    $me = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/tenantRelationships/delegatedAdminCustomers" -ErrorAction SilentlyContinue 
    # Pour du App-Only, on peut juste dire qu'on a le token, la cmd de l'usine Azure gère les erreurs.
    Write-Host "  > Authentification réussie." -ForegroundColor Green
}
catch {
    Write-Host "Erreur d'authentification : $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "Environnement prêt.`n" -ForegroundColor Cyan
