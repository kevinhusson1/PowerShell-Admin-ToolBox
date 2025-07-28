<#
.SYNOPSIS
    Charge, prépare et affiche une fenêtre WPF en utilisant le patron de conception MVVM.
... (le reste de l'aide est inchangé) ...
#>
function Show-ToolBoxWindow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ViewPath,

        [Parameter(Mandatory = $true)]
        [object]$ViewModel,
        
        [Parameter(Mandatory = $false)]
        [string]$WindowIconPath,

        [Parameter(Mandatory = $false)]
        [switch]$IsDialog
    )

    try {
        # Étape 1 : Valider les chemins et charger les assemblys
        if (-not (Test-Path $ViewPath)) {
            throw "Le fichier de la vue est introuvable : '$ViewPath'"
        }
        Add-Type -AssemblyName PresentationFramework

        # Étape 2 : Charger le dictionnaire de styles global EN PREMIER
        $moduleRoot = (Get-Module PSToolBox.Core).ModuleBase
        $stylesPath = Join-Path $moduleRoot "../../PSToolBox/Assets/Styles/Global.xaml"
        $stylesPath = [System.IO.Path]::GetFullPath($stylesPath)
        if (-not (Test-Path $stylesPath)) { throw "Le fichier de styles global est introuvable : '$stylesPath'" }
        
        $stylesContent = Get-Content -Path $stylesPath -Raw
        $stringReaderStyles = New-Object System.IO.StringReader($stylesContent)
        $xmlReaderStyles = [System.Xml.XmlReader]::Create($stringReaderStyles)
        $globalStyles = [System.Windows.Markup.XamlReader]::Load($xmlReaderStyles)
        if (-not $globalStyles) { throw "Le fichier de styles n'a pas pu être chargé." }

        # Étape 3 : Charger la vue
        $viewContent = Get-Content -Path $ViewPath -Raw
        $stringReader = New-Object System.IO.StringReader($viewContent)
        $xmlReader = [System.Xml.XmlReader]::Create($stringReader)
        $window = [System.Windows.Markup.XamlReader]::Load($xmlReader)
        if (-not $window) { throw "Le chargement du XAML a échoué pour la vue : '$ViewPath'" }

        # --- NOUVELLE LOGIQUE POUR L'ICÔNE ---
        if (-not ([string]::IsNullOrWhiteSpace($WindowIconPath))) {
            if (Test-Path $WindowIconPath) {
                try {
                    $iconUri = New-Object System.Uri($WindowIconPath, [System.UriKind]::Absolute)
                    $window.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create($iconUri)
                }
                catch {
                    Write-ToolBoxLog -Message "Impossible de charger l'icône de la fenêtre : $WindowIconPath. Erreur : $($_.Exception.Message)" -Level WARNING
                }
            }
            else {
                Write-ToolBoxLog -Message "Le fichier d'icône de fenêtre est introuvable : $WindowIconPath" -Level WARNING
            }
        }

        # Étape 4 : Fusionner les styles et lier le ViewModel
        $window.Resources.MergedDictionaries.Add($globalStyles)
        $window.DataContext = $ViewModel

        # Étape 5 : Afficher la fenêtre
        if ($IsDialog) {
            return $window.ShowDialog()
        }
        else {
            $window.Show()
        }
    }
    catch {
        $errorMessage = "Erreur lors de l'affichage de la fenêtre '$ViewPath': $($_.Exception.Message)"
        if ($_.Exception.InnerException) { $errorMessage += " | InnerException: $($_.Exception.InnerException.Message)" }
        Write-ToolBoxLog -Message $errorMessage -Level ERROR
        throw $errorMessage
    }
}