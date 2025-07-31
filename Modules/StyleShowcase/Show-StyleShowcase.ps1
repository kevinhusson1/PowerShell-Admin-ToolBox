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
        
        Write-ToolBoxLog -Level "Info" -Message "Démarrage du module StyleShowcase V1.1 (Vitrine Complète)" -Component "StyleShowcase" -UI $true
        
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
        $powerShellComboBox = $window.FindName("PowerShellComboBox")
        $demoDataGrid = $window.FindName("DemoDataGrid") # NOUVEAU
        $demoListView = $window.FindName("DemoListView") # NOUVEAU
        $blackoutDatePicker = $window.FindName("BlackoutDatePicker") # NOUVEAU
        
        # ÉTAPE 4.1 : Peuplement de la ComboBox via PowerShell
        if ($powerShellComboBox) {
            $services = @("Service: BITS", "Service: Spooler", "Service: Themes", "Service: AudioSrv", "Service: Browser", "Service: CryptSvc", "Service: Dhcp", "Service: Dnscache", "Service: EventLog", "Service: LanmanServer")
            foreach ($service in $services) {
                $item = New-Object System.Windows.Controls.ComboBoxItem
                $item.Content = $service
                $powerShellComboBox.Items.Add($item) | Out-Null
            }
            $powerShellComboBox.SelectedIndex = 0
            Write-ToolBoxLog -Level "Debug" -Message "ComboBox PowerShell peuplée avec $($services.Count) services" -Component "StyleShowcase"
        }
        
        if ($demoDataGrid) {
            $data = @(
                [PSCustomObject]@{Name="Alice"; Email="alice@example.com"; Status="Actif"; LastLogin="2025-07-30"; IsSelected=$false},
                [PSCustomObject]@{Name="Bob"; Email="bob@example.com"; Status="Inactif"; LastLogin="2025-07-29"; IsSelected=$true},
                [PSCustomObject]@{Name="Charlie"; Email="charlie@example.com"; Status="En attente"; LastLogin="2025-07-28"; IsSelected=$false}
            )
            $demoDataGrid.ItemsSource = $data
            Write-ToolBoxLog -Level "Debug" -Message "DataGrid peuplée avec $($data.Count) éléments" -Component "StyleShowcase"
        }

        # ÉTAPE 4.3 : Peuplement du ListView (NOUVEAU)
        if ($demoListView) {
            $files = @(
                [PSCustomObject]@{FileName="rapport.pdf"; Size="1.2 MB"; Type="PDF Document"; Modified="2025-07-25"},
                [PSCustomObject]@{FileName="image.jpg"; Size="350 KB"; Type="JPG File"; Modified="2025-07-26"},
                [PSCustomObject]@{FileName="script.ps1"; Size="20 KB"; Type="PowerShell Script"; Modified="2025-07-27"}
            )
            $demoListView.ItemsSource = $files
            Write-ToolBoxLog -Level "Debug" -Message "ListView peuplée avec $($files.Count) éléments" -Component "StyleShowcase"
        }

        # ÉTAPE 4.4 : Configuration de DatePicker (NOUVEAU)
        if ($blackoutDatePicker) {
            # Exemple: Désactiver les week-ends
            $today = Get-Date
            $startOfWeek = $today.AddDays(-$today.DayOfWeek.value__)
            $endOfWeek = $startOfWeek.AddDays(6) # Samedi

            for ($i = 0; $i -lt 365; $i++) {
                $date = $today.AddDays($i)
                if ($date.DayOfWeek -eq [System.DayOfWeek]::Saturday -or $date.DayOfWeek -eq [System.DayOfWeek]::Sunday) {
                    $blackoutDatePicker.BlackoutDates.Add($date)
                }
            }
            Write-ToolBoxLog -Level "Debug" -Message "DatePicker configuré avec des dates non sélectionnables" -Component "StyleShowcase"
        }

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
                    # Mettez à jour cet exemple XAML avec la structure complète quand elle sera finalisée
                    $exampleXaml = @"
<!-- Exemple d'interface ToolBox V1 avec styles modernes -->
<Window x:Class="MonModule.MainWindow"
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:sys="clr-namespace:System;assembly=mscorlib"
        Style="{DynamicResource ToolBoxWindow}"
        Title="Mon Module ToolBox" Height="600" Width="800">
    
    <!-- ... (Simplifiez ici un extrait représentatif de votre interface complète) ... -->
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        
        <!-- En-tête -->
        <Border Grid.Row="0" Style="{DynamicResource ToolBoxCardFlat}">
            <StackPanel>
                <TextBlock Text="Mon Interface Moderne" Style="{DynamicResource ToolBoxHeaderText}"/>
                <TextBlock Text="Utilise le design system ToolBox V1" Style="{DynamicResource ToolBoxSecondaryText}"/>
            </StackPanel>
        </Border>
        
        <!-- Contenu principal -->
        <ScrollViewer Grid.Row="1">
            <StackPanel Margin="{DynamicResource LargeMargin}">
                
                <GroupBox Header="Formulaire d'exemple" Style="{DynamicResource ToolBoxSection}">
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
                        
                        <Label Grid.Row="0" Grid.Column="0" Content="Nom :" Style="{DynamicResource ToolBoxFormLabel}"/>
                        <TextBox Grid.Row="0" Grid.Column="1" Style="{DynamicResource ToolBoxTextBox}" Margin="0,0,0,8"/>
                        
                        <Label Grid.Row="1" Grid.Column="0" Content="Email :" Style="{DynamicResource ToolBoxFormLabel}"/>
                        <TextBox Grid.Row="1" Grid.Column="1" Style="{DynamicResource ToolBoxTextBox}" Margin="0,0,0,8"/>
                        
                        <Label Grid.Row="2" Grid.Column="0" Content="Type :" Style="{DynamicResource ToolBoxFormLabel}"/>
                        <ComboBox Grid.Row="2" Grid.Column="1" Style="{DynamicResource ToolBoxComboBox}">
                            <ComboBoxItem Content="Option 1"/>
                            <ComboBoxItem Content="Option 2"/>
                        </ComboBox>
                    </Grid>
                </GroupBox>
                
                <Border Style="{DynamicResource ToolBoxCard}">
                    <StackPanel>
                        <TextBlock Text="Options" Style="{DynamicResource ToolBoxSubHeaderText}"/>
                        <CheckBox Content="Notification par email" Style="{DynamicResource ToolBoxCheckBox}"/>
                        <CheckBox Content="Synchronisation automatique" Style="{DynamicResource ToolBoxCheckBox}"/>
                    </StackPanel>
                </Border>

                <DataGrid Height="150" AutoGenerateColumns="False" CanUserAddRows="False">
                    <DataGrid.Columns>
                        <DataGridTextColumn Header="Nom" Binding="{Binding Name}" Width="*"/>
                        <DataGridTextColumn Header="Statut" Binding="{Binding Status}" Width="*"/>
                    </DataGrid.Columns>
                </DataGrid>
                
            </StackPanel>
        </ScrollViewer>
        
        <!-- Actions -->
        <Border Grid.Row="2" Style="{DynamicResource ToolBoxCardFlat}">
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                <Button Content="Annuler" Style="{DynamicResource ToolBoxSecondaryButton}" Margin="0,0,8,0"/>
                <Button Content="Valider" Style="{DynamicResource ToolBoxPrimaryButton}"/>
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
        Write-Host "`n🎨 === VITRINE DE STYLES TOOLBOX V1.1 (Complète) ===" -ForegroundColor Cyan
        Write-Host "🚀 Interface chargée avec succès" -ForegroundColor Green
        Write-Host "📊 Nouveaux contrôles inclus : DataGrid, ListView, TreeView, Menu, etc." -ForegroundColor Yellow
        Write-Host "📝 Design : Moderne, minimaliste et fonctionnel" -ForegroundColor Magenta
        Write-Host "⚡ Compatible : .NET 9.0 / PowerShell 7.5+" -ForegroundColor Magenta
        
        # ÉTAPE 7 : Gestion de la fermeture propre
        $window.Add_Closed({
            Write-ToolBoxLog -Level "Info" -Message "Vitrine de styles V1 fermée" -Component "StyleShowcase" -Console $true -UI $true
            Write-Host "🎨 Vitrine de styles fermée - Merci d'avoir testé !" -ForegroundColor Magenta
        })
        
        # ÉTAPE 8 : Affichage de la fenêtre
        Write-Host "🌟 Ouverture de la vitrine des styles V1..." -ForegroundColor Green
        $window.ShowDialog() | Out-Null
        
    }
    catch {
        $errorMsg = "Erreur lors de l'affichage de la vitrine de styles V1.1 : $($_.Exception.Message)"
        Write-Error $errorMsg
        
        Write-ToolBoxLog -Level "Error" -Message $errorMsg -Component "StyleShowcase" -File $true -Console $true
        
        Write-Host "`n🔧 INFORMATIONS DE DÉPANNAGE :" -ForegroundColor Red
        Write-Host "   • Vérifiez le fichier XAML pour des erreurs de syntaxe." -ForegroundColor Yellow
        Write-Host "   • Assurez-vous que tous les namespaces (comme 'sys') sont déclarés en haut du XAML." -ForegroundColor Yellow
        Write-Host "   • Le XAML est long, l'erreur peut être n'importe où. Regardez le numéro de ligne/colonne exact." -ForegroundColor Yellow
        
        Write-Host "`n📋 INFORMATIONS SYSTÈME :" -ForegroundColor Cyan
        Write-Host "   • PowerShell : $($PSVersionTable.PSVersion)" -ForegroundColor White
        Write-Host "   • OS : $($PSVersionTable.OS)" -ForegroundColor White
        Write-Host "   • Edition : $($PSVersionTable.PSEdition)" -ForegroundColor White
        Write-Host "   • .NET Version : $([System.Environment]::Version)" -ForegroundColor White
        
        Write-Host "`n💡 SOLUTIONS SUGGÉRÉES :" -ForegroundColor Green
        Write-Host "   1. Comparez attentivement les lignes XAML mentionnées dans l'erreur." -ForegroundColor White
        Write-Host "   2. Commentez des sections entières du XAML pour isoler la partie défectueuse." -ForegroundColor White
        Write-Host "   3. Activez les logs `Debug` dans `ToolBoxConfig.json` si ce n'est pas déjà fait." -ForegroundColor White
    }
}

# Auto-exécution pour test autonome
Show-StyleShowcase