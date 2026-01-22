# Modules/Localization/Functions/Initialize-AppLocalization.ps1

<#
.SYNOPSIS
    Charge le fichier de traduction principal en mémoire.
.DESCRIPTION
    Cette fonction lit le fichier de traduction principal (global) depuis le dossier /Localization
    correspondant à la langue demandée. Elle stocke le résultat dans la variable
    $Global:AppLocalization, qui servira de base pour toutes les opérations de traduction.
.PARAMETER ProjectRoot
    Le chemin racine du projet où se trouve le dossier /Localization.
.PARAMETER Language
    Le code de la langue à charger (ex: 'fr-FR', 'en-US').
.EXAMPLE
    Initialize-AppLocalization -ProjectRoot $projectRoot -Language 'fr-FR'
.OUTPUTS
    Aucune.
#>
function Initialize-AppLocalization {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$ProjectRoot,
        [Parameter(Mandatory)] [string]$Language
    )

    # CORRECTION : On initialise à $null pour forcer le "Fast Path" au premier fichier trouvé
    $Global:AppLocalization = $null
    
    Write-Verbose "--- DÉBUT INITIALISATION TRADUCTION ($Language) ---"

    # 1. CHARGEMENT DES TRADUCTIONS GLOBALES
    $globalLangFolder = Join-Path -Path $ProjectRoot -ChildPath "Localization\$Language"
    if (Test-Path $globalLangFolder) {
        $globalFiles = Get-ChildItem -Path $globalLangFolder -Filter "*.json"
        foreach ($file in $globalFiles) {
            Write-Verbose "Source Globale : $($file.Name)"
            Add-AppLocalizationSource -FilePath $file.FullName
        }
    } else {
        $legacyFile = Join-Path -Path $ProjectRoot -ChildPath "Localization\$Language.json"
        if (Test-Path $legacyFile) {
            Write-Verbose "Source Globale (Legacy) : $Language.json"
            Add-AppLocalizationSource -FilePath $legacyFile
        }
    }

    # 2. DÉCOUVERTE AUTOMATIQUE MODULES
    $modulesRoot = Join-Path -Path $ProjectRoot -ChildPath "Modules"
    if (Test-Path $modulesRoot) {
        $modules = Get-ChildItem -Path $modulesRoot -Directory
        foreach ($module in $modules) {
            $moduleLangFile = Join-Path -Path $module.FullName -ChildPath "Localization\$Language.json"
            if (Test-Path $moduleLangFile) {
                Write-Verbose "Source Module [$($module.Name)] : $Language.json"
                Add-AppLocalizationSource -FilePath $moduleLangFile
            }
        }
    }
    Write-Verbose "--- FIN INITIALISATION TRADUCTION ---"
}