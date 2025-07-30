function Show-UserManagement {
    <#
    .SYNOPSIS
        Interface de gestion des utilisateurs AD/Azure AD
    
    .DESCRIPTION
        Module de test pour la gestion des utilisateurs.
        Ce module est désactivé par défaut dans le manifest.
    
    .EXAMPLE
        Show-UserManagement
    #>
    
    [CmdletBinding()]
    param()
    
    try {
        # Logging du démarrage
        if (Get-Command Write-ToolBoxLog -ErrorAction SilentlyContinue) {
            Write-ToolBoxLog -Level "Info" -Message "Tentative de démarrage du module UserManagement" -Component "UserManagement" -File $true
            Write-ToolBoxLog -Level "Private" -Message "Module UserManagement appelé par $($env:USERNAME)" -Component "UserManagement" -File $true
        }
        
        Write-Host "👤 MODULE USERMANAGEMENT - TEST" -ForegroundColor Cyan
        Write-Host "==================================" -ForegroundColor Cyan
        
        Write-Host "`n⚠️  ATTENTION : Ce module est en développement" -ForegroundColor Yellow
        Write-Host "Fonctionnalités à venir :" -ForegroundColor White
        Write-Host "   • Création d'utilisateurs AD/Azure" -ForegroundColor Gray
        Write-Host "   • Désactivation de comptes" -ForegroundColor Gray
        Write-Host "   • Réactivation de comptes" -ForegroundColor Gray
        Write-Host "   • Synchronisation AD <-> Azure" -ForegroundColor Gray
        
        # Test logging avec niveau Private
        if (Get-Command Write-ToolBoxLog -ErrorAction SilentlyContinue) {
            Write-ToolBoxLog -Level "Warning" -Message "Module UserManagement exécuté en mode test" -Component "UserManagement" -File $true -UI $true
            Write-ToolBoxLog -Level "Private" -Message "Accès au module UserManagement autorisé pour $($env:USERNAME)" -Component "UserManagement" -File $true
        }
        
        Write-Host "`n🚧 Module UserManagement en construction..." -ForegroundColor Yellow
        Write-Host "==================================`n" -ForegroundColor Cyan
    }
    catch {
        $errorMsg = "Erreur dans le module UserManagement : $($_.Exception.Message)"
        Write-Error $errorMsg
        
        if (Get-Command Write-ToolBoxLog -ErrorAction SilentlyContinue) {
            Write-ToolBoxLog -Level "Error" -Message $errorMsg -Component "UserManagement" -File $true
        }
    }
}