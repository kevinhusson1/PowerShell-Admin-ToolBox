function Show-StyleShowcase {
    <#
    .SYNOPSIS
        Affiche la vitrine des styles ToolBox V1
    
    .DESCRIPTION
        Module de référence qui présente tous les styles, couleurs, contrôles
        et layouts disponibles dans le système de design ToolBox V1.
        
        Cette vitrine sert de :
        - Référence visuelle pour les développeurs
        - Guide de style pour l'équipe
        - Test des styles en temps réel
        - Documentation interactive
        
        VERSION 1 : Design moderne, minimaliste et fonctionnel
        Compatible .NET 9.0 / PowerShell 7.5+
    
    .EXAMPLE
        Show-StyleShowcase
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
        
        Write-ToolBoxLog -Level "Info" -Message "Démarrage du module StyleShowcase V1 (Design Moderne)" -Component "StyleShowcase"
        
        # ÉTAPE 2 : Charger le XAML
        $xamlPath = Join-Path $PSScriptRoot "StyleShowcase.xaml"
        if (-not (Test-Path $xamlPath)) {
            throw "Fichier XAML introuvable : $xamlPath"
        }
        
        [xml]$xaml = Get-Content $xamlPath -Raw -Encoding UTF8
        $reader = New-Object System.Xml.XmlNodeReader $xaml
        $window = [Windows.Markup.XamlReader]::Load($reader)
        
        if (-not $window) { 
            throw "Impossible de charger la fenêtre XAML" 
        }
        
        # ÉTAPE 3 : Injection des styles personnalisés ToolBox
        $stylesResult = Import-ToolBoxGlobalStyles -Window $window
        if (-not $stylesResult) {
            Write-Warning "Impossible de charger les styles personnalisés, utilisation des styles par défaut"
        }
        
        # ÉTAPE 4 : Récupération des contrôles nommés
        $closeButton = $window.FindName("CloseButton")
        $copyXamlButton = $window.FindName("CopyXamlButton")
        $documentationButton = $window.FindName("DocumentationButton")
        $focusTextBox = $window.FindName("FocusTextBox")
        
        # ÉTAPE 5 : Configuration des événements
        
        # Bouton Fermer
        if ($closeButton) {
            $closeButton.Add_Click({
                Write-ToolBoxLog -Level "Info" -Message "Fermeture de la vitrine de styles V1" -Component "StyleShowcase" -UI $true
                $window.Close()
            })
        }
        
        # Bouton Copier XAML
        if ($copyXamlButton) {
            $copyXamlButton.Add_Click({
                try {
                    # Exemple XAML moderne avec les nouveaux styles
                    $exampleXaml = @"
<!-- Exemple d'interface ToolBox V1 avec styles modernes -->
<Window x:Class="MonModule.MainWindow"
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Style="{StaticResource ToolBoxWindow}"
        Title="Mon Module ToolBox" Height="600" Width="800">
    
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        
        <!-- En-tête -->
        <Border Grid.Row="0" Style="{StaticResource ToolBoxCard}">
            <StackPanel>
                <TextBlock Text="Mon Interface Moderne" Style="{StaticResource ToolBoxHeaderText}"/>
                <TextBlock Text="Utilise le design system ToolBox V1" Style="{StaticResource ToolBoxSecondaryText}"/>
            </StackPanel>
        </Border>
        
        <!-- Contenu principal -->
        <ScrollViewer Grid.Row="1">
            <StackPanel Margin="{StaticResource LargeMargin}">
                
                <!-- Section Formulaire -->
                <GroupBox Header="Formulaire d'exemple" Style="{StaticResource ToolBoxSection}">
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="120"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Grid.RowDefinitions>
                            <RowDefinition/>
                            <RowDefinition/>
                            <RowDefinition/>
                        </Grid.RowDefinitions>
                        
                        <Label Grid.Row="0" Grid.Column="0" Content="Nom :" Style="{StaticResource ToolBoxFormLabel}"/>
                        <TextBox Grid.Row="0" Grid.Column="1" Style="{StaticResource ToolBoxTextBox}" Margin="0,0,0,8"/>
                        
                        <Label Grid.Row="1" Grid.Column="0" Content="Email :" Style="{StaticResource ToolBoxFormLabel}"/>
                        <TextBox Grid.Row="1" Grid.Column="1" Style="{StaticResource ToolBoxTextBox}" Margin="0,0,0,8"/>
                        
                        <Label Grid.Row="2" Grid.Column="0" Content="Type :" Style="{StaticResource ToolBoxFormLabel}"/>
                        <ComboBox Grid.Row="2" Grid.Column="1" Style="{StaticResource ToolBoxComboBox}">
                            <ComboBoxItem Content="Option 1"/>
                            <ComboBoxItem Content="Option 2"/>
                        </ComboBox>
                    </Grid>
                </GroupBox>
                
                <!-- Section Options -->
                <Border Style="{StaticResource ToolBoxCard}">
                    <StackPanel>
                        <TextBlock Text="Options" Style="{StaticResource ToolBoxSubHeaderText}"/>
                        <CheckBox Content="Notification par email" Style="{StaticResource ToolBoxCheckBox}"/>
                        <CheckBox Content="Synchronisation automatique" Style="{StaticResource ToolBoxCheckBox}"/>
                    </StackPanel>
                </Border>
                
            </StackPanel>
        </ScrollViewer>
        
        <!-- Actions -->
        <Border Grid.Row="2" Style="{StaticResource ToolBoxCard}">
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                <Button Content="Annuler" Style="{StaticResource ToolBoxSecondaryButton}" Margin="0,0,8,0"/>
                <Button Content="Valider" Style="{StaticResource ToolBoxPrimaryButton}"/>
            </StackPanel>
        </Border>
        
    </Grid>
</Window>
"@
                    [System.Windows.Clipboard]::SetText($exampleXaml)
                    
                    # Notification
                    [System.Windows.MessageBox]::Show(
                        "Exemple de XAML moderne copié dans le presse-papiers !`n`nUtilise les nouveaux styles ToolBox V1 :`n- ToolBoxWindow, ToolBoxCard, ToolBoxSection`n- ToolBoxPrimaryButton, ToolBoxTextBox`n- Et tous les styles de la palette moderne",
                        "ToolBox - Vitrine de Styles V1",
                        [System.Windows.MessageBoxButton]::OK,
                        [System.Windows.MessageBoxImage]::Information
                    )
                    
                    Write-ToolBoxLog -Level "Info" -Message "Exemple XAML V1 copié dans le presse-papiers" -Component "StyleShowcase" -UI $true
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
        
        # Bouton Documentation
        if ($documentationButton) {
            $documentationButton.Add_Click({
                try {
                    # Ouverture de la documentation (adapter l'URL selon vos besoins)
                    $githubUrl = "https://github.com/votre-repo/PowerShell-Admin-ToolBox/wiki/Style-Guide-V1"
                    Start-Process $githubUrl
                    
                    Write-ToolBoxLog -Level "Info" -Message "Ouverture de la documentation des styles V1" -Component "StyleShowcase" -UI $true
                }
                catch {
                    [System.Windows.MessageBox]::Show(
                        "Impossible d'ouvrir la documentation : $($_.Exception.Message)`n`nVeuillez consulter le fichier README.md ou la documentation dans le dépôt GitHub.",
                        "Information",
                        [System.Windows.MessageBoxButton]::OK,
                        [System.Windows.MessageBoxImage]::Information
                    )
                }
            })
        }
        
        # Focus automatique sur le TextBox d'exemple
        if ($focusTextBox) {
            $window.Add_Loaded({
                $focusTextBox.Focus()
            })
        }
        
        # ÉTAPE 6 : Affichage d'informations sur la console
        Write-Host "`n🎨 === VITRINE DE STYLES TOOLBOX V1 ===" -ForegroundColor Cyan
        Write-Host "🚀 Interface chargée avec succès" -ForegroundColor Green
        Write-Host "📊 Fonctionnalités disponibles :" -ForegroundColor Yellow
        Write-Host "   • Palette de couleurs moderne et cohérente" -ForegroundColor White
        Write-Host "   • Styles de typographie hiérarchisés" -ForegroundColor White
        Write-Host "   • Boutons avec états interactifs (hover, pressed, disabled)" -ForegroundColor White
        Write-Host "   • Champs de saisie uniformisés avec focus" -ForegroundColor White
        Write-Host "   • Conteneurs et layouts structurés" -ForegroundColor White
        Write-Host "   • Guide d'utilisation complet" -ForegroundColor White
        Write-Host "   • Exemples XAML prêts à copier" -ForegroundColor White
        Write-Host "📝 Design : Moderne, minimaliste et fonctionnel" -ForegroundColor Magenta
        Write-Host "⚡ Compatible : .NET 9.0 / PowerShell 7.5+" -ForegroundColor Magenta
        
        # ÉTAPE 7 : Gestion de la fermeture propre
        $window.Add_Closed({
            Write-ToolBoxLog -Level "Info" -Message "Vitrine de styles V1 fermée" -Component "StyleShowcase" -File $true -UI $true
            Write-Host "🎨 Vitrine de styles fermée - Merci d'avoir testé !" -ForegroundColor Magenta
        })
        
        # ÉTAPE 8 : Affichage de la fenêtre
        Write-Host "🌟 Ouverture de la vitrine des styles V1..." -ForegroundColor Green
        $window.ShowDialog() | Out-Null
        
    }
    catch {
        $errorMsg = "Erreur lors de l'affichage de la vitrine de styles V1 : $($_.Exception.Message)"
        Write-Error $errorMsg
        
        Write-ToolBoxLog -Level "Error" -Message $errorMsg -Component "StyleShowcase" -File $true
        
        # Affichage d'informations de dépannage
        Write-Host "`n🔧 INFORMATIONS DE DÉPANNAGE :" -ForegroundColor Red
        Write-Host "   • Vérifiez que .NET 9.0 est installé" -ForegroundColor Yellow
        Write-Host "   • Vérifiez que PowerShell 7.5+ est utilisé" -ForegroundColor Yellow
        Write-Host "   • Le fichier XAML doit être présent : $xamlPath" -ForegroundColor Yellow
        Write-Host "   • Les styles GlobalStyles.xaml doivent être accessibles" -ForegroundColor Yellow
        Write-Host "   • Le module ToolBox.Core doit être chargé" -ForegroundColor Yellow
        
        # Informations de versions
        Write-Host "`n📋 INFORMATIONS SYSTÈME :" -ForegroundColor Cyan
        Write-Host "   • PowerShell : $($PSVersionTable.PSVersion)" -ForegroundColor White
        Write-Host "   • OS : $($PSVersionTable.OS)" -ForegroundColor White
        Write-Host "   • Edition : $($PSVersionTable.PSEdition)" -ForegroundColor White
        Write-Host "   • .NET Version : $([System.Environment]::Version)" -ForegroundColor White
        
        # Instructions de résolution
        Write-Host "`n💡 SOLUTIONS SUGGÉRÉES :" -ForegroundColor Green
        Write-Host "   1. Redémarrez PowerShell en tant qu'administrateur" -ForegroundColor White
        Write-Host "   2. Vérifiez l'ExecutionPolicy : Set-ExecutionPolicy RemoteSigned" -ForegroundColor White
        Write-Host "   3. Rechargez le module Core : Import-Module .\Core\ToolBox.Core.psd1 -Force" -ForegroundColor White
        Write-Host "   4. Testez l'initialisation : Initialize-ToolBoxEnvironment -ShowDetails" -ForegroundColor White
    }
}

# Auto-exécution pour test autonome
Show-StyleShowcase