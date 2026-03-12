# Test de validation de la hiérarchie (GUIDs automatiques)
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = (Get-Item $scriptRoot).Parent.Parent.Parent.FullName
$env:PSModulePath = "$projectRoot\Modules;$env:PSModulePath"
Import-Module "Toolbox.SharePoint" -Force

$json = @"
{
    "Children": [
        {
            "Name": "Dossier1",
            "Children": [
                { "Name": "SousDossier1" }
            ]
        }
    ]
}
"@

Write-Host "--- TEST VALIDATION HIERARCHIE ---" -ForegroundColor Yellow
$plan = Get-AppSPDeploymentPlan -StructureJson $json

$d1 = $plan | Where-Object { $_.Name -eq "Dossier1" }
$s1 = $plan | Where-Object { $_.Name -eq "SousDossier1" }

Write-Host "Dossier1 ID: $($d1.Id)"
Write-Host "SousDossier1 ParentId: $($s1.ParentId)"

if ($s1.ParentId -eq $d1.Id -and $d1.Id -match "^[0-9a-f-]{36}$") {
    Write-Host "[SUCCÈS] La hiérarchie est correctement liée via des GUIDs auto-générés." -ForegroundColor Green
} else {
    Write-Host "[ÉCHEC] La hiérarchie est rompue ou les IDs sont incorrects." -ForegroundColor Red
    exit 1
}
