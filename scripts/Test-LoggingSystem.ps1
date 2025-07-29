# Script de test pour le système de logging PowerShell Admin ToolBox
# Permet de valider toutes les fonctionnalités du système de logging

#Requires -Version 7.5

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string] $TestLogPath = ".\test-logs",
    
    [Parameter(Mandatory = $false)]
    [switch] $CleanupAfter
)

Write-Host "🧪 Test du système de logging PowerShell Admin ToolBox" -ForegroundColor Cyan
Write-Host "=" * 60 -ForegroundColor Gray

# Fonction utilitaire pour les tests
function Test-Assertion {
    param(
        [string] $TestName,
        [bool] $Condition,
        [string] $ErrorMessage = ""
    )
    
    if ($Condition) {
        Write-Host "✅ $TestName" -ForegroundColor Green
        return $true
    } else {
        Write-Host "❌ $TestName" -ForegroundColor Red
        if ($ErrorMessage) {
            Write-Host "   Error: $ErrorMessage" -ForegroundColor Yellow
        }
        return $false
    }
}

# Résultats des tests
$testResults = @{
    Passed = 0
    Failed = 0
    Total = 0
}

try {
    Write-Host "`n📦 Étape 1 : Import du module Core" -ForegroundColor Yellow
    
    # Test 1 : Import du module
    $testResults.Total++
    try {
        # Import relatif depuis le dossier src
        $modulePath = Join-Path $PSScriptRoot "..\src\Core\PowerShellAdminToolBox.Core.psd1"
        Import-Module $modulePath -Force -ErrorAction Stop
        $moduleImported = $true
    } catch {
        $moduleImported = $false
        $importError = $_.Exception.Message
    }
    
    if (Test-Assertion "Import du module Core" $moduleImported $importError) {
        $testResults.Passed++
    } else {
        $testResults.Failed++
    }
    
    Write-Host "`n🔧 Étape 2 : Initialisation du service de logging" -ForegroundColor Yellow
    
    # Test 2 : Initialisation du service
    $testResults.Total++
    try {
        $loggingService = Initialize-ToolBoxLogging -LogPath $TestLogPath -LogLevel "Debug" -Force
        $serviceInitialized = $loggingService -ne $null
    } catch {
        $serviceInitialized = $false
        $initError = $_.Exception.Message
    }
    
    if (Test-Assertion "Initialisation du service de logging" $serviceInitialized $initError) {
        $testResults.Passed++
    } else {
        $testResults.Failed++
    }
    
    Write-Host "`n📝 Étape 3 : Tests d'écriture de logs" -ForegroundColor Yellow
    
    # Test 3 : Écriture logs différents niveaux
    $testResults.Total++
    try {
        Write-ToolBoxLog -Message "Test message Debug" -Level "Debug"
        Write-ToolBoxLog -Message "Test message Info" -Level "Info"  
        Write-ToolBoxLog -Message "Test message Warning" -Level "Warning"
        Write-ToolBoxLog -Message "Test message Error" -Level "Error"
        $logsWritten = $true
    } catch {
        $logsWritten = $false
        $writeError = $_.Exception.Message
    }
    
    if (Test-Assertion "Écriture logs tous niveaux" $logsWritten $writeError) {
        $testResults.Passed++
    } else {
        $testResults.Failed++
    }
    
    # Test 4 : Console output immédiat
    $testResults.Total++
    Write-Host "   Test affichage console (doit apparaître ci-dessous):" -ForegroundColor Gray
    try {
        Write-ToolBoxLog -Message "Test console output" -Level "Info" -Destinations @{ Console = $true }
        $consoleOutput = $true
    } catch {
        $consoleOutput = $false
        $consoleError = $_.Exception.Message
    }
    
    if (Test-Assertion "Affichage console immédiat" $consoleOutput $consoleError) {
        $testResults.Passed++
    } else {
        $testResults.Failed++
    }
    
    # Test 5 : ModuleName personnalisé
    $testResults.Total++
    try {
        Write-ToolBoxLog -Message "Test avec nom de module" -Level "Info" -ModuleName "TestModule"
        $moduleNameTest = $true
    } catch {
        $moduleNameTest = $false
        $moduleError = $_.Exception.Message
    }
    
    if (Test-Assertion "Log avec nom de module personnalisé" $moduleNameTest $moduleError) {
        $testResults.Passed++
    } else {
        $testResults.Failed++
    }
    
    Write-Host "`n⚙️ Étape 4 : Tests de configuration" -ForegroundColor Yellow
    
    # Test 6 : Changement niveau de log
    $testResults.Total++
    try {
        Set-ToolBoxLogLevel -Level "Warning"
        Write-ToolBoxLog -Message "Ce debug ne devrait pas apparaître" -Level "Debug"
        Write-ToolBoxLog -Message "Ce warning devrait apparaître" -Level "Warning" -Destinations @{ Console = $true }
        $levelChangeTest = $true
    } catch {
        $levelChangeTest = $false
        $levelError = $_.Exception.Message
    }
    
    if (Test-Assertion "Changement niveau de log" $levelChangeTest $levelError) {
        $testResults.Passed++
    } else {
        $testResults.Failed++
    }
    
    # Test 7 : Récupération chemin logs
    $testResults.Total++
    try {
        $logPath = Get-ToolBoxLogPath
        $pathTest = $logPath -eq $TestLogPath
    } catch {
        $pathTest = $false
        $pathError = $_.Exception.Message
    }
    
    if (Test-Assertion "Récupération chemin logs" $pathTest $pathError) {
        $testResults.Passed++
    } else {
        $testResults.Failed++
    }
    
    # Test 8 : Statistiques du service
    $testResults.Total++
    try {
        $stats = Get-ToolBoxLogStatistics
        $statsTest = $stats -ne $null -and $stats.ContainsKey('LogPath')
    } catch {
        $statsTest = $false
        $statsError = $_.Exception.Message
    }
    
    if (Test-Assertion "Récupération statistiques" $statsTest $statsError) {
        $testResults.Passed++
    } else {
        $testResults.Failed++
    }
    
    Write-Host "`n📁 Étape 5 : Vérification fichiers de logs" -ForegroundColor Yellow
    
    # Attendre un peu pour que les logs soient flushés
    Write-Host "   Attente flush des logs (6 secondes)..." -ForegroundColor Gray
    Start-Sleep -Seconds 6
    
    # Test 9 : Existence du dossier de logs
    $testResults.Total++
    $logDirExists = Test-Path $TestLogPath
    
    if (Test-Assertion "Création dossier de logs" $logDirExists) {
        $testResults.Passed++
    } else {
        $testResults.Failed++
    }
    
    # Test 10 : Existence du fichier de log du jour
    $testResults.Total++
    if ($logDirExists) {
        $todayLogFile = Join-Path $TestLogPath "ToolBox_$(Get-Date -Format 'yyyy-MM-dd').log"
        $logFileExists = Test-Path $todayLogFile
        
        if (Test-Assertion "Création fichier de log" $logFileExists) {
            $testResults.Passed++
            
            # Affichage du contenu du fichier pour validation manuelle
            if ($logFileExists) {
                Write-Host "   Contenu du fichier de log:" -ForegroundColor Gray
                $logContent = Get-Content $todayLogFile -Tail 5
                $logContent | ForEach-Object { Write-Host "     $_" -ForegroundColor DarkGray }
            }
        } else {
            $testResults.Failed++
        }
    } else {
        Write-Host "❌ Création fichier de log (dossier inexistant)" -ForegroundColor Red
        $testResults.Failed++
    }
    
    Write-Host "`n📊 Résultats des tests" -ForegroundColor Cyan
    Write-Host "=" * 30 -ForegroundColor Gray
    Write-Host "Total    : $($testResults.Total)" -ForegroundColor White
    Write-Host "Réussis  : $($testResults.Passed)" -ForegroundColor Green  
    Write-Host "Échoués  : $($testResults.Failed)" -ForegroundColor Red
    
    $successRate = [math]::Round(($testResults.Passed / $testResults.Total) * 100, 1)
    Write-Host "Taux     : $successRate%" -ForegroundColor $(if ($successRate -ge 80) { "Green" } else { "Yellow" })
    
    if ($testResults.Failed -eq 0) {
        Write-Host "`n🎉 Tous les tests sont passés ! Le système de logging fonctionne correctement." -ForegroundColor Green
    } else {
        Write-Host "`n⚠️  Certains tests ont échoué. Vérifiez la configuration." -ForegroundColor Yellow
    }
    
    # Affichage des statistiques finales
    Write-Host "`n📈 Statistiques du service:" -ForegroundColor Cyan
    $finalStats = Get-ToolBoxLogStatistics
    $finalStats.GetEnumerator() | Sort-Object Key | ForEach-Object {
        Write-Host "   $($_.Key): $($_.Value)" -ForegroundColor Gray
    }

} catch {
    Write-Host "`n💥 Erreur générale pendant les tests:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Yellow
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
} finally {
    # Nettoyage si demandé
    if ($CleanupAfter -and (Test-Path $TestLogPath)) {
        Write-Host "`n🧹 Nettoyage des fichiers de test..." -ForegroundColor Yellow
        try {
            Remove-Item $TestLogPath -Recurse -Force
            Write-Host "✅ Fichiers de test supprimés" -ForegroundColor Green
        } catch {
            Write-Host "⚠️  Erreur suppression fichiers test: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    
    Write-Host "`n🏁 Test terminé" -ForegroundColor Cyan
}