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
        
        Write-ToolBoxLog -Level "Info" -Message "Démarrage du module TestStyles" -Component "TestStyles" -File $true -UI $true
        
        # ÉTAPE 2 : Chargement des styles globaux
        Write-ToolBoxLog -Level "Debug" -Message "Chargement des styles globaux" -Component "TestStyles" -Console $true
        # Clear-ToolBoxStylesCache  # Temporairement désactivé - fonction non exportée
        $stylesLoaded = Import-ToolBoxGlobalStyles
        
        if ($stylesLoaded) {
            Write-ToolBoxLog -Level "Info" -Message "Styles globaux chargés avec succès" -Component "TestStyles" -Console $true -UI $true
        } else {
            Write-ToolBoxLog -Level "Warning" -Message "Échec du chargement des styles globaux" -Component "TestStyles" -File $true -Console $true
        }
        
        # ÉTAPE 3 : Chargement de l'interface XAML
        $scriptPath = $PSScriptRoot
        if (-not $scriptPath) {
            $scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
        }
        $xamlPath = Join-Path $scriptPath "TestStyles.xaml"
        
        if (-not (Test-Path $xamlPath)) {
            $errorMsg = "Fichier XAML introuvable : $xamlPath"
            Write-ToolBoxLog -Level "Error" -Message $errorMsg -Component "TestStyles" -File $true -Console $true
            return
        }
        
        Write-ToolBoxLog -Level "Debug" -Message "Chargement de l'interface XAML" -Component "TestStyles" -Console $true
        
        [xml]$xaml = Get-Content $xamlPath -Raw -Encoding UTF8
        $reader = New-Object System.Xml.XmlNodeReader $xaml
        $window = [Windows.Markup.XamlReader]::Load($reader)
        
        if (-not $window) {
            throw "Impossible de charger la fenêtre XAML"
        }
        
        # ÉTAPE 4 : Configuration des événements
        $closeButton = $window.FindName("CloseButton")
        $testButton = $window.FindName("TestButton")
        $infoLabel = $window.FindName("InfoLabel")
        
        if ($closeButton) {
            $closeButton.Add_Click({
                Write-ToolBoxLog -Level "Info" -Message "Fermeture du module TestStyles" -Component "TestStyles" -UI $true
                $window.Close()
            })
        }
        
        if ($testButton) {
            $testButton.Add_Click({
                try {
                    if ($infoLabel) {
                        $infoLabel.Content = "Test effectué avec succès ! Styles appliqués."
                    }
                    Write-ToolBoxLog -Level "Info" -Message "Test des styles effectué par l'utilisateur" -Component "TestStyles" -UI $true
                }
                catch {
                    Write-ToolBoxLog -Level "Error" -Message "Erreur lors du test : $($_.Exception.Message)" -Component "TestStyles" -File $true
                }
            })
        }
        
        # ÉTAPE 5 : Informations de statut
        Write-ToolBoxLog -Level "Info" -Message "Interface TestStyles chargée avec succès" -Component "TestStyles" -Console $true
        Write-ToolBoxLog -Level "Debug" -Message "Mode de lancement : $(if ($Global:ToolBoxLaunchedFromLauncher) { 'Launcher' } else { 'Autonome' })" -Component "TestStyles" -Console $true
        Write-ToolBoxLog -Level "Debug" -Message "Fluent Theme disponible : $Global:ToolBoxFluentThemeAvailable" -Component "TestStyles" -Console $true
        
        # Gestion de la fermeture
        $window.Add_Closed({
            Write-ToolBoxLog -Level "Info" -Message "Module TestStyles fermé" -Component "TestStyles" -File $true -UI $true
        })
        
        # ÉTAPE 6 : Affichage de la fenêtre
        Write-ToolBoxLog -Level "Info" -Message "Ouverture de l'interface TestStyles" -Component "TestStyles" -File $true -UI $true
        
        $window.ShowDialog() | Out-Null
        
    }
    catch {
        $errorMsg = "Erreur dans le module TestStyles : $($_.Exception.Message)"
        
        # Logging avec fallback
        if (Get-Command Write-ToolBoxLog -ErrorAction SilentlyContinue) {
            Write-ToolBoxLog -Level "Error" -Message $errorMsg -Component "TestStyles" -File $true -Console $true
        } else {
            Write-Error $errorMsg
        }
    }
}