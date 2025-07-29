# Script d'installation et configuration du module Core PowerShell Admin ToolBox
# Crée la structure de dossiers et installe les composants de base

#Requires -Version 7.5

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string] $InstallPath = ".\PowerShellAdminToolBox",
    
    [Parameter(Mandatory = $false)]
    [switch] $Force,
    
    [Parameter(Mandatory = $false)]
    [switch] $RunTests
)

Write-Host "🏗️ Installation PowerShell Admin ToolBox - Module Core" -ForegroundColor Cyan
Write-Host "=" * 60 -ForegroundColor Gray

# Fonction utilitaire pour créer des dossiers
function New-DirectoryIfNotExists {
    param([string] $Path)
    
    if (-not (Test-Path $Path)) {
        try {
            New-Item -Path $Path -ItemType Directory -Force | Out-Null
            Write-Host "✅ Dossier créé : $Path" -ForegroundColor Green
            return $true
        } catch {
            Write-Host "❌ Erreur création dossier : $Path - $($_.Exception.Message)" -ForegroundColor Red
            return $false
        }
    } else {
        Write-Host "📁 Dossier existe : $Path" -ForegroundColor Gray
        return $true
    }
}

# Fonction pour créer un fichier avec contenu
function New-FileWithContent {
    param(
        [string] $Path,
        [string] $Content,
        [string] $Description = ""
    )
    
    try {
        if ((Test-Path $Path) -and -not $Force) {
            Write-Host "⚠️  Fichier existe déjà : $Path (utilisez -Force pour écraser)" -ForegroundColor Yellow
            return $false
        }
        
        Set-Content -Path $Path -Value $Content -Encoding UTF8
        Write-Host "✅ Fichier créé : $Path $(if($Description) { "($Description)" })" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "❌ Erreur création fichier : $Path - $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

try {
    Write-Host "`n📁 Étape 1 : Création de la structure de dossiers" -ForegroundColor Yellow
    
    # Structure de base
    $folders = @(
        $InstallPath,
        "$InstallPath\src",
        "$InstallPath\src\Core",
        "$InstallPath\src\Core\Classes", 
        "$InstallPath\src\Core\Functions",
        "$InstallPath\src\Core\Functions\Public",
        "$InstallPath\src\Core\Functions\Private",
        "$InstallPath\src\Modules",
        "$InstallPath\tests",
        "$InstallPath\tests\Unit",
        "$InstallPath\tests\Integration", 
        "$InstallPath\logs",
        "$InstallPath\config",
        "$InstallPath\scripts",
        "$InstallPath\docs"
    )
    
    $foldersCreated = 0
    foreach ($folder in $folders) {
        if (New-DirectoryIfNotExists -Path $folder) {
            $foldersCreated++
        }
    }
    
    Write-Host "`n📄 Étape 2 : Création des fichiers du module Core" -ForegroundColor Yellow
    
    # Note: Dans un vrai scénario, nous copierions les fichiers depuis les artifacts
    # Ici, nous créons des placeholders pour la structure
    
    $coreFiles = @{
        "$InstallPath\src\Core\PowerShellAdminToolBox.Core.psd1" = @"
# Placeholder pour le manifest du module Core
# Dans une implémentation réelle, ce contenu viendrait de l'artifact core_manifest
@{
    RootModule = 'PowerShellAdminToolBox.Core.psm1'
    ModuleVersion = '1.0.0'
    GUID = '12345678-9abc-def0-1234-56789abcdef0'
    Author = 'PowerShell Admin ToolBox Team'
    # ... (contenu complet dans l'artifact)
}
"@
        
        "$InstallPath\src\Core\PowerShellAdminToolBox.Core.psm1" = @"
# Placeholder pour le module principal
# Dans une implémentation réelle, ce contenu viendrait de l'artifact core_module
# Module PowerShellAdminToolBox.Core
# Version: 1.0.0
# ... (contenu complet dans l'artifact)
"@
        
        "$InstallPath\src\Core\Classes\LoggingService.ps1" = @"
# Placeholder pour la classe LoggingService
# Dans une implémentation réelle, ce contenu viendrait de l'artifact logging_service
# Classe LoggingService pour PowerShell Admin ToolBox
# ... (contenu complet dans l'artifact)
"@
        
        "$InstallPath\src\Core\Functions\Public\Write-ToolBoxLog.ps1" = @"
# Placeholder pour les fonctions de logging
# Dans une implémentation réelle, ce contenu viendrait de l'artifact logging_functions
# Fonctions publiques de logging
# ... (contenu complet dans l'artifact)
"@
        
        "$InstallPath\scripts\Test-LoggingSystem.ps1" = @"
# Placeholder pour le script de test
# Dans une implémentation réelle, ce contenu viendrait de l'artifact logging_test  
# Script de test pour le système de logging
# ... (contenu complet dans l'artifact)
"@
    }
    
    $filesCreated = 0
    foreach ($file in $coreFiles.GetEnumerator()) {
        if (New-FileWithContent -Path $file.Key -Content $file.Value) {
            $filesCreated++
        }
    }
    
    Write-Host "`n⚙️ Étape 3 : Configuration initiale" -ForegroundColor Yellow
    
    # Fichier de configuration par défaut
    $configContent = @"
# Configuration PowerShell Admin ToolBox
@{
    Application = @{
        Name = "PowerShell Admin ToolBox"
        Version = "1.0.0"
        LogLevel = "Info"
        LogPath = ".\logs"
    }
    
    UI = @{
        Theme = "Modern"
        Language = "FR"
        WindowStartPosition = "CenterScreen"
    }
    
    Security = @{
        AuthenticationMode = "UserPassword"  # UserPassword | Certificate
        RequireAdminRights = `$true
    }
}
"@
    
    New-FileWithContent -Path "$InstallPath\config\default.config.psd1" -Content $configContent -Description "Configuration par défaut"
    
    # README du projet
    $readmeContent = @"
# PowerShell Admin ToolBox - Module Core

## Installation réussie !

Vous avez installé avec succès le module Core de PowerShell Admin ToolBox.

## Structure créée

- **src/Core/** : Module Core avec système de logging
- **tests/** : Tests unitaires et d'intégration  
- **logs/** : Dossier des fichiers de logs
- **config/** : Fichiers de configuration
- **scripts/** : Scripts utilitaires

## Prochaines étapes

1. **Tester le système de logging** :
   ```powershell
   .\scripts\Test-LoggingSystem.ps1
   ```

2. **Importer le module** :
   ```powershell
   Import-Module .\src\Core\PowerShellAdminToolBox.Core.psd1
   ```

3. **Utiliser le logging** :
   ```powershell
   Write-ToolBoxLog -Message "Hello World!" -Level "Info"
   ```

## Documentation

Voir le dossier `docs/` pour la documentation complète.

## Support

- GitHub Issues : [Lien vers votre repo]
- Documentation : [Lien vers la doc]
"@
    
    New-FileWithContent -Path "$InstallPath\README.md" -Content $readmeContent -Description "Documentation principale"
    
    Write-Host "`n📊 Résumé de l'installation" -ForegroundColor Cyan
    Write-Host "=" * 40 -ForegroundColor Gray
    Write-Host "Dossiers créés  : $foldersCreated/$($folders.Count)" -ForegroundColor White
    Write-Host "Fichiers créés  : $filesCreated/$($coreFiles.Count)" -ForegroundColor White
    Write-Host "Chemin install  : $InstallPath" -ForegroundColor White
    
    # Test optionnel
    if ($RunTests) {
        Write-Host "`n🧪 Exécution des tests de validation" -ForegroundColor Yellow
        
        # Ici, dans un vrai scénario, on exécuterait les tests
        Write-Host "⚠️  Tests automatiques non disponibles en mode setup" -ForegroundColor Yellow
        Write-Host "   Exécutez manuellement : .\scripts\Test-LoggingSystem.ps1" -ForegroundColor Gray
    }
    
    Write-Host "`n🎉 Installation terminée avec succès !" -ForegroundColor Green
    Write-Host "`n📋 Actions recommandées :" -ForegroundColor Cyan
    Write-Host "   1. cd $InstallPath" -ForegroundColor Gray
    Write-Host "   2. .\scripts\Test-LoggingSystem.ps1" -ForegroundColor Gray  
    Write-Host "   3. Import-Module .\src\Core\PowerShellAdminToolBox.Core.psd1" -ForegroundColor Gray
    Write-Host "   4. Write-ToolBoxLog 'Premier test !'" -ForegroundColor Gray
    
} catch {
    Write-Host "`n💥 Erreur pendant l'installation :" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Yellow
    Write-Host "`nTrace :" -ForegroundColor DarkGray
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
    
    exit 1
}

Write-Host "`n🏁 Script d'installation terminé" -ForegroundColor Cyan