function Show-TestStyles {
    <#
    .SYNOPSIS
        Module de test pour validation du système de styles
    
    .DESCRIPTION
        Module de référence qui démontre l'utilisation de l'architecture ToolBox.
        Initialise automatiquement l'environnement si nécessaire.
    
    .EXAMPLE
        Show-TestStyles
    #>
    
    [CmdletBinding()]
    param()
    
    try {
        # ÉTAPE 1 : Initialisation universelle de l'environnement ToolBox
        if (-not $Global:ToolBoxEnvironmentInitialized) {
            # Import du module Core si pas déjà fait
            $coreModulePath = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "Core"
            if (Test-Path (Join-Path $coreModulePath "ToolBox.Core.psd1")) {
                Import-Module (Join-Path $coreModulePath "ToolBox.Core.psd1") -Force -Verbose:$false
            } else {
                throw "Module ToolBox.Core introuvable dans : $coreModulePath"
            }
            
            # Initialisation complète de l'environnement
            $initResult = Initialize-ToolBoxEnvironment -ShowDetails
            if (-not $initResult) {
                throw "Échec de l'initialisation de l'environnement ToolBox"
            }
        }
        
        Write-ToolBoxLog -Level "Info" -Message "Démarrage du module TestStyles (Pattern Final Simple)" -Component "TestStyles"
        
        # ÉTAPE 1 : Charger le XAML
        $xamlPath = Join-Path $PSScriptRoot "TestStyles.xaml"
        [xml]$xaml = Get-Content $xamlPath -Raw -Encoding UTF8
        $reader = New-Object System.Xml.XmlNodeReader $xaml
        $window = [Windows.Markup.XamlReader]::Load($reader)
        
        if (-not $window) { throw "Impossible de charger la fenêtre XAML" }
        
        # ÉTAPE 2 : INJECTER nos styles personnalisés
        Import-ToolBoxGlobalStyles -Window $window
        
        # ÉTAPE 3 : Configuration des événements
        $closeButton = $window.FindName("CloseButton")
        $testButton = $window.FindName("TestButton")
        $infoLabel = $window.FindName("InfoLabel")
        
        $closeButton.Add_Click({ $window.Close() })
        
        $testButton.Add_Click({
            $infoLabel.Content = "Test effectué ! Styles personnalisés appliqués."
        })

        # ÉTAPE 4 : Affichage de la fenêtre
        $window.ShowDialog() | Out-Null
    }
    catch {
        $errorMsg = "Erreur dans le module TestStyles : $($_.Exception.Message)"
        if (Get-Command Write-ToolBoxLog -ErrorAction SilentlyContinue) {
            Write-ToolBoxLog -Level "Error" -Message $errorMsg -Component "TestStyles" -File $true -Console $true
        } else {
            Write-Error $errorMsg
        }
    }
}