#Requires -Version 7.5

<#
.SYNOPSIS
    Script de vérification des prérequis pour PowerShell Admin ToolBox
    
.DESCRIPTION
    Vérifie que l'environnement dispose de tous les prérequis nécessaires
    pour exécuter PowerShell Admin ToolBox. Affiche des erreurs uniquement
    en cas de problème détecté.
    
.PARAMETER ShowDetails
    Affiche des informations détaillées même en cas de succès
    
.EXAMPLE
    .\Initialize-Environment.ps1
    
.EXAMPLE
    .\Initialize-Environment.ps1 -ShowDetails
    
.NOTES
    Auteur: PowerShell Admin ToolBox Team
    Version: 1.0
    Création: 30 Juillet 2025
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$ShowDetails
)

# Variables globales
$ErrorsFound = @()
$WarningsFound = @()

#region Main Execution

try {
    # Démarrage silencieux sauf en mode ShowDetails
    if ($ShowDetails) {
        Write-Host "🔍 Vérification des prérequis PowerShell Admin ToolBox..." -ForegroundColor Cyan
    }
    
    # 1. Vérification PowerShell 7.5+
    try {
        $currentVersion = $PSVersionTable.PSVersion
        $requiredVersion = [System.Version]"7.5.0"
        
        if ($currentVersion -lt $requiredVersion) {
            $ErrorsFound += "PowerShell version $currentVersion détectée. Version 7.5+ requise."
        } else {
            if ($ShowDetails) {
                Write-Host "✓ PowerShell version $currentVersion validée" -ForegroundColor Green
            }
        }
    }
    catch {
        $ErrorsFound += "Impossible de déterminer la version PowerShell : $($_.Exception.Message)"
    }
    
    # 2. Vérification .NET 9.0
    try {
        $envVersion = [System.Environment]::Version
        
        if ($envVersion.Major -ge 9) {
            if ($ShowDetails) {
                Write-Host "✓ .NET $($envVersion.Major).$($envVersion.Minor).$($envVersion.Build) détecté" -ForegroundColor Green
            }
        } else {
            # Test PowerShell Core comme fallback
            $psRuntime = $PSVersionTable.PSEdition
            if ($psRuntime -eq "Core") {
                if ($ShowDetails) {
                    Write-Host "✓ PowerShell Core détecté (utilise .NET)" -ForegroundColor Green
                }
            } else {
                $WarningsFound += ".NET 9.0 non détecté explicitement"
            }
        }
    }
    catch {
        $ErrorsFound += "Erreur lors de la vérification .NET : $($_.Exception.Message)"
    }
    
    # 3. Vérification ExecutionPolicy
    try {
        $currentPolicy = Get-ExecutionPolicy -Scope CurrentUser
        $restrictivePolicies = @('Restricted', 'AllSigned')
        
        if ($currentPolicy -in $restrictivePolicies) {
            $ErrorsFound += "ExecutionPolicy '$currentPolicy' trop restrictive. Politique 'RemoteSigned' ou 'Unrestricted' recommandée."
        } else {
            if ($ShowDetails) {
                Write-Host "✓ ExecutionPolicy '$currentPolicy' autorise l'exécution de scripts" -ForegroundColor Green
            }
        }
    }
    catch {
        $ErrorsFound += "Impossible de vérifier l'ExecutionPolicy : $($_.Exception.Message)"
    }
    
    # 4. Vérification Windows
    try {
        $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $osVersion = [System.Version]$osInfo.Version
        $osName = $osInfo.Caption
        
        # Windows 10 version 1809 (build 17763) minimum
        $minBuild = 17763
        
        if ($osVersion.Build -lt $minBuild) {
            $ErrorsFound += "Windows build $($osVersion.Build) détecté. Build $minBuild minimum requis (Windows 10 1809+/Windows Server 2019+)."
        } else {
            if ($ShowDetails) {
                Write-Host "✓ $osName (Build $($osVersion.Build)) compatible" -ForegroundColor Green
            }
        }
    }
    catch {
        $WarningsFound += "Impossible de vérifier la version Windows : $($_.Exception.Message)"
    }
    
    # Affichage des résultats
    $hasErrors = $ErrorsFound.Count -gt 0
    $hasWarnings = $WarningsFound.Count -gt 0
    
    # Affichage uniquement si erreurs ou warnings (ou mode ShowDetails)
    if ($hasErrors -or $hasWarnings -or $ShowDetails) {
        
        if ($hasErrors) {
            Write-Host "`n❌ ERREURS DÉTECTÉES :" -ForegroundColor Red
            $ErrorsFound | ForEach-Object {
                Write-Host "   • $_" -ForegroundColor Red
            }
        }
        
        if ($hasWarnings) {
            Write-Host "`n⚠️  AVERTISSEMENTS :" -ForegroundColor Yellow
            $WarningsFound | ForEach-Object {
                Write-Host "   • $_" -ForegroundColor Yellow
            }
        }
        
        if ($ShowDetails -and -not $hasErrors -and -not $hasWarnings) {
            Write-Host "`n✅ Tous les prérequis sont satisfaits" -ForegroundColor Green
        }
    }
    
    # Exit codes
    if ($hasErrors) {
        Write-Host "`n❌ Certains prérequis ne sont pas satisfaits." -ForegroundColor Red
        Write-Host "Veuillez corriger les erreurs avant de lancer PowerShell Admin ToolBox." -ForegroundColor Red
        exit 1
    } else {
        exit 0
    }
}
catch {
    Write-Host "❌ Erreur critique lors de l'initialisation : $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}

#endregion Main Execution