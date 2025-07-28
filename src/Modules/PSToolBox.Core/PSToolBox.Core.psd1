#
# Module Manifest for module 'PSToolBox.Core'
#
@{

# Le fichier de script principal du module
RootModule = 'PSToolBox.Core.psm1'

# Version du module. Respectez le versionnage sémantique (Majeur.Mineur.Patch)
ModuleVersion = '0.1.0'

# Un GUID unique pour identifier ce module. Généré une seule fois.
GUID = '35f3d3fb-2709-4ea4-9680-ab1c699ae635' # Exécutez [guid]::NewGuid() dans PowerShell et collez le résultat ici

# Informations sur l'auteur
Author = 'Kevin Husson' # ou votre nom/pseudo
CompanyName = 'N/A'
Copyright = '(c) 2025 Kevin Husson. All rights reserved.'

# Description du module
Description = 'Module principal contenant les fonctions utilitaires partagées pour PowerShell Admin ToolBox.'

# Fonctions à rendre publiques. C'est la surface d'attaque de notre module.
# TOUT le reste sera privé par défaut.
FunctionsToExport = @(
    'Show-ToolBoxWindow',
    'Get-ToolBoxConfig',
    'Write-ToolBoxLog',
    'Show-ToolBoxWindow'
)

# Cmdlets et Alias à exporter (aucun pour l'instant)
CmdletsToExport = @()
AliasesToExport = @()

# Modules requis (si on en avait)
RequiredModules = @()

# Version de PowerShell requise
PowerShellVersion = '7.5'

}