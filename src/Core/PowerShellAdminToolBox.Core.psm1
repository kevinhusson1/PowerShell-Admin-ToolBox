# Module PowerShellAdminToolBox.Core
# Fournit les services fondamentaux et l'architecture MVVM pour l'application
# Auteur: PowerShell Admin ToolBox Team
# Version: 1.0.0

#Requires -Version 7.5

# Variables globales du module
$script:LoggingService = $null
$script:ModuleInitialized = $false

# Import des classes de base
$ClassFiles = @(
    'LoggingService.ps1',
    'ViewModelBase.ps1', 
    'RelayCommand.ps1'
)

foreach ($ClassFile in $ClassFiles) {
    $ClassPath = Join-Path $PSScriptRoot "Classes\$ClassFile"
    if (Test-Path $ClassPath) {
        try {
            . $ClassPath
            Write-Verbose "Classe chargée : $($ClassFile -replace '\.ps1$', '')"
        }
        catch {
            Write-Error "Erreur chargement classe $ClassFile : $($_.Exception.Message)"
        }
    } else {
        Write-Warning "Classe non trouvée : $ClassPath"
    }
}

# Import des fonctions publiques
$PublicFunctions = Get-ChildItem -Path "$PSScriptRoot\Functions\Public\*.ps1" -ErrorAction SilentlyContinue

foreach ($Function in $PublicFunctions) {
    try {
        . $Function.FullName
        Write-Verbose "Fonction publique chargée : $($Function.BaseName)"
    }
    catch {
        Write-Error "Erreur chargement fonction $($Function.BaseName) : $($_.Exception.Message)"
    }
}

# Import des fonctions privées
$PrivateFunctions = Get-ChildItem -Path "$PSScriptRoot\Functions\Private\*.ps1" -ErrorAction SilentlyContinue

foreach ($Function in $PrivateFunctions) {
    try {
        . $Function.FullName
        Write-Verbose "Fonction privée chargée : $($Function.BaseName)"
    }
    catch {
        Write-Error "Erreur chargement fonction privée $($Function.BaseName) : $($_.Exception.Message)"
    }
}

# Initialisation du module
function Initialize-CoreModule {
    if (-not $script:ModuleInitialized) {
        try {
            # Initialisation du service de logging par défaut
            $script:LoggingService = [LoggingService]::new()
            
            Write-Verbose "Module PowerShellAdminToolBox.Core initialisé avec succès"
            $script:ModuleInitialized = $true
        }
        catch {
            Write-Error "Erreur initialisation module Core : $($_.Exception.Message)"
        }
    }
}

# Nettoyage à la décharge du module
$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
    if ($script:LoggingService) {
        try {
            $script:LoggingService.Dispose()
            Write-Verbose "Service de logging nettoyé"
        }
        catch {
            Write-Warning "Erreur nettoyage logging service : $($_.Exception.Message)"
        }
    }
    $script:ModuleInitialized = $false
}

# Initialisation automatique
Initialize-CoreModule

# Export des fonctions publiques (sera synchronisé avec le manifest)
$ExportedFunctions = $PublicFunctions | ForEach-Object { $_.BaseName }
Export-ModuleMember -Function $ExportedFunctions

Write-Verbose "Module PowerShellAdminToolBox.Core chargé - Version 1.0.0"