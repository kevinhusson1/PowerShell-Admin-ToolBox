# Modules/UI/Functions/Import-AppXamlTemplate.ps1

<#
.SYNOPSIS
    Charge un fichier XAML, le parse, et remplace les clés de traduction.
.DESCRIPTION
    Cette fonction est le moteur de chargement des interfaces graphiques de l'application.
    Elle lit un fichier XAML brut, recherche toutes les balises de traduction au format ##loc:key.path##,
    les remplace par les valeurs correspondantes du dictionnaire de langue global, puis
    parse le XAML final pour le transformer en un objet WPF utilisable.
.PARAMETER XamlPath
    Le chemin complet vers le fichier .xaml à charger.
.EXAMPLE
    $mainWindow = Import-AppXamlTemplate -XamlPath "$projectRoot\Templates\Layouts\MainLauncher.xaml"
.OUTPUTS
    [System.Windows.Window] ou [System.Windows.ResourceDictionary] - L'objet WPF créé à partir du fichier XAML.
#>
function Import-AppXamlTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$XamlPath
    )

    if (-not (Test-Path $XamlPath)) {
        $errorMsg = Get-AppText -Key 'modules.ui.xaml_file_not_found'
        throw "$errorMsg : $XamlPath"
    }
    
    # On s'assure que les assemblages WPF sont chargés.
    # Le Add-Type est rapide et ne fait rien s'ils sont déjà chargés.
    try { Add-Type -AssemblyName PresentationFramework -ErrorAction Stop } catch {}

    try {
        Write-Verbose (("{0} '{1}'..." -f (Get-AppText 'modules.ui.loading_xaml_file'), $XamlPath))
        $xamlContent = Get-Content -Path $XamlPath -Raw -Encoding UTF8

        if (Get-Command "Get-AppText" -ErrorAction SilentlyContinue) {
            $xamlMatches = $xamlContent | Select-String -Pattern '##loc:(.*?)##' -AllMatches
            
            if ($xamlMatches) {
                Write-Verbose (("{0} {1} {2}" -f (Get-AppText 'modules.ui.replacing_keys_1'), $xamlMatches.Matches.Count, (Get-AppText 'modules.ui.replacing_keys_2')))
                foreach ($match in $xamlMatches.Matches) {
                    $fullTag = $match.Value
                    $key = $match.Groups[1].Value
                    $translatedText = Get-AppText -Key $key
                    # On utilise [System.Security.SecurityElement]::Escape() pour s'assurer que des caractères spéciaux
                    # dans la traduction (comme <, >, &) ne cassent pas le parseur XAML. C'est une sécurité.
                    $xamlContent = $xamlContent.Replace($fullTag, [System.Security.SecurityElement]::Escape($translatedText))
                }
            }
        }

        $xamlObject = [System.Windows.Markup.XamlReader]::Parse($xamlContent)
        return $xamlObject
    }
    catch {
        $errorMsg = Get-AppText -Key 'modules.ui.xaml_parse_error'
        # On utilise Write-Error pour un log propre, et throw pour arrêter l'exécution.
        Write-Error "$errorMsg '$XamlPath' : $($_.Exception.Message)"
        throw
    }
}