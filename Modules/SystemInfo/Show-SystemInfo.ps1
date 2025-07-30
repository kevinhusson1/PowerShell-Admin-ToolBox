function Show-SystemInfo {
    <#
    .SYNOPSIS
        Affiche les informations système détaillées
    
    .DESCRIPTION
        Module de test qui affiche les informations système de base
        avec interface XAML simple.
    
    .EXAMPLE
        Show-SystemInfo
    #>
    
    [CmdletBinding()]
    param()
    
    try {
        # Logging du démarrage
        if (Get-Command Write-ToolBoxLog -ErrorAction SilentlyContinue) {
            Write-ToolBoxLog -Level "Info" -Message "Démarrage du module SystemInfo" -Component "SystemInfo" -File $true
        }
        
        Write-Host "🖥️  MODULE SYSTEMINFO - TEST" -ForegroundColor Cyan
        Write-Host "================================" -ForegroundColor Cyan
        
        # Informations de base
        $computerInfo = Get-ComputerInfo
        $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
        
        Write-Host "`n📋 Informations générales :" -ForegroundColor Green
        Write-Host "   Nom de l'ordinateur : $($env:COMPUTERNAME)" -ForegroundColor White
        Write-Host "   Utilisateur actuel  : $($env:USERNAME)" -ForegroundColor White
        Write-Host "   Système d'exploitation : $($osInfo.Caption)" -ForegroundColor White
        Write-Host "   Version : $($osInfo.Version)" -ForegroundColor White
        Write-Host "   Architecture : $($osInfo.OSArchitecture)" -ForegroundColor White
        
        Write-Host "`n💾 Mémoire :" -ForegroundColor Green
        $totalRAM = [math]::Round($osInfo.TotalVisibleMemorySize / 1MB, 2)
        $freeRAM = [math]::Round($osInfo.FreePhysicalMemory / 1MB, 2)
        Write-Host "   RAM Totale : $totalRAM GB" -ForegroundColor White
        Write-Host "   RAM Libre  : $freeRAM GB" -ForegroundColor White
        
        Write-Host "`n🔄 PowerShell :" -ForegroundColor Green
        Write-Host "   Version : $($PSVersionTable.PSVersion)" -ForegroundColor White
        Write-Host "   Edition : $($PSVersionTable.PSEdition)" -ForegroundColor White
        
        # Test du logging avec différents niveaux
        if (Get-Command Write-ToolBoxLog -ErrorAction SilentlyContinue) {
            Write-ToolBoxLog -Level "Debug" -Message "Collecte des informations système terminée" -Component "SystemInfo" -UI $true
            Write-ToolBoxLog -Level "Info" -Message "Module SystemInfo exécuté avec succès" -Component "SystemInfo" -File $true -UI $true
        }
        
        Write-Host "`n✅ Module SystemInfo terminé avec succès !" -ForegroundColor Green
        Write-Host "================================`n" -ForegroundColor Cyan
    }
    catch {
        $errorMsg = "Erreur dans le module SystemInfo : $($_.Exception.Message)"
        Write-Error $errorMsg
        
        if (Get-Command Write-ToolBoxLog -ErrorAction SilentlyContinue) {
            Write-ToolBoxLog -Level "Error" -Message $errorMsg -Component "SystemInfo" -File $true
        }
    }
}