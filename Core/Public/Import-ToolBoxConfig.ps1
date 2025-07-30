<#
.SYNOPSIS
    Module de chargement et validation de la configuration ToolBox

.DESCRIPTION
    Fournit les fonctions pour charger, valider et accéder à la configuration
    centralisée de PowerShell Admin ToolBox.

.NOTES
    Auteur: PowerShell Admin ToolBox Team
    Version: 1.0
    Création: 30 Juillet 2025
#>

# Variable globale pour stocker la configuration
$Global:ToolBoxConfig = $null

function Import-ToolBoxConfig {
    <#
    .SYNOPSIS
        Charge la configuration depuis le fichier JSON
    
    .DESCRIPTION
        Charge et valide la configuration depuis ToolBoxConfig.json.
        Stocke la configuration dans une variable globale pour accès rapide.
    
    .PARAMETER ConfigPath
        Chemin vers le fichier de configuration. Par défaut, cherche dans Config/ToolBoxConfig.json
    
    .PARAMETER Force
        Force le rechargement même si la configuration est déjà chargée
    
    .EXAMPLE
        Import-ToolBoxConfig
        
    .EXAMPLE
        Import-ToolBoxConfig -ConfigPath "C:\Custom\Config.json"
        
    .EXAMPLE
        Import-ToolBoxConfig -Force
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ConfigPath,
        
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )
    
    try {
        # Si déjà chargé et pas de force, retourne la config existante
        if ($Global:ToolBoxConfig -and -not $Force) {
            Write-Verbose "Configuration déjà chargée. Utilisez -Force pour recharger."
            return $Global:ToolBoxConfig
        }
        
        # Détermination du chemin de configuration
        if (-not $ConfigPath) {
            if ($Global:ToolBoxConfigPath) {
                $ConfigPath = Join-Path $Global:ToolBoxConfigPath "ToolBoxConfig.json"
            } else {
                # Fallback si variables globales pas initialisées
                $scriptRoot = $PSScriptRoot
                if (-not $scriptRoot) {
                    $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
                }
                $ConfigPath = Join-Path (Split-Path -Parent (Split-Path -Parent $scriptRoot)) "Config\ToolBoxConfig.json"
            }
        }
        
        # Vérification de l'existence du fichier
        if (-not (Test-Path $ConfigPath)) {
            throw "Fichier de configuration introuvable : $ConfigPath"
        }
        
        Write-Verbose "Chargement de la configuration depuis : $ConfigPath"
        
        # Lecture et parsing du JSON
        $jsonContent = Get-Content -Path $ConfigPath -Raw -Encoding UTF8
        $config = $jsonContent | ConvertFrom-Json
        
        # Validation basique de la structure
        if (-not $config) {
            throw "Impossible de parser le fichier JSON"
        }
        
        # Vérification des sections critiques
        $requiredSections = @('Application', 'Authentication', 'Modules')
        foreach ($section in $requiredSections) {
            if (-not $config.PSObject.Properties.Name.Contains($section)) {
                throw "Section manquante dans la configuration : $section"
            }
        }
        
        # Stockage dans la variable globale
        $Global:ToolBoxConfig = $config
        
        Write-Verbose "Configuration chargée avec succès"
        Write-Verbose "Version application : $($config.Application.Version)"
        Write-Verbose "Modules configurés : $($config.Modules.PSObject.Properties.Name -join ', ')"
        
        return $Global:ToolBoxConfig
    }
    catch {
        $errorMsg = "Erreur lors du chargement de la configuration : $($_.Exception.Message)"
        Write-Error $errorMsg
        throw $errorMsg
    }
}

function Get-ToolBoxConfig {
    <#
    .SYNOPSIS
        Récupère la configuration chargée ou une section spécifique
    
    .DESCRIPTION
        Retourne la configuration complète ou une section spécifique.
        Charge automatiquement la configuration si elle n'est pas déjà en mémoire.
    
    .PARAMETER Section
        Section spécifique à retourner (ex: 'Authentication', 'Modules', etc.)
    
    .PARAMETER Property
        Propriété spécifique dans une section (ex: 'ClientID' dans 'Authentication.Azure')
    
    .EXAMPLE
        Get-ToolBoxConfig
        # Retourne la configuration complète
        
    .EXAMPLE
        Get-ToolBoxConfig -Section "Authentication"
        # Retourne uniquement la section Authentication
        
    .EXAMPLE
        Get-ToolBoxConfig -Section "Authentication" -Property "Azure"
        # Retourne uniquement Authentication.Azure
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Section,
        
        [Parameter(Mandatory = $false)]
        [string]$Property
    )
    
    try {
        # Chargement automatique si pas déjà fait
        if (-not $Global:ToolBoxConfig) {
            Write-Verbose "Configuration non chargée, chargement automatique..."
            Import-ToolBoxConfig
        }
        
        $config = $Global:ToolBoxConfig
        
        # Retour de la configuration complète
        if (-not $Section) {
            return $config
        }
        
        # Vérification de l'existence de la section
        if (-not $config.PSObject.Properties.Name.Contains($Section)) {
            throw "Section '$Section' introuvable dans la configuration"
        }
        
        $sectionData = $config.$Section
        
        # Retour de la section complète
        if (-not $Property) {
            return $sectionData
        }
        
        # Vérification de l'existence de la propriété
        if (-not $sectionData.PSObject.Properties.Name.Contains($Property)) {
            throw "Propriété '$Property' introuvable dans la section '$Section'"
        }
        
        return $sectionData.$Property
    }
    catch {
        $errorMsg = "Erreur lors de la récupération de la configuration : $($_.Exception.Message)"
        Write-Error $errorMsg
        throw $errorMsg
    }
}

function Test-ToolBoxConfig {
    <#
    .SYNOPSIS
        Valide la configuration chargée
    
    .DESCRIPTION
        Effectue une validation basique de la configuration pour s'assurer
        qu'elle est lisible et contient les éléments essentiels.
    
    .EXAMPLE
        Test-ToolBoxConfig
    #>
    
    [CmdletBinding()]
    param()
    
    try {
        Write-Verbose "Validation de la configuration ToolBox..."
        
        # Chargement si nécessaire
        if (-not $Global:ToolBoxConfig) {
            Import-ToolBoxConfig
        }
        
        $config = $Global:ToolBoxConfig
        $errors = @()
        $warnings = @()
        
        # Tests basiques de structure
        $requiredSections = @{
            'Application' = @('Version', 'LogLevel')
            'Authentication' = @('Azure')
            'Modules' = @()
        }
        
        foreach ($section in $requiredSections.Keys) {
            if (-not $config.PSObject.Properties.Name.Contains($section)) {
                $errors += "Section manquante : $section"
                continue
            }
            
            $requiredProps = $requiredSections[$section]
            foreach ($prop in $requiredProps) {
                if (-not $config.$section.PSObject.Properties.Name.Contains($prop)) {
                    $warnings += "Propriété manquante dans $section : $prop"
                }
            }
        }
        
        # Tests spécifiques Azure
        if ($config.Authentication.Azure) {
            $azureConfig = $config.Authentication.Azure
            $requiredAzureProps = @('ClientID', 'TenantID', 'CertificateThumbprint')
            
            foreach ($prop in $requiredAzureProps) {
                if (-not $azureConfig.PSObject.Properties.Name.Contains($prop) -or 
                    [string]::IsNullOrWhiteSpace($azureConfig.$prop)) {
                    $warnings += "Configuration Azure incomplète : $prop"
                }
            }
        }
        
        # Résultats
        $result = [PSCustomObject]@{
            IsValid = ($errors.Count -eq 0)
            Errors = $errors
            Warnings = $warnings
            ConfigVersion = $config.Application.Version
            LoadedSections = $config.PSObject.Properties.Name
        }
        
        if ($errors.Count -gt 0) {
            Write-Warning "Erreurs de configuration détectées :"
            $errors | ForEach-Object { Write-Warning "  • $_" }
        }
        
        if ($warnings.Count -gt 0) {
            Write-Warning "Avertissements de configuration :"
            $warnings | ForEach-Object { Write-Warning "  • $_" }
        }
        
        if ($result.IsValid) {
            Write-Verbose "Configuration validée avec succès"
        }
        
        return $result
    }
    catch {
        $errorMsg = "Erreur lors de la validation de la configuration : $($_.Exception.Message)"
        Write-Error $errorMsg
        throw $errorMsg
    }
}

# Les fonctions sont automatiquement disponibles après dot-sourcing du script
# Pour utiliser : . .\Core\ConfigLoader.ps1