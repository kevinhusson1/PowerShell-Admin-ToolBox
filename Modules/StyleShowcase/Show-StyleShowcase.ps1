function Show-StyleShowcase {
    <#
    .SYNOPSIS
        Affiche la vitrine des styles et contrôles ToolBox
    
    .DESCRIPTION
        Module de référence qui présente tous les styles, couleurs, contrôles
        et layouts disponibles dans le système de design ToolBox.
        
        Cette vitrine sert de :
        - Référence visuelle pour les développeurs
        - Guide de style pour l'équipe
        - Test des styles en temps réel
        - Documentation interactive
    
    .EXAMPLE
        Show-StyleShowcase
    #>
    
    [CmdletBinding()]
    param()
    
    try {
        # Logging du démarrage
        if (Get-Command Write-ToolBoxLog -ErrorAction SilentlyContinue) {
            Write-ToolBoxLog -Level "Info" -Message "Ouverture de la vitrine de styles" -Component "StyleShowcase" -File $true -UI $true
        }
        
        Write-Host "🎨 VITRINE DE STYLES TOOLBOX" -ForegroundColor Magenta
        Write-Host "============================" -ForegroundColor Magenta
        
        # Détermination du chemin XAML
        $scriptPath = $PSScriptRoot
        if (-not $scriptPath) {
            $scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
        }
        $xamlPath = Join-Path $scriptPath "StyleShowcase.xaml"
        
        # Vérification de l'existence du fichier XAML
        if (-not (Test-Path $xamlPath)) {
            $errorMsg = "Fichier XAML introuvable : $xamlPath"
            Write-Error $errorMsg
            if (Get-Command Write-ToolBoxLog -ErrorAction SilentlyContinue) {
                Write-ToolBoxLog -Level "Error" -Message $errorMsg -Component "StyleShowcase" -File $true
            }
            return
        }
        
        # Chargement du XAML
        Write-Host "📄 Chargement de l'interface XAML..." -ForegroundColor Cyan
        
        Add-Type -AssemblyName PresentationFramework
        Add-Type -AssemblyName PresentationCore
        Add-Type -AssemblyName WindowsBase
        
        [xml]$xaml = Get-Content $xamlPath -Raw
        $reader = New-Object System.Xml.XmlNodeReader $xaml
        $window = [Windows.Markup.XamlReader]::Load($reader)
        
        if (-not $window) {
            throw "Impossible de charger la fenêtre XAML"
        }
        
        # Récupération des contrôles nommés
        $closeButton = $window.FindName("CloseButton")
        $copyXamlButton = $window.FindName("CopyXamlButton")
        $documentationButton = $window.FindName("DocumentationButton")
        
        # Gestion des événements
        if ($closeButton) {
            $closeButton.Add_Click({
                if (Get-Command Write-ToolBoxLog -ErrorAction SilentlyContinue) {
                    Write-ToolBoxLog -Level "Info" -Message "Fermeture de la vitrine de styles" -Component "StyleShowcase" -UI $true
                }
                $window.Close()
            })
        }
        
        if ($copyXamlButton) {
            $copyXamlButton.Add_Click({
                try {
                    # Copie d'un exemple de XAML dans le presse-papiers
                    $exampleXaml = @"
<!-- Exemple d'utilisation des styles ToolBox -->
<Window x:Class="MonModule.MainWindow"
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Style="{StaticResource ToolBoxWindow}">
    
    <Window.Resources>
        <ResourceDictionary>
            <ResourceDictionary.MergedDictionaries>
                <ResourceDictionary Source="pack://application:,,,/PowerShell-Admin-ToolBox;component/Styles/GlobalStyles.xaml" />
            </ResourceDictionary.MergedDictionaries>
        </ResourceDictionary>
    </Window.Resources>
    
    <StackPanel Margin="{StaticResource LargeMargin}">
        <TextBlock Text="Mon Interface" Style="{StaticResource HeaderText}"/>
        <TextBox Style="{StaticResource StandardTextBox}" Text="Exemple"/>
        <Button Content="Action" Style="{StaticResource PrimaryButton}"/>
    </StackPanel>
</Window>
"@
                    [System.Windows.Clipboard]::SetText($exampleXaml)
                    
                    # Notification
                    [System.Windows.MessageBox]::Show(
                        "Exemple de XAML copié dans le presse-papiers !",
                        "ToolBox - Vitrine de Styles",
                        [System.Windows.MessageBoxButton]::OK,
                        [System.Windows.MessageBoxImage]::Information
                    )
                    
                    if (Get-Command Write-ToolBoxLog -ErrorAction SilentlyContinue) {
                        Write-ToolBoxLog -Level "Info" -Message "Exemple XAML copié dans le presse-papiers" -Component "StyleShowcase" -UI $true
                    }
                }
                catch {
                    [System.Windows.MessageBox]::Show(
                        "Erreur lors de la copie : $($_.Exception.Message)",
                        "Erreur",
                        [System.Windows.MessageBoxButton]::OK,
                        [System.Windows.MessageBoxImage]::Error
                    )
                }
            })
        }
        
        if ($documentationButton) {
            $documentationButton.Add_Click({
                try {
                    # Ouverture de la documentation GitHub
                    $githubUrl = "https://github.com/votre-repo/PowerShell-Admin-ToolBox/wiki/Style-Guide"
                    Start-Process $githubUrl
                    
                    if (Get-Command Write-ToolBoxLog -ErrorAction SilentlyContinue) {
                        Write-ToolBoxLog -Level "Info" -Message "Ouverture de la documentation de styles" -Component "StyleShowcase" -UI $true
                    }
                }
                catch {
                    [System.Windows.MessageBox]::Show(
                        "Impossible d'ouvrir la documentation : $($_.Exception.Message)",
                        "Erreur",
                        [System.Windows.MessageBoxButton]::OK,
                        [System.Windows.MessageBoxImage]::Warning
                    )
                }
            })
        }
        
        # Affichage d'informations sur la console
        Write-Host "✅ Interface chargée avec succès" -ForegroundColor Green
        Write-Host "📊 Fonctionnalités disponibles :" -ForegroundColor Yellow
        Write-Host "   • Couleurs système et personnalisées" -ForegroundColor White
        Write-Host "   • Styles de typographie" -ForegroundColor White
        Write-Host "   • Boutons et contrôles de formulaire" -ForegroundColor White
        Write-Host "   • Copie d'exemples XAML" -ForegroundColor White
        Write-Host "   • Lien vers documentation" -ForegroundColor White
        
        # Gestion de la fermeture propre
        $window.Add_Closed({
            if (Get-Command Write-ToolBoxLog -ErrorAction SilentlyContinue) {
                Write-ToolBoxLog -Level "Info" -Message "Vitrine de styles fermée" -Component "StyleShowcase" -File $true -UI $true
            }
            Write-Host "🎨 Vitrine de styles fermée" -ForegroundColor Magenta
        })
        
        # Affichage de la fenêtre
        Write-Host "🚀 Ouverture de la vitrine..." -ForegroundColor Green
        $window.ShowDialog() | Out-Null
        
    }
    catch {
        $errorMsg = "Erreur lors de l'affichage de la vitrine de styles : $($_.Exception.Message)"
        Write-Error $errorMsg
        
        if (Get-Command Write-ToolBoxLog -ErrorAction SilentlyContinue) {
            Write-ToolBoxLog -Level "Error" -Message $errorMsg -Component "StyleShowcase" -File $true
        }
        
        # Affichage d'informations de dépannage
        Write-Host "`n🔧 INFORMATIONS DE DÉPANNAGE :" -ForegroundColor Red
        Write-Host "   • Vérifiez que .NET 9 est installé" -ForegroundColor Yellow
        Write-Host "   • Vérifiez que PowerShell 7.5+ est utilisé" -ForegroundColor Yellow
        Write-Host "   • Le fichier XAML doit être présent : $xamlPath" -ForegroundColor Yellow
        Write-Host "   • Les styles globaux doivent être accessibles" -ForegroundColor Yellow
        
        # Informations de versions
        Write-Host "`n📋 INFORMATIONS SYSTÈME :" -ForegroundColor Cyan
        Write-Host "   • PowerShell : $($PSVersionTable.PSVersion)" -ForegroundColor White
        Write-Host "   • OS : $($PSVersionTable.OS)" -ForegroundColor White
        Write-Host "   • Edition : $($PSVersionTable.PSEdition)" -ForegroundColor White
    }
}
Show-StyleShowcase