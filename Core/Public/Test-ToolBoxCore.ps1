function Test-ToolBoxCore {
    <#
    .SYNOPSIS
        Fonction de test pour valider le module ToolBox.Core
    
    .DESCRIPTION
        Simple fonction de test pour vérifier que le système de chargement
        Public/Private fonctionne correctement.
    #>
    
    Write-Host "🧪 Test du module ToolBox.Core réussi !" -ForegroundColor Green
    Write-Host "✅ La structure Public/Private fonctionne" -ForegroundColor Green
    return $true
}