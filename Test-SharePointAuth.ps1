# Test-SharePointAuth.ps1

# 1. Setup Environnement
$projectRoot = $PSScriptRoot
$env:PSModulePath = "$($projectRoot)\Modules;$($projectRoot)\Vendor;$($env:PSModulePath)"

Import-Module Core -Force
Import-Module Localization -Force
Import-Module Database -Force
Import-Module Toolbox.SharePoint -Force

# 2. Simulation Config (Comme si la BDD était chargée)
Initialize-AppDatabase -ProjectRoot $projectRoot
Initialize-AppLocalization -ProjectRoot $projectRoot -Language "fr-FR"

# Simulation de la config globale (normalement fait par Get-AppConfiguration)
# REMPLACEZ CECI PAR VOTRE VRAI APP ID AZURE
$RealAppId = "0107cfb1-a2e6-4394-b363-d25930adf7e4" 

$Global:AppConfig = [PSCustomObject]@{
    azure = [PSCustomObject]@{
        authentication = [PSCustomObject]@{
            userAuth = [PSCustomObject]@{
                appId = $RealAppId
            }
        }
    }
}

# 3. Test
Write-Host "--- TEST CONNEXION ---" -ForegroundColor Cyan
$tenant = "vosgelis365.onmicrosoft.com" # On teste le nettoyage

# On passe le ClientId explicitement pour le test
Connect-AppSharePoint -TenantName $tenant -ClientId $RealAppId -Verbose