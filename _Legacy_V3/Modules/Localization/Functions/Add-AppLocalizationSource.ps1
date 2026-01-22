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
        [Parameter(Mandatory)] [string]$FilePath
    )
    
    if (-not (Test-Path $FilePath)) {
        Write-Warning "Fichier introuvable : $FilePath"
        return
    }

    try {
        $jsonContent = Get-Content -Path $FilePath -Raw -Encoding UTF8 | ConvertFrom-Json
        
        # Si le fichier JSON est vide ou invalide, on arrête
        if ($null -eq $jsonContent) { return }

        # --- CORRECTION CRITIQUE ---
        # Si c'est le tout premier fichier, on l'assigne directement (Fast Path).
        if ($null -eq $Global:AppLocalization) {
            $Global:AppLocalization = $jsonContent
            Write-Verbose "Source initiale chargée (Fast Path) : $(Split-Path $FilePath -Leaf)"
        } 
        else {
            # Sinon, on fusionne (Slow Path)
            Merge-PSCustomObject -base $Global:AppLocalization -overlay $jsonContent
            Write-Verbose "Source fusionnée : $(Split-Path $FilePath -Leaf)"
        }

    } catch {
        Write-Warning "Erreur chargement '$FilePath': $($_.Exception.Message)"
    }
}