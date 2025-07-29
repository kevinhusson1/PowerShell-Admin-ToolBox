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
   `powershell
   .\scripts\Test-LoggingSystem.ps1
   `

2. **Importer le module** :
   `powershell
   Import-Module .\src\Core\PowerShellAdminToolBox.Core.psd1
   `

3. **Utiliser le logging** :
   `powershell
   Write-ToolBoxLog -Message "Hello World!" -Level "Info"
   `

## Documentation

Voir le dossier docs/ pour la documentation complète.

## Support

- GitHub Issues : [Lien vers votre repo]
- Documentation : [Lien vers la doc]
