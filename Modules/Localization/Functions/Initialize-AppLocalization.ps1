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
        [Parameter(Mandatory)]
        [string]$ProjectRoot,

        [Parameter(Mandatory)]
        [string]$Language
    )
    
    $langFilePath = Join-Path -Path $ProjectRoot -ChildPath "Localization\$Language.json"

    # On initialise toujours la variable globale avec une hashtable vide pour la sécurité
    $Global:AppLocalization = @{}

    if (-not (Test-Path $langFilePath)) {
        $warningMsg = "{0} '{1}'. {2}" -f (Get-AppText 'modules.localization.lang_file_not_found_1'), $Language, (Get-AppText 'modules.localization.lang_file_not_found_2')
        Write-Warning $warningMsg
        return
    }

    try {
        # On lit le fichier en UTF8 et on le charge dans la variable globale
        $Global:AppLocalization = Get-Content -Path $langFilePath -Raw -Encoding UTF8 | ConvertFrom-Json
        
        $logMsg = "{0} '{1}' {2}" -f (Get-AppText 'modules.localization.lang_file_loaded_1'), $Language, (Get-AppText 'modules.localization.lang_file_loaded_2')
        Write-Verbose $logMsg
    }
    catch {
        $errorMsg = Get-AppText -Key 'modules.localization.lang_file_error'
        throw "$errorMsg '$langFilePath': $($_.Exception.Message)"
    }
}