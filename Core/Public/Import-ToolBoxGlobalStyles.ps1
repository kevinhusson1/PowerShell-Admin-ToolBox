<#
.SYNOPSIS
    Chargeur de styles globaux pour PowerShell Admin ToolBox

.DESCRIPTION
    Fournit la fonction pour charger les styles globaux dans les fenêtres XAML
    des modules ToolBox.

.NOTES
    Auteur: PowerShell Admin ToolBox Team
    Version: 1.0
    Création: 30 Juillet 2025
#>

function Import-ToolBoxGlobalStyles {
    <#
    .SYNOPSIS
        Charge les styles globaux ToolBox pour l'application
    
    .DESCRIPTION
        Charge le fichier GlobalStyles.xaml dans les ressources globales de l'application
        pour permettre l'utilisation des styles standardisés via DynamicResource.
        
        Cette fonction charge les styles de façon globale, permettant leur utilisation
        dans toutes les fenêtres de l'application.
    
    .PARAMETER Window
        La fenêtre XAML dans laquelle charger les styles (optionnel, pour compatibilité)
    
    .EXAMPLE
        Import-ToolBoxGlobalStyles
        
    .EXAMPLE
        # Dans une fonction Show-ModuleName
        Import-ToolBoxGlobalStyles
        $window = [Windows.Markup.XamlReader]::Load($reader)
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [System.Windows.Window]$Window
    )
    
    try {
        # Détermination du chemin vers GlobalStyles.xaml via les variables globales
        if ($Global:ToolBoxStylesPath) {
            $globalStylesPath = Join-Path $Global:ToolBoxStylesPath "GlobalStyles.xaml"
        } else {
            # Fallback si variables globales pas initialisées
            $scriptRoot = $PSScriptRoot
            if (-not $scriptRoot) {
                $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
            }
            $rootPath = Split-Path -Parent (Split-Path -Parent $scriptRoot)
            $globalStylesPath = Join-Path $rootPath "Styles\GlobalStyles.xaml"
        }
        
        # Vérification de l'existence du fichier
        if (-not (Test-Path $globalStylesPath)) {
            $errorMsg = "Fichier GlobalStyles.xaml introuvable : $globalStylesPath"
            Write-Error $errorMsg
            
            if (Get-Command Write-ToolBoxLog -ErrorAction SilentlyContinue) {
                Write-ToolBoxLog -Level "Error" -Message $errorMsg -Component "StyleLoader" -File $true
            }
            return $false
        }
        
        # Chargement global des styles (comme dans votre méthode précédente)
        Write-Verbose "Chargement global des styles depuis : $globalStylesPath"
        
        # Vérification si les styles sont déjà chargés globalement
        if (-not $Global:ToolBoxStylesXAML) {
            [xml]$Global:ToolBoxStylesXAML = Get-Content $globalStylesPath -Raw -Encoding UTF8
            
            if (-not $Global:ToolBoxStylesXAML) {
                throw "Impossible de charger le fichier GlobalStyles.xaml"
            }
            
            Write-Verbose "Styles ToolBox chargés globalement pour la première fois"
        } else {
            Write-Verbose "Styles ToolBox déjà chargés globalement, réutilisation"
        }
        
        # Création du ResourceDictionary depuis le XML
        $stylesReader = New-Object System.Xml.XmlNodeReader $Global:ToolBoxStylesXAML
        $resourceDictionary = [Windows.Markup.XamlReader]::Load($stylesReader)
        
        if (-not $resourceDictionary) {
            throw "Impossible de créer le ResourceDictionary depuis GlobalStyles.xaml"
        }
        
        # Ajout au niveau application pour disponibilité globale
        if (-not [System.Windows.Application]::Current) {
            # Si pas d'application WPF, on crée une instance minimale
            $app = New-Object System.Windows.Application
        }
        
        $app = [System.Windows.Application]::Current
        if (-not $app.Resources) {
            $app.Resources = New-Object System.Windows.ResourceDictionary
        }
        
        if (-not $app.Resources.MergedDictionaries) {
            $app.Resources.MergedDictionaries = New-Object System.Collections.ObjectModel.Collection[System.Windows.ResourceDictionary]
        }
        
        # Vérification si déjà ajouté pour éviter les doublons
        $alreadyLoaded = $false
        foreach ($dict in $app.Resources.MergedDictionaries) {
            if ($dict.Source -and $dict.Source.ToString().Contains("GlobalStyles")) {
                $alreadyLoaded = $true
                break
            }
        }
        
        if (-not $alreadyLoaded) {
            $app.Resources.MergedDictionaries.Add($resourceDictionary)
            Write-Verbose "ResourceDictionary ajouté aux ressources de l'application"
        }
        
        # Si une fenêtre est fournie, s'assurer qu'elle peut accéder aux ressources
        if ($Window) {
            if (-not $Window.Resources) {
                $Window.Resources = New-Object System.Windows.ResourceDictionary
            }
            # La fenêtre hérite automatiquement des ressources de l'application
        }
        
        # Logging du succès
        $successMsg = "Styles ToolBox chargés avec succès au niveau application"
        Write-Verbose $successMsg
        
        if (Get-Command Write-ToolBoxLog -ErrorAction SilentlyContinue) {
            Write-ToolBoxLog -Level "Debug" -Message $successMsg -Component "StyleLoader"
        }
        
        return $true
    }
    catch {
        $errorMsg = "Erreur lors du chargement global des styles : $($_.Exception.Message)"
        Write-Error $errorMsg
        
        if (Get-Command Write-ToolBoxLog -ErrorAction SilentlyContinue) {
            Write-ToolBoxLog -Level "Error" -Message $errorMsg -Component "StyleLoader" -File $true
        }
        
        return $false
    }
}

function Test-ToolBoxStylesLoading {
    <#
    .SYNOPSIS
        Teste le chargement des styles globaux
    
    .DESCRIPTION
        Fonction de test pour valider que les styles globaux se chargent correctement.
    #>
    
    [CmdletBinding()]
    param()
    
    try {
        Write-Host "🎨 Test du chargement des styles globaux..." -ForegroundColor Cyan
        
        # Création d'une fenêtre de test simple
        Add-Type -AssemblyName PresentationFramework
        Add-Type -AssemblyName PresentationCore
        Add-Type -AssemblyName WindowsBase
        
        $testWindow = New-Object System.Windows.Window
        $testWindow.Title = "Test Styles"
        $testWindow.Width = 300
        $testWindow.Height = 200
        
        # Test du chargement
        $result = Import-ToolBoxGlobalStyles -Window $testWindow
        
        if ($result) {
            Write-Host "✅ Styles chargés avec succès" -ForegroundColor Green
            Write-Host "   Ressources mergées : $($testWindow.Resources.MergedDictionaries.Count)" -ForegroundColor White
        } else {
            Write-Host "❌ Échec du chargement des styles" -ForegroundColor Red
        }
        
        # Nettoyage
        $testWindow.Close()
        
        return $result
    }
    catch {
        Write-Host "❌ Erreur lors du test : $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Les fonctions sont disponibles après dot-sourcing du script