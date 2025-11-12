# Modules/Localization/Functions/Add-AppLocalizationSource.ps1

<#
.SYNOPSIS
    Charge et fusionne un fichier de traduction supplémentaire dans le dictionnaire global.
.DESCRIPTION
    Permet à un composant (comme un script enfant) de charger son propre fichier
    de traduction. Le contenu de ce fichier est fusionné avec le dictionnaire
    $Global:AppLocalization en utilisant la fonction Merge-PSCustomObject. 
    En cas de conflit de clés, les valeurs du nouveau fichier écrasent les valeurs existantes.
.PARAMETER FilePath
    Chemin complet vers le fichier .json de traduction à ajouter.
.EXAMPLE
    # Dans un script enfant, pour charger ses traductions locales
    $scriptLangFile = "$scriptRoot\Localization\$($Global:AppConfig.defaultLanguage).json"
    Add-AppLocalizationSource -FilePath $scriptLangFile
.OUTPUTS
    Aucune.
#>
function Add-AppLocalizationSource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath
    )
    if (-not (Test-Path $FilePath)) {
        $warningMsg = "{0} : {1}" -f (Get-AppText 'modules.localization.source_file_not_found'), $FilePath
        Write-Warning $warningMsg
        return
    }
    try {
        # On s'assure de lire en UTF8 pour la compatibilité
        $scriptLocalization = Get-Content -Path $FilePath -Raw -Encoding UTF8 | ConvertFrom-Json
        
        # On appelle notre fonction d'aide (qui se trouve dans son propre fichier)
        # pour fusionner intelligemment les dictionnaires
        Merge-PSCustomObject -base $Global:AppLocalization -overlay $scriptLocalization

        $logMsg = "{0} '{1}' {2}" -f (Get-AppText 'modules.localization.source_merged_1'), $FilePath, (Get-AppText 'modules.localization.source_merged_2')
        Write-Verbose $logMsg
    } catch {
        $warningMsg = "{0} '{1}': $($_.Exception.Message)" -f (Get-AppText 'modules.localization.merge_error'), $FilePath
        Write-Warning $warningMsg
    }
}