# ToolBox.Core.psm1 - Structure PowerShell Standard

Write-Host "🔧 Chargement du module ToolBox.Core..." -ForegroundColor Cyan

# Charger les fonctions privées (si le dossier existe)
$privatePath = Join-Path $PSScriptRoot "Private"
if (Test-Path $privatePath) {
    Get-ChildItem -Path "$privatePath\*.ps1" | ForEach-Object {
        Write-Verbose "Chargement fonction privée : $($_.Name)"
        . $_.FullName
    }
}

# Charger les fonctions publiques et les exporter
$publicPath = Join-Path $PSScriptRoot "Public"
if (Test-Path $publicPath) {
    Get-ChildItem -Path "$publicPath\*.ps1" | ForEach-Object {
        Write-Verbose "Chargement fonction publique : $($_.Name)"
        . $_.FullName
        Export-ModuleMember -Function $_.BaseName
    }
} else {
    Write-Warning "Dossier Public introuvable : $publicPath"
}

Write-Host "✅ Module ToolBox.Core chargé avec succès" -ForegroundColor Green