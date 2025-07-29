# Clone et setup
git clone https://github.com/username/PowerShellAdminToolBox.git
cd PowerShellAdminToolBox
git remote add upstream https://github.com/original-owner/PowerShellAdminToolBox.git

# Synchronisation régulière
git fetch upstream
git checkout main
git merge upstream/main
git push origin main

# Développement feature
git checkout -b feature/nouvelle-fonctionnalite
# ... développement ...
git add .
git commit -m "[FEAT] Description de la fonctionnalité"
git push origin feature/nouvelle-fonctionnalite

# Après merge de la PR
git checkout main
git pull upstream main
git branch -d feature/nouvelle-fonctionnalite
git push origin --delete feature/nouvelle-fonctionnalite
```

### Conventions de Commit
```bash
# Format : [TYPE] Description courte (max 72 caractères)
# 
# Description détaillée optionnelle
# - Point spécifique 1
# - Point spécifique 2
#
# Fixes #123 (référence issue si applicable)

# Types de commit
[FEAT]     # Nouvelle fonctionnalité
[FIX]      # Correction de bug
[REFACTOR] # Refactorisation sans changement fonctionnel
[DOCS]     # Documentation uniquement
[STYLE]    # Formatage, indentation, etc.
[TEST]     # Ajout ou modification de tests
[PERF]     # Amélioration performance
[SECURITY] # Correction sécurité
[BUILD]    # Système de build, dépendances
[CI]       # Configuration intégration continue

# Exemples
[FEAT] Ajout module gestion utilisateurs Azure AD
[FIX] Correction crash lors du chargement des modules
[REFACTOR] Amélioration architecture MVVM ViewModelBase
[DOCS] Documentation API module UserManagement
```

## 🧪 Tests et Qualité Code

### Configuration Pester
```powershell
# Test de configuration environnement
function Test-DevelopmentEnvironment {
    $issues = @()
    
    # Vérification PowerShell
    if ($PSVersionTable.PSVersion.Major -lt 7 -or 
        ($PSVersionTable.PSVersion.Major -eq 7 -and $PSVersionTable.PSVersion.Minor -lt 5)) {
        $issues += "PowerShell 7.5+ requis. Version actuelle : $($PSVersionTable.PSVersion)"
    }
    
    # Vérification .NET
    try {
        $dotnetVersion = dotnet --version
        $majorVersion = [int]($dotnetVersion.Split('.')[0])
        if ($majorVersion -lt 9) {
            $issues += ".NET 9.0+ requis. Version actuelle : $dotnetVersion"
        }
    } catch {
        $issues += ".NET Runtime non trouvé"
    }
    
    # Vérification modules
    $requiredModules = @('Pester', 'PSScriptAnalyzer', 'Microsoft.Graph', 'PnP.PowerShell')
    foreach ($module in $requiredModules) {
        if (-not (Get-Module -ListAvailable -Name $module)) {
            $issues += "Module manquant : $module"
        }
    }
    
    if ($issues.Count -eq 0) {
        Write-Host "✅ Environnement de développement OK" -ForegroundColor Green
        return $true
    } else {
        Write-Host "❌ Problèmes détectés :" -ForegroundColor Red
        $issues | ForEach-Object { Write-Host "   - $_" -ForegroundColor Yellow }
        return $false
    }
}

# Configuration Pester pour le projet
$PesterConfiguration = [PesterConfiguration]::new()
$PesterConfiguration.Run.Path = @(
    ".\tests\Unit\*.Tests.ps1",
    ".\tests\Integration\*.Tests.ps1",
    ".\tests\UI\*.Tests.ps1"
)
$PesterConfiguration.Output.Verbosity = "Detailed"
$PesterConfiguration.CodeCoverage.Enabled = $true
$PesterConfiguration.CodeCoverage.Path = @(
    ".\src\Core\**\*.ps1",
    ".\src\Modules\**\*.ps1"
)
$PesterConfiguration.CodeCoverage.OutputFormat = "JaCoCo"
$PesterConfiguration.CodeCoverage.OutputPath = ".\reports\coverage.xml"
$PesterConfiguration.TestResult.Enabled = $true
$PesterConfiguration.TestResult.OutputFormat = "NUnit2.5"
$PesterConfiguration.TestResult.OutputPath = ".\reports\testresults.xml"
```

### Script de Tests Complets
```powershell
# Test-ProjectQuality.ps1
[CmdletBinding()]
param(
    [switch] $RunTests = $true,
    [switch] $RunAnalysis = $true,
    [switch] $CheckCoverage = $true,
    [int] $MinCoveragePercent = 80
)

function Test-ProjectQuality {
    param($Parameters)
    
    $results = @{
        Tests = @{ Passed = $false; Details = "" }
        Analysis = @{ Passed = $false; Details = "" }
        Coverage = @{ Passed = $false; Details = "" }
        Overall = $false
    }
    
    Write-Host "🧪 Exécution des tests qualité projet..." -ForegroundColor Cyan
    
    # Tests Pester
    if ($Parameters.RunTests) {
        Write-Host "`n📋 Exécution tests Pester..." -ForegroundColor Yellow
        
        try {
            $pesterResult = Invoke-Pester -Configuration $PesterConfiguration
            
            if ($pesterResult.FailedCount -eq 0) {
                $results.Tests.Passed = $true
                $results.Tests.Details = "✅ $($pesterResult.PassedCount) tests passés"
                Write-Host $results.Tests.Details -ForegroundColor Green
            } else {
                $results.Tests.Details = "❌ $($pesterResult.FailedCount) tests échoués sur $($pesterResult.TotalCount)"
                Write-Host $results.Tests.Details -ForegroundColor Red
            }
        } catch {
            $results.Tests.Details = "❌ Erreur exécution tests : $($_.Exception.Message)"
            Write-Host $results.Tests.Details -ForegroundColor Red
        }
    }
    
    # Analyse PSScriptAnalyzer
    if ($Parameters.RunAnalysis) {
        Write-Host "`n🔍 Analyse PSScriptAnalyzer..." -ForegroundColor Yellow
        
        $analysisFiles = Get-ChildItem -Path ".\src" -Include "*.ps1", "*.psm1" -Recurse
        $analysisResults = @()
        
        foreach ($file in $analysisFiles) {
            $issues = Invoke-ScriptAnalyzer -Path $file.FullName -Settings ".\PSScriptAnalyzerSettings.psd1"
            if ($issues) {
                $analysisResults += $issues
            }
        }
        
        if ($analysisResults.Count -eq 0) {
            $results.Analysis.Passed = $true
            $results.Analysis.Details = "✅ Aucun problème détecté par PSScriptAnalyzer"
            Write-Host $results.Analysis.Details -ForegroundColor Green
        } else {
            $errorCount = ($analysisResults | Where-Object Severity -eq "Error").Count
            $warningCount = ($analysisResults | Where-Object Severity -eq "Warning").Count
            $infoCount = ($analysisResults | Where-Object Severity -eq "Information").Count
            
            $results.Analysis.Details = "❌ PSScriptAnalyzer : $errorCount erreurs, $warningCount avertissements, $infoCount infos"
            Write-Host $results.Analysis.Details -ForegroundColor Red
            
            # Affichage détails erreurs
            $analysisResults | Where-Object Severity -eq "Error" | ForEach-Object {
                Write-Host "   ERROR: $($_.ScriptName):$($_.Line) - $($_.Message)" -ForegroundColor Red
            }
        }
    }
    
    # Vérification couverture
    if ($Parameters.CheckCoverage) {
        Write-Host "`n📊 Vérification couverture code..." -ForegroundColor Yellow
        
        if (Test-Path ".\reports\coverage.xml") {
            try {
                [xml]$coverageXml = Get-Content ".\reports\coverage.xml"
                $coveragePercent = [math]::Round(
                    ($coverageXml.report.counter | Where-Object type -eq "LINE").covered / 
                    ($coverageXml.report.counter | Where-Object type -eq "LINE").missed * 100, 2
                )
                
                if ($coveragePercent -ge $Parameters.MinCoveragePercent) {
                    $results.Coverage.Passed = $true
                    $results.Coverage.Details = "✅ Couverture : $coveragePercent% (minimum : $($Parameters.MinCoveragePercent)%)"
                    Write-Host $results.Coverage.Details -ForegroundColor Green
                } else {
                    $results.Coverage.Details = "❌ Couverture insuffisante : $coveragePercent% (minimum : $($Parameters.MinCoveragePercent)%)"
                    Write-Host $results.Coverage.Details -ForegroundColor Red
                }
            } catch {
                $results.Coverage.Details = "❌ Erreur lecture couverture : $($_.Exception.Message)"
                Write-Host $results.Coverage.Details -ForegroundColor Red
            }
        } else {
            $results.Coverage.Details = "❌ Fichier couverture non trouvé"
            Write-Host $results.Coverage.Details -ForegroundColor Red
        }
    }
    
    # Résultat global
    $allPassed = (-not $Parameters.RunTests -or $results.Tests.Passed) -and
                 (-not $Parameters.RunAnalysis -or $results.Analysis.Passed) -and
                 (-not $Parameters.CheckCoverage -or $results.Coverage.Passed)
    
    $results.Overall = $allPassed
    
    Write-Host "`n📈 Résumé qualité projet :" -ForegroundColor Cyan
    Write-Host "   Tests : $($results.Tests.Details)"
    Write-Host "   Analyse : $($results.Analysis.Details)"
    Write-Host "   Couverture : $($results.Coverage.Details)"
    
    if ($allPassed) {
        Write-Host "`n🎉 Projet prêt pour commit/push !" -ForegroundColor Green
    } else {
        Write-Host "`n⚠️  Corrections nécessaires avant commit" -ForegroundColor Yellow
    }
    
    return $results
}

# Exécution
$results = Test-ProjectQuality -Parameters $PSBoundParameters
exit ($results.Overall ? 0 : 1)
```

## 🔧 Outils de Développement

### Scripts Utilitaires

#### 1. Création Nouveau Module
```powershell
# New-ToolBoxModule.ps1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $ModuleName,
    
    [Parameter(Mandatory = $false)]
    [string] $DisplayName = $ModuleName,
    
    [Parameter(Mandatory = $false)]
    [string] $Category = "Administration",
    
    [Parameter(Mandatory = $false)]
    [array] $RequiredPermissions = @("AdminSystem")
)

function New-ToolBoxModule {
    param($ModuleName, $DisplayName, $Category, $RequiredPermissions)
    
    $modulePath = ".\src\Modules\$ModuleName"
    
    if (Test-Path $modulePath) {
        throw "Le module $ModuleName existe déjà"
    }
    
    Write-Host "🏗️ Création du module $ModuleName..." -ForegroundColor Cyan
    
    # Création structure dossiers
    $folders = @(
        $modulePath,
        "$modulePath\Functions\Public",
        "$modulePath\Functions\Private",
        "$modulePath\Classes",
        "$modulePath\Resources",
        "$modulePath\Tests"
    )
    
    foreach ($folder in $folders) {
        New-Item -Path $folder -ItemType Directory -Force | Out-Null
        Write-Host "   📁 $folder" -ForegroundColor Gray
    }
    
    # Génération GUID unique
    $moduleGuid = [System.Guid]::NewGuid().ToString()
    
    # Création manifest (.psd1)
    $manifestContent = @"
@{
    RootModule = '$ModuleName.psm1'
    ModuleVersion = '1.0.0'
    GUID = '$moduleGuid'
    Author = 'PowerShell Admin ToolBox Team'
    CompanyName = 'Open Source Community'
    Copyright = '(c) 2025 PowerShell Admin ToolBox Contributors'
    Description = 'Module $DisplayName pour PowerShell Admin ToolBox'
    
    PowerShellVersion = '7.5'
    DotNetFrameworkVersion = '9.0'
    
    RequiredModules = @('PowerShellAdminToolBox.Core')
    
    FunctionsToExport = @()
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    
    PrivateData = @{
        ToolBoxModule = @{
            DisplayName = '$DisplayName'
            Description = 'Description du module $DisplayName'
            Category = '$Category'
            Icon = 'Module'
            WindowType = 'Floating'
            AllowMultipleInstances = `$false
            RequiredPermissions = @('$($RequiredPermissions -join "', '")')
            HasConfigurationUI = `$true
            HasProgressIndicator = `$true
            HasLogOutput = `$true
            Version = '1.0.0'
            LastUpdated = '$(Get-Date -Format "yyyy-MM-dd")'
            Author = 'Developer'
        }
    }
}
"@
    
    Set-Content -Path "$modulePath\$ModuleName.psd1" -Value $manifestContent -Encoding UTF8
    Write-Host "   📄 $ModuleName.psd1" -ForegroundColor Green
    
    # Création module principal (.psm1)
    $moduleContent = @"
# Module $ModuleName pour PowerShell Admin ToolBox
# Auteur: PowerShell Admin ToolBox Team
# Date: $(Get-Date -Format "dd/MM/yyyy")

# Import des fonctions publiques
`$PublicFunctions = Get-ChildItem -Path "`$PSScriptRoot\Functions\Public\*.ps1" -ErrorAction SilentlyContinue
foreach (`$Function in `$PublicFunctions) {
    try {
        . `$Function.FullName
        Write-Verbose "Fonction chargée : `$(`$Function.BaseName)"
    }
    catch {
        Write-Error "Erreur chargement fonction `$(`$Function.BaseName) : `$(`$_.Exception.Message)"
    }
}

# Import des fonctions privées
`$PrivateFunctions = Get-ChildItem -Path "`$PSScriptRoot\Functions\Private\*.ps1" -ErrorAction SilentlyContinue
foreach (`$Function in `$PrivateFunctions) {
    try {
        . `$Function.FullName
        Write-Verbose "Fonction privée chargée : `$(`$Function.BaseName)"
    }
    catch {
        Write-Error "Erreur chargement fonction privée `$(`$Function.BaseName) : `$(`$_.Exception.Message)"
    }
}

# Import des classes
`$Classes = Get-ChildItem -Path "`$PSScriptRoot\Classes\*.ps1" -ErrorAction SilentlyContinue
foreach (`$Class in `$Classes) {
    try {
        . `$Class.FullName
        Write-Verbose "Classe chargée : `$(`$Class.BaseName)"
    }
    catch {
        Write-Error "Erreur chargement classe `$(`$Class.BaseName) : `$(`$_.Exception.Message)"
    }
}

# Export des fonctions publiques
`$ExportedFunctions = `$PublicFunctions | ForEach-Object { `$_.BaseName }
Export-ModuleMember -Function `$ExportedFunctions

Write-Verbose "Module $ModuleName chargé avec succès"
"@
    
    Set-Content -Path "$modulePath\$ModuleName.psm1" -Value $moduleContent -Encoding UTF8
    Write-Host "   📄 $ModuleName.psm1" -ForegroundColor Green
    
    # Création interface XAML
    $xamlContent = @"
<Window x:Class="$ModuleName.${ModuleName}Window"
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Style="{DynamicResource ToolBoxWindowStyle}"
        Title="{Binding WindowTitle}"
        Width="800" Height="600"
        WindowStartupLocation="CenterScreen">
    
    <Grid Style="{DynamicResource MainGridStyle}">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto" />      <!-- Header -->
            <RowDefinition Height="*" />         <!-- Content -->
            <RowDefinition Height="Auto" />      <!-- Footer -->
        </Grid.RowDefinitions>
        
        <!-- Header -->
        <Border Grid.Row="0" Style="{DynamicResource HeaderBorderStyle}">
            <StackPanel Orientation="Horizontal">
                <TextBlock Text="{Binding PageTitle}" 
                          Style="{DynamicResource PageTitleStyle}" />
                <Button Content="Exécuter" 
                        Command="{Binding ExecuteCommand}"
                        Style="{DynamicResource PrimaryButtonStyle}"
                        Margin="10,0,0,0" />
            </StackPanel>
        </Border>
        
        <!-- Contenu principal -->
        <ScrollViewer Grid.Row="1" Style="{DynamicResource MainScrollViewerStyle}">
            <StackPanel Margin="20">
                <TextBlock Text="Configuration du module $DisplayName" 
                          Style="{DynamicResource SectionTitleStyle}" />
                
                <!-- Zone de configuration à personnaliser -->
                <Grid Margin="0,10,0,0">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto" />
                        <ColumnDefinition Width="*" />
                    </Grid.ColumnDefinitions>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto" />
                        <RowDefinition Height="Auto" />
                    </Grid.RowDefinitions>
                    
                    <TextBlock Grid.Row="0" Grid.Column="0" 
                              Text="Paramètre 1 :" 
                              Style="{DynamicResource LabelStyle}" />
                    <TextBox Grid.Row="0" Grid.Column="1" 
                            Text="{Binding Parameter1}"
                            Style="{DynamicResource InputTextBoxStyle}" />
                    
                    <TextBlock Grid.Row="1" Grid.Column="0" 
                              Text="Paramètre 2 :" 
                              Style="{DynamicResource LabelStyle}" />
                    <TextBox Grid.Row="1" Grid.Column="1" 
                            Text="{Binding Parameter2}"
                            Style="{DynamicResource InputTextBoxStyle}" />
                </Grid>
            </StackPanel>
        </ScrollViewer>
        
        <!-- Footer avec logs et progression -->
        <Border Grid.Row="2" Style="{DynamicResource FooterBorderStyle}">
            <StackPanel>
                <!-- Barre de progression -->
                <ProgressBar Value="{Binding ProgressValue}" 
                           Maximum="100"
                           Visibility="{Binding IsProcessing, 
                                      Converter={StaticResource BooleanToVisibilityConverter}}"
                           Style="{DynamicResource ToolBoxProgressBarStyle}" />
                
                <!-- Zone de logs -->
                <ScrollViewer Height="100" 
                            Style="{DynamicResource LogScrollViewerStyle}">
                    <RichTextBox x:Name="LogTextBox"
                               IsReadOnly="True"
                               Style="{DynamicResource LogTextBoxStyle}" />
                </ScrollViewer>
            </StackPanel>
        </Border>
    </Grid>
</Window>
"@
    
    Set-Content -Path "$modulePath\${ModuleName}Window.xaml" -Value $xamlContent -Encoding UTF8
    Write-Host "   📄 ${ModuleName}Window.xaml" -ForegroundColor Green
    
    # Création ViewModel
    $viewModelContent = @"
# ViewModel pour le module $ModuleName
# Respect strict du pattern MVVM

using module PowerShellAdminToolBox.Core

class ${ModuleName}ViewModel : ViewModelBase {
    # Propriétés bindées à l'interface
    [string] `$PageTitle = "$DisplayName"
    [string] `$WindowTitle = "PowerShell Admin ToolBox - $DisplayName"
    [string] `$Parameter1 = ""
    [string] `$Parameter2 = ""
    [bool] `$IsProcessing = `$false
    [int] `$ProgressValue = 0
    
    # Commands pour l'interface
    [System.Windows.Input.ICommand] `$ExecuteCommand
    [System.Windows.Input.ICommand] `$CancelCommand
    
    # Services injectés
    [ProcessService] `$ProcessService
    [LoggingService] `$LoggingService
    
    # Constructor avec injection de dépendances
    ${ModuleName}ViewModel(
        [EventAggregator] `$eventAggregator,
        [LoggingService] `$loggingService,
        [ConfigurationService] `$configService,
        [ProcessService] `$processService
    ) : base(`$eventAggregator, `$loggingService, `$configService) {
        
        `$this.ProcessService = `$processService
        `$this.LoggingService = `$loggingService
        
        `$this.InitializeCommands()
        `$this.Initialize()
    }
    
    # Initialisation des commandes
    [void] InitializeCommands() {
        `$this.ExecuteCommand = [RelayCommand]::new(
            { `$this.ExecuteAction() },
            { `$this.CanExecute() }
        )
        
        `$this.CancelCommand = [RelayCommand]::new(
            { `$this.CancelAction() },
            { `$this.IsProcessing }
        )
    }
    
    # Initialisation du ViewModel
    [void] Initialize() {
        `$this.LoggingService.WriteLog("Module $ModuleName initialisé", "Info")
        
        # Abonnement aux événements si nécessaire
        `$this.EventAggregator.Subscribe("ProcessCompleted", {
            param(`$eventData)
            `$this.OnProcessCompleted(`$eventData)
        })
    }
    
    # Action principale du module
    [void] ExecuteAction() {
        try {
            `$this.IsProcessing = `$true
            `$this.ProgressValue = 0
            `$this.OnPropertyChanged("IsProcessing")
            `$this.OnPropertyChanged("ProgressValue")
            
            `$this.LoggingService.WriteLog("Démarrage traitement $ModuleName", "Info")
            
            # Script à exécuter en processus isolé
            `$scriptBlock = {
                param(`$param1, `$param2)
                
                # Logique métier du module à développer
                Write-Output "Traitement avec paramètres : `$param1, `$param2"
                
                # Simulation traitement
                for (`$i = 1; `$i -le 10; `$i++) {
                    Start-Sleep -Seconds 1
                    Write-Progress -Activity "Traitement en cours" -PercentComplete (`$i * 10)
                }
                
                return @{
                    Success = `$true
                    Message = "Traitement $ModuleName terminé avec succès"
                    Results = @{
                        Parameter1 = `$param1
                        Parameter2 = `$param2
                        ProcessedAt = Get-Date
                    }
                }
            }
            
            # Paramètres pour le script
            `$parameters = @{
                param1 = `$this.Parameter1
                param2 = `$this.Parameter2
            }
            
            # Démarrage processus isolé
            `$processId = `$this.ProcessService.StartProcess(`$scriptBlock, `$parameters)
            `$this.MonitorProcess(`$processId)
            
        } catch {
            `$this.LoggingService.WriteLog("Erreur exécution $ModuleName : `$(`$_.Exception.Message)", "Error")
            `$this.IsProcessing = `$false
            `$this.OnPropertyChanged("IsProcessing")
        }
    }
    
    # Annulation traitement
    [void] CancelAction() {
        `$this.LoggingService.WriteLog("Annulation traitement $ModuleName", "Warning")
        `$this.IsProcessing = `$false
        `$this.OnPropertyChanged("IsProcessing")
    }
    
    # Vérification possibilité exécution
    [bool] CanExecute() {
        return (-not `$this.IsProcessing) -and 
               (-not [string]::IsNullOrWhiteSpace(`$this.Parameter1))
    }
    
    # Monitoring processus asynchrone
    [void] MonitorProcess([string] `$processId) {
        `$timer = [System.Windows.Threading.DispatcherTimer]::new()
        `$timer.Interval = [TimeSpan]::FromMilliseconds(500)
        
        `$timer.add_Tick({
            `$status = `$this.ProcessService.GetProcessStatus(`$processId)
            
            if (`$status -and `$status.Status -eq "Completed") {
                `$this.IsProcessing = `$false
                `$this.ProgressValue = 100
                `$this.OnPropertyChanged("IsProcessing")
                `$this.OnPropertyChanged("ProgressValue")
                
                if (`$status.Result -and `$status.Result.Success) {
                    `$this.LoggingService.WriteLog(`$status.Result.Message, "Info")
                    `$this.EventAggregator.Publish("ProcessCompleted", `$status.Result)
                } else {
                    `$this.LoggingService.WriteLog("Traitement échoué", "Error")
                }
                
                `$timer.Stop()
            }
            elseif (`$status -and `$status.Status -eq "Error") {
                `$this.IsProcessing = `$false
                `$this.OnPropertyChanged("IsProcessing")
                
                foreach (`$error in `$status.Errors) {
                    `$this.LoggingService.WriteLog(`$error.ToString(), "Error")
                }
                
                `$timer.Stop()
            }
            else {
                # Mise à jour progression si disponible
                `$this.ProgressValue = [math]::Min(90, `$this.ProgressValue + 5)
                `$this.OnPropertyChanged("ProgressValue")
            }
        })
        
        `$timer.Start()
    }
    
    # Gestionnaire fin de processus
    [void] OnProcessCompleted([object] `$result) {
        `$this.LoggingService.WriteLog("Processus terminé : `$(`$result | ConvertTo-Json)", "Debug")
    }
    
    # Nettoyage ressources
    [void] Cleanup() {
        `$this.LoggingService.WriteLog("Nettoyage module $ModuleName", "Debug")
        # Nettoyage spécifique au module
    }
}
"@
    
    Set-Content -Path "$modulePath\${ModuleName}ViewModel.ps1" -Value $viewModelContent -Encoding UTF8
    Write-Host "   📄 ${ModuleName}ViewModel.ps1" -ForegroundColor Green
    
    # Création fonction exemple
    $functionContent = @"
function Get-${ModuleName}Data {
    <#
    .SYNOPSIS
        Fonction exemple pour le module $ModuleName
    
    .DESCRIPTION
        Cette fonction sert d'exemple pour le développement du module $ModuleName.
        À personnaliser selon les besoins du module.
    
    .PARAMETER InputData
        Données d'entrée à traiter
    
    .EXAMPLE
        Get-${ModuleName}Data -InputData "test"
        
        Récupère et traite les données pour le module $ModuleName
    
    .NOTES
        Auteur: PowerShell Admin ToolBox Team
        Date: $(Get-Date -Format "dd/MM/yyyy")
        Version: 1.0.0
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = `$true)]
        [string] `$InputData,
        
        [Parameter(Mandatory = `$false)]
        [switch] `$Detailed
    )
    
    begin {
        Write-ToolBoxLog -Message "Début Get-${ModuleName}Data" -Level "Debug"
    }
    
    process {
        try {
            Write-ToolBoxLog -Message "Traitement données pour $ModuleName : `$InputData" -Level "Info"
            
            # Logique métier à développer
            `$result = @{
                ModuleName = "$ModuleName"
                InputData = `$InputData
                ProcessedAt = Get-Date
                Success = `$true
            }
            
            if (`$Detailed) {
                `$result.Details = @{
                    ProcessId = `$PID
                    UserContext = `$env:USERNAME
                    ComputerName = `$env:COMPUTERNAME
                }
            }
            
            Write-ToolBoxLog -Message "Données traitées avec succès" -Level "Info"
            return `$result
            
        } catch {
            Write-ToolBoxLog -Message "Erreur traitement données : `$(`$_.Exception.Message)" -Level "Error"
            throw
        }
    }
    
    end {
        Write-ToolBoxLog -Message "Fin Get-${ModuleName}Data" -Level "Debug"
    }
}
"@
    
    Set-Content -Path "$modulePath\Functions\Public\Get-${ModuleName}Data.ps1" -Value $functionContent -Encoding UTF8
    Write-Host "   📄 Functions\Public\Get-${ModuleName}Data.ps1" -ForegroundColor Green
    
    # Création tests unitaires
    $testContent = @"
    # Tests unitaires pour le module $ModuleName
using module PowerShellAdminToolBox.Core

Describe "$ModuleName Module Tests" {
    BeforeAll {
        # Import du module pour tests
        Import-Module ".\src\Modules\$ModuleName\$ModuleName.psd1" -Force
        
        # Mocks des services
        `$mockEventAggregator = [PSCustomObject]@{
            Subscribe = { param(`$eventType, `$handler) }
            Publish = { param(`$eventType, `$data) }
        }
        
        `$mockLoggingService = [PSCustomObject]@{
            WriteLog = { param(`$message, `$level) Write-Host "`$level`: `$message" }
        }
        
        `$mockConfigService = [PSCustomObject]@{
            GetConfiguration = { return @{} }
        }
        
        `$mockProcessService = [PSCustomObject]@{
            StartProcess = { param(`$script, `$params) return "test-process-id" }
            GetProcessStatus = { param(`$id) return @{ Status = "Completed"; Result = @{ Success = `$true } } }
        }
    }
    
    Context "Get-${ModuleName}Data Function" {
        It "Retourne un résultat valide avec données d'entrée" {
            # Arrange
            `$inputData = "test-data"
            
            # Act
            `$result = Get-${ModuleName}Data -InputData `$inputData
            
            # Assert
            `$result | Should -Not -Be `$null
            `$result.ModuleName | Should -Be "$ModuleName"
            `$result.InputData | Should -Be `$inputData
            `$result.Success | Should -Be `$true
        }
        
        It "Inclut les détails quand le switch Detailed est utilisé" {
            # Arrange
            `$inputData = "test-data"
            
            # Act
            `$result = Get-${ModuleName}Data -InputData `$inputData -Detailed
            
            # Assert
            `$result.Details | Should -Not -Be `$null
            `$result.Details.ProcessId | Should -Not -Be `$null
            `$result.Details.UserContext | Should -Not -Be `$null
        }
        
        It "Lève une exception avec données invalides" {
            # Arrange & Act & Assert
            { Get-${ModuleName}Data -InputData "" } | Should -Throw
        }
    }
    
    Context "${ModuleName}ViewModel" {
        BeforeEach {
            `$viewModel = [${ModuleName}ViewModel]::new(
                `$mockEventAggregator,
                `$mockLoggingService,
                `$mockConfigService,
                `$mockProcessService
            )
        }
        
        It "Initialise correctement les propriétés" {
            `$viewModel.PageTitle | Should -Be "$DisplayName"
            `$viewModel.WindowTitle | Should -Match "$DisplayName"
            `$viewModel.IsProcessing | Should -Be `$false
            `$viewModel.ProgressValue | Should -Be 0
        }
        
        It "Commands sont initialisées" {
            `$viewModel.ExecuteCommand | Should -Not -Be `$null
            `$viewModel.CancelCommand | Should -Not -Be `$null
        }
        
        It "CanExecute retourne false quand Parameter1 est vide" {
            `$viewModel.Parameter1 = ""
            `$viewModel.CanExecute() | Should -Be `$false
        }
        
        It "CanExecute retourne true quand Parameter1 est renseigné" {
            `$viewModel.Parameter1 = "test"
            `$viewModel.CanExecute() | Should -Be `$true
        }
        
        It "ExecuteAction démarre le traitement" {
            # Arrange
            `$viewModel.Parameter1 = "test"
            
            # Act
            `$viewModel.ExecuteAction()
            
            # Assert
            `$viewModel.IsProcessing | Should -Be `$true
        }
    }
    
    Context "Module Integration" {
        It "Module se charge sans erreur" {
            { Import-Module ".\src\Modules\$ModuleName\$ModuleName.psd1" -Force } | Should -Not -Throw
        }
        
        It "Fonctions publiques sont exportées" {
            `$module = Get-Module -Name "$ModuleName"
            `$module.ExportedFunctions.Keys | Should -Contain "Get-${ModuleName}Data"
        }
        
        It "Manifest contient les métadonnées ToolBox" {
            `$manifestData = Import-PowerShellDataFile -Path ".\src\Modules\$ModuleName\$ModuleName.psd1"
            `$manifestData.PrivateData.ToolBoxModule | Should -Not -Be `$null
            `$manifestData.PrivateData.ToolBoxModule.DisplayName | Should -Be "$DisplayName"
        }
    }
}
"@
    
    Set-Content -Path "$modulePath\Tests\$ModuleName.Tests.ps1" -Value $testContent -Encoding UTF8
    Write-Host "   📄 Tests\$ModuleName.Tests.ps1" -ForegroundColor Green
    
    # Mise à jour du manifest avec les fonctions exportées
    $manifestPath = "$modulePath\$ModuleName.psd1"
    $manifestContent = Get-Content $manifestPath -Raw
    $manifestContent = $manifestContent -replace "FunctionsToExport = @\(\)", "FunctionsToExport = @('Get-${ModuleName}Data')"
    Set-Content -Path $manifestPath -Value $manifestContent -Encoding UTF8
    
    Write-Host "`n✅ Module $ModuleName créé avec succès !" -ForegroundColor Green
    Write-Host "📍 Emplacement : $modulePath" -ForegroundColor Cyan
    Write-Host "🚀 Prochaines étapes :" -ForegroundColor Yellow
    Write-Host "   1. Personnaliser l'interface XAML selon vos besoins" -ForegroundColor Gray
    Write-Host "   2. Développer la logique métier dans les fonctions" -ForegroundColor Gray
    Write-Host "   3. Adapter le ViewModel aux fonctionnalités spécifiques" -ForegroundColor Gray
    Write-Host "   4. Étoffer les tests unitaires" -ForegroundColor Gray
    Write-Host "   5. Tester le module avec : Import-Module `"$modulePath\$ModuleName.psd1`"" -ForegroundColor Gray
}

# Exécution
New-ToolBoxModule -ModuleName $ModuleName -DisplayName $DisplayName -Category $Category -RequiredPermissions $RequiredPermissions
```

#### 2. Script de Build et Release
```powershell
# Build-Release.ps1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $Version,
    
    [Parameter(Mandatory = $false)]
    [string] $OutputPath = ".\releases",
    
    [Parameter(Mandatory = $false)]
    [switch] $SkipTests,
    
    [Parameter(Mandatory = $false)]
    [switch] $CreateZip
)

function Build-Release {
    param($Version, $OutputPath, $SkipTests, $CreateZip)
    
    Write-Host "🏗️ Construction de la release v$Version..." -ForegroundColor Cyan
    
    # Validation version
    if (-not ($Version -match '^\d+\.\d+\.\d+# Guide de Développement - PowerShell Admin ToolBox 👨‍💻

Ce guide détaille l'environnement et les processus de développement pour contribuer efficacement au projet.

## 🚀 Configuration Environnement de Développement

### Prérequis Système
```powershell
# Version PowerShell requise
$PSVersionTable.PSVersion.Major -ge 7 -and $PSVersionTable.PSVersion.Minor -ge 5

# Framework .NET requis
dotnet --version  # Doit être 9.0 ou supérieur

# Modules PowerShell requis
Install-Module -Name Pester -Force -SkipPublisherCheck
Install-Module -Name PSScriptAnalyzer -Force
Install-Module -Name Microsoft.Graph -Force
Install-Module -Name PnP.PowerShell -Force
```

### Configuration Visual Studio Code
```json
// .vscode/settings.json
{
    "powershell.codeFormatting.preset": "OTBS",
    "powershell.codeFormatting.openBraceOnSameLine": true,
    "powershell.codeFormatting.newLineAfterOpenBrace": true,
    "powershell.codeFormatting.newLineAfterCloseBrace": true,
    "powershell.codeFormatting.whitespaceBeforeOpenBrace": true,
    "powershell.codeFormatting.whitespaceBeforeOpenParen": true,
    "powershell.codeFormatting.whitespaceAroundOperator": true,
    "powershell.codeFormatting.whitespaceAfterSeparator": true,
    "powershell.codeFormatting.ignoreOneLineBlock": false,
    "powershell.scriptAnalysis.enable": true,
    "powershell.scriptAnalysis.settingsPath": ".\\PSScriptAnalyzerSettings.psd1",
    "files.encoding": "utf8",
    "files.eol": "\r\n",
    "editor.insertSpaces": true,
    "editor.tabSize": 4
}
```

### Extensions VSCode Recommandées
```json
// .vscode/extensions.json
{
    "recommendations": [
        "ms-vscode.powershell",
        "ms-dotnettools.vscode-dotnet-runtime",
        "ms-vscode.vscode-json",
        "redhat.vscode-xml",
        "ms-vscode.test-adapter-converter",
        "formulahendry.code-runner",
        "streetsidesoftware.code-spell-checker"
    ]
}
```

### Configuration PSScriptAnalyzer
```powershell
# PSScriptAnalyzerSettings.psd1
@{
    # Règles à exclure
    ExcludeRules = @(
        'PSUseShouldProcessForStateChangingFunctions',  # Trop restrictif pour nos cas
        'PSAvoidUsingWriteHost'  # Autorisé pour logs console
    )
    
    # Règles personnalisées
    Rules = @{
        PSPlaceOpenBrace = @{
            Enable = $true
            OnSameLine = $true
            NewLineAfter = $true
        }
        
        PSPlaceCloseBrace = @{
            Enable = $true
            NewLineAfter = $true
        }
        
        PSUseConsistentIndentation = @{
            Enable = $true
            IndentationSize = 4
            PipelineIndentation = 'IncreaseIndentationForFirstPipeline'
            Kind = 'space'
        }
        
        PSUseConsistentWhitespace = @{
            Enable = $true
            CheckInnerBrace = $true
            CheckOpenBrace = $true
            CheckOpenParen = $true
            CheckOperator = $true
            CheckPipe = $true
            CheckSeparator = $true
        }
    }
}
```

## 🏗️ Structure de Développement

### Workflow Git Recommandé
```bash
# Configuration initiale
git config --global user.name "Votre Nom"
git config --global user.email "votre.email@example.com"
git config --global core.autocrlf true
git config --global pull.rebase false

# Clone et setup
git clone https://github.com/username/PowerShellAdminTool)) {
        throw "Format de version invalide. Utilisez le format x.y.z (ex: 1.0.0)"
    }
    
    # Tests qualité
    if (-not $SkipTests) {
        Write-Host "`n🧪 Exécution des tests..." -ForegroundColor Yellow
        $testResults = & ".\scripts\Test-ProjectQuality.ps1" -RunTests -RunAnalysis -CheckCoverage
        
        if (-not $testResults.Overall) {
            throw "Tests échoués. Utilisez -SkipTests pour ignorer (non recommandé)"
        }
    }
    
    # Création dossier release
    $releaseDir = Join-Path $OutputPath "v$Version"
    if (Test-Path $releaseDir) {
        Remove-Item $releaseDir -Recurse -Force
    }
    New-Item -Path $releaseDir -ItemType Directory -Force | Out-Null
    
    Write-Host "📁 Dossier release : $releaseDir" -ForegroundColor Gray
    
    # Copie des fichiers source
    $sourceItems = @(
        @{ Source = ".\src"; Destination = "$releaseDir\src" },
        @{ Source = ".\config"; Destination = "$releaseDir\config" },
        @{ Source = ".\scripts\Start-ToolBox.ps1"; Destination = "$releaseDir\Start-ToolBox.ps1" },
        @{ Source = ".\scripts\Install-Dependencies.ps1"; Destination = "$releaseDir\Install-Dependencies.ps1" },
        @{ Source = ".\README.md"; Destination = "$releaseDir\README.md" },
        @{ Source = ".\LICENSE"; Destination = "$releaseDir\LICENSE" },
        @{ Source = ".\CHANGELOG.md"; Destination = "$releaseDir\CHANGELOG.md" }
    )
    
    foreach ($item in $sourceItems) {
        if (Test-Path $item.Source) {
            if (Test-Path $item.Source -PathType Container) {
                Copy-Item -Path $item.Source -Destination $item.Destination -Recurse -Force
            } else {
                Copy-Item -Path $item.Source -Destination $item.Destination -Force
            }
            Write-Host "   ✅ $($item.Source)" -ForegroundColor Green
        } else {
            Write-Host "   ⚠️  $($item.Source) (introuvable)" -ForegroundColor Yellow
        }
    }
    
    # Mise à jour des numéros de version
    Write-Host "`n🔄 Mise à jour versions..." -ForegroundColor Yellow
    Update-ModuleVersions -Path "$releaseDir\src" -Version $Version
    
    # Génération des métadonnées release
    $releaseInfo = @{
        Version = $Version
        BuildDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        DotNetVersion = (dotnet --version)
        BuildEnvironment = $env:COMPUTERNAME
        Modules = Get-ModuleList -Path "$releaseDir\src\Modules"
    }
    
    $releaseInfo | ConvertTo-Json -Depth 3 | Set-Content -Path "$releaseDir\release-info.json" -Encoding UTF8
    Write-Host "   📄 release-info.json généré" -ForegroundColor Green
    
    # Création archive ZIP
    if ($CreateZip) {
        Write-Host "`n📦 Création archive ZIP..." -ForegroundColor Yellow
        $zipPath = Join-Path $OutputPath "PowerShellAdminToolBox-v$Version.zip"
        
        if (Test-Path $zipPath) {
            Remove-Item $zipPath -Force
        }
        
        Compress-Archive -Path "$releaseDir\*" -DestinationPath $zipPath -CompressionLevel Optimal
        Write-Host "   📦 Archive créée : $zipPath" -ForegroundColor Green
        
        # Calcul hash pour intégrité
        $hash = Get-FileHash -Path $zipPath -Algorithm SHA256
        "$($hash.Hash)  PowerShellAdminToolBox-v$Version.zip" | Set-Content -Path "$OutputPath\PowerShellAdminToolBox-v$Version.sha256" -Encoding UTF8
        Write-Host "   🔐 Hash SHA256 : $($hash.Hash)" -ForegroundColor Green
    }
    
    Write-Host "`n🎉 Release v$Version construite avec succès !" -ForegroundColor Green
    Write-Host "📍 Emplacement : $releaseDir" -ForegroundColor Cyan
    
    return @{
        Version = $Version
        Path = $releaseDir
        ZipPath = if ($CreateZip) { $zipPath } else { $null }
        Info = $releaseInfo
    }
}

function Update-ModuleVersions {
    param([string] $Path, [string] $Version)
    
    # Mise à jour manifests modules
    $manifestFiles = Get-ChildItem -Path $Path -Filter "*.psd1" -Recurse
    
    foreach ($manifest in $manifestFiles) {
        $content = Get-Content $manifest.FullName -Raw
        $content = $content -replace "ModuleVersion = '[^']*'", "ModuleVersion = '$Version'"
        $content = $content -replace "LastUpdated = '[^']*'", "LastUpdated = '$(Get-Date -Format "yyyy-MM-dd")'"
        Set-Content -Path $manifest.FullName -Value $content -Encoding UTF8
        
        Write-Host "   🔄 $($manifest.Name)" -ForegroundColor Gray
    }
}

function Get-ModuleList {
    param([string] $Path)
    
    $modules = @()
    $manifestFiles = Get-ChildItem -Path $Path -Filter "*.psd1" -Recurse
    
    foreach ($manifest in $manifestFiles) {
        try {
            $moduleData = Import-PowerShellDataFile -Path $manifest.FullName
            if ($moduleData.PrivateData.ToolBoxModule) {
                $modules += @{
                    Name = $moduleData.PrivateData.ToolBoxModule.DisplayName
                    Version = $moduleData.ModuleVersion
                    Category = $moduleData.PrivateData.ToolBoxModule.Category
                    Author = $moduleData.PrivateData.ToolBoxModule.Author
                }
            }
        } catch {
            Write-Warning "Erreur lecture manifest $($manifest.Name) : $($_.Exception.Message)"
        }
    }
    
    return $modules
}

# Exécution
$result = Build-Release -Version $Version -OutputPath $OutputPath -SkipTests:$SkipTests -CreateZip:$CreateZip
```

## 🔄 Processus de Développement

### Workflow Standard

#### 1. Démarrage Nouvelle Fonctionnalité
```powershell
# 1. Synchronisation
git checkout main
git pull upstream main

# 2. Création branche feature
git checkout -b feature/nom-fonctionnalite

# 3. Développement iteratif
# - Écrire tests en premier (TDD)
# - Développer fonctionnalité
# - Refactoriser si nécessaire

# 4. Validation continue
.\scripts\Test-ProjectQuality.ps1

# 5. Commits atomiques
git add -A
git commit -m "[FEAT] Description claire"

# 6. Push et PR
git push origin feature/nom-fonctionnalite
# Créer Pull Request via GitHub
```

#### 2. Résolution Bug
```powershell
# 1. Reproduction du bug
# - Créer test qui échoue
# - Documenter le comportement actuel

# 2. Création branche hotfix
git checkout -b hotfix/fix-bug-description

# 3. Correction
# - Corriger le code
# - Vérifier que le test passe
# - Ajouter tests de régression

# 4. Validation
.\scripts\Test-ProjectQuality.ps1 -RunTests -RunAnalysis

# 5. Merge vers main et develop
git checkout main
git merge hotfix/fix-bug-description
git checkout develop  
git merge hotfix/fix-bug-description
```

### Standards de Code Review

#### Checklist Reviewer
- [ ] **Architecture** : Respect du pattern MVVM
- [ ] **Modularité** : Pas de couplage fort entre modules
- [ ] **PowerShell pur** : Aucun code C#, aucune DLL externe
- [ ] **Tests** : Couverture suffisante, tests significatifs
- [ ] **Documentation** : Help PowerShell, commentaires clairs
- [ ] **Performance** : Pas de goulots d'étranglement évidents
- [ ] **Sécurité** : Pas de credentials hardcodés
- [ ] **Lisibilité** : Code auto-documenté, nommage cohérent

#### Commentaires Constructifs
```markdown
# ✅ Bon commentaire
Excellent use du pattern MVVM ! Suggestion mineure : pourriez-vous extraire cette logique dans une méthode privée pour améliorer la lisibilité ?

# ❌ Commentaire non constructif  
Ce code est mauvais.

# ✅ Commentaire technique
Cette méthode pourrait bénéficier d'une gestion d'erreur plus granulaire. Considérez l'utilisation de try/catch spécifiques pour différents types d'exceptions.
```

## 📈 Métriques et Monitoring

### Dashboard Qualité Projet
```powershell
# Get-ProjectMetrics.ps1
function Get-ProjectMetrics {
    $metrics = @{}
    
    # Métriques code
    $sourceFiles = Get-ChildItem -Path ".\src" -Include "*.ps1", "*.psm1" -Recurse
    $metrics.CodeMetrics = @{
        TotalFiles = $sourceFiles.Count
        TotalLines = ($sourceFiles | ForEach-Object { (Get-Content $_.FullName).Count } | Measure-Object -Sum).Sum
        PowerShellFiles = ($sourceFiles | Where-Object Extension -eq ".ps1").Count
        ModuleFiles = ($sourceFiles | Where-Object Extension -eq ".psm1").Count
    }
    
    # Métriques tests
    $testFiles = Get-ChildItem -Path ".\tests" -Filter "*.Tests.ps1" -Recurse
    $metrics.TestMetrics = @{
        TestFiles = $testFiles.Count
        TestCoverage = Get-TestCoverage
    }
    
    # Métriques modules
    $moduleManifests = Get-ChildItem -Path ".\src\Modules" -Filter "*.psd1" -Recurse
    $metrics.ModuleMetrics = @{
        TotalModules = $moduleManifests.Count
        ModulesByCategory = Get-ModulesByCategory $moduleManifests
    }
    
    # Métriques Git
    $gitMetrics = Get-GitMetrics
    $metrics.GitMetrics = $gitMetrics
    
    return $metrics
}

function Get-TestCoverage {
    if (Test-Path ".\reports\coverage.xml") {
        try {
            [xml]$coverage = Get-Content ".\reports\coverage.xml"
            $covered = [int]($coverage.report.counter | Where-Object type -eq "LINE").covered
            $missed = [int]($coverage.report.counter | Where-Object type -eq "LINE").missed
            return [math]::Round(($covered / ($covered + $missed)) * 100, 2)
        } catch {
            return 0
        }
    }
    return 0
}

function Get-ModulesByCategory {
    param($Manifests)
    
    $categories = @{}
    foreach ($manifest in $Manifests) {
        try {
            $data = Import-PowerShellDataFile -Path $manifest.FullName
            $category = $data.PrivateData.ToolBoxModule.Category
            if (-not $categories.ContainsKey($category)) {
                $categories[$category] = 0
            }
            $categories[$category]++
        } catch {
            # Ignore les erreurs de lecture manifest
        }
    }
    return $categories
}

function Get-GitMetrics {
    try {
        $totalCommits = (git rev-list --count HEAD)
        $contributors = (git log --format='%an' | Sort-Object -Unique).Count
        $lastCommitDate = git log -1 --format='%cd' --date=short
        
        return @{
            TotalCommits = $totalCommits
            Contributors = $contributors
            LastCommitDate = $lastCommitDate
            CurrentBranch = git branch --show-current
        }
    } catch {
        return @{
            TotalCommits = 0
            Contributors = 0
            LastCommitDate = "Unknown"
            CurrentBranch = "Unknown"
        }
    }
}

# Génération rapport
$metrics = Get-ProjectMetrics
$metrics | ConvertTo-Json -Depth 3 | Set-Content -Path ".\reports\project-metrics.json"

Write-Host "📊 Métriques Projet PowerShell Admin ToolBox" -ForegroundColor Cyan
Write-Host "=" * 50 -ForegroundColor Gray
Write-Host "Code      : $($metrics.CodeMetrics.TotalFiles) fichiers, $($metrics.CodeMetrics.TotalLines) lignes" -ForegroundColor White
Write-Host "Tests     : $($metrics.TestMetrics.TestFiles) fichiers, $($metrics.TestMetrics.TestCoverage)% couverture" -ForegroundColor White
Write-Host "Modules   : $($metrics.ModuleMetrics.TotalModules) modules actifs" -ForegroundColor White
Write-Host "Git       : $($metrics.GitMetrics.TotalCommits) commits, $($metrics.GitMetrics.Contributors) contributeurs" -ForegroundColor White
Write-Host "Branche   : $($metrics.GitMetrics.CurrentBranch)" -ForegroundColor White
```

## 🚀 Optimisations Performance

### Profiling PowerShell
```powershell
# Measure-Performance.ps1
function Measure-ModulePerformance {
    param(
        [string] $ModuleName,
        [int] $Iterations = 100
    )
    
    Write-Host "⚡ Test performance module $ModuleName..." -ForegroundColor Cyan
    
    # Mesure temps de chargement
    $loadTimes = @()
    for ($i = 1; $i -le $Iterations; $i++) {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        
        Remove-Module $ModuleName -ErrorAction SilentlyContinue
        Import-Module ".\src\Modules\$ModuleName\$ModuleName.psd1" -Force
        
        $stopwatch.Stop()
        $loadTimes += $stopwatch.ElapsedMilliseconds
        
        Write-Progress -Activity "Test chargement" -PercentComplete (($i / $Iterations) * 100)
    }
    
    # Statistiques
    $avgLoadTime = ($loadTimes | Measure-Object -Average).Average
    $maxLoadTime = ($loadTimes | Measure-Object -Maximum).Maximum
    $minLoadTime = ($loadTimes | Measure-Object -Minimum).Minimum
    
    Write-Host "📈 Résultats performance :" -ForegroundColor Yellow
    Write-Host "   Temps moyen chargement : $([math]::Round($avgLoadTime, 2)) ms" -ForegroundColor White
    Write-Host "   Temps minimum : $minLoadTime ms" -ForegroundColor Green
    Write-Host "   Temps maximum : $maxLoadTime ms" -ForegroundColor Red
    
    # Seuils d'alerte
    if ($avgLoadTime -gt 1000) {
        Write-Host "⚠️  Chargement lent détecté (>1s)" -ForegroundColor Yellow
    }
    
    return @{
        ModuleName = $ModuleName
        AverageLoadTime = $avgLoadTime
        MinLoadTime = $minLoadTime
        MaxLoadTime = $maxLoadTime
        Iterations = $Iterations
    }
}

# Test tous les modules
$modules = Get-ChildItem -Path ".\src\Modules" -Directory
foreach ($module in $modules) {
    $result = Measure-ModulePerformance -ModuleName $module.Name -Iterations 10
    # Sauvegarder résultats pour suivi dans le temps
}
```

---

## 📚 Ressources pour Développeurs

### Documentation PowerShell
- [About Classes](https://docs.microsoft.com/powershell/scripting/learn/deep-dives/everything-about-classes)
- [Advanced Functions](https://docs.microsoft.com/powershell/scripting/learn/deep-dives/everything-about-parameters)
- [PowerShell Gallery](https://www.powershellgallery.com/)

### Outils Recommandés
- **PSScriptAnalyzer** : Analyse statique de code
- **Pester** : Framework de tests
- **PlatyPS** : Génération documentation
- **PowerShell-Beautifier** : Formatage automatique

### Communauté
- [PowerShell Community](https://github.com/PowerShell/PowerShell)
- [PowerShell Discord](https://discord.gg/powershell)
- [Reddit r/PowerShell](https://www.reddit.com/r/PowerShell/)

Ce guide garantit une **approche professionnelle** et **standardisée** pour tous les contributeurs du projet !# Guide de Développement - PowerShell Admin ToolBox 👨‍💻

Ce guide détaille l'environnement et les processus de développement pour contribuer efficacement au projet.

## 🚀 Configuration Environnement de Développement

### Prérequis Système
```powershell
# Version PowerShell requise
$PSVersionTable.PSVersion.Major -ge 7 -and $PSVersionTable.PSVersion.Minor -ge 5

# Framework .NET requis
dotnet --version  # Doit être 9.0 ou supérieur

# Modules PowerShell requis
Install-Module -Name Pester -Force -SkipPublisherCheck
Install-Module -Name PSScriptAnalyzer -Force
Install-Module -Name Microsoft.Graph -Force
Install-Module -Name PnP.PowerShell -Force
```

### Configuration Visual Studio Code
```json
// .vscode/settings.json
{
    "powershell.codeFormatting.preset": "OTBS",
    "powershell.codeFormatting.openBraceOnSameLine": true,
    "powershell.codeFormatting.newLineAfterOpenBrace": true,
    "powershell.codeFormatting.newLineAfterCloseBrace": true,
    "powershell.codeFormatting.whitespaceBeforeOpenBrace": true,
    "powershell.codeFormatting.whitespaceBeforeOpenParen": true,
    "powershell.codeFormatting.whitespaceAroundOperator": true,
    "powershell.codeFormatting.whitespaceAfterSeparator": true,
    "powershell.codeFormatting.ignoreOneLineBlock": false,
    "powershell.scriptAnalysis.enable": true,
    "powershell.scriptAnalysis.settingsPath": ".\\PSScriptAnalyzerSettings.psd1",
    "files.encoding": "utf8",
    "files.eol": "\r\n",
    "editor.insertSpaces": true,
    "editor.tabSize": 4
}
```

### Extensions VSCode Recommandées
```json
// .vscode/extensions.json
{
    "recommendations": [
        "ms-vscode.powershell",
        "ms-dotnettools.vscode-dotnet-runtime",
        "ms-vscode.vscode-json",
        "redhat.vscode-xml",
        "ms-vscode.test-adapter-converter",
        "formulahendry.code-runner",
        "streetsidesoftware.code-spell-checker"
    ]
}
```

### Configuration PSScriptAnalyzer
```powershell
# PSScriptAnalyzerSettings.psd1
@{
    # Règles à exclure
    ExcludeRules = @(
        'PSUseShouldProcessForStateChangingFunctions',  # Trop restrictif pour nos cas
        'PSAvoidUsingWriteHost'  # Autorisé pour logs console
    )
    
    # Règles personnalisées
    Rules = @{
        PSPlaceOpenBrace = @{
            Enable = $true
            OnSameLine = $true
            NewLineAfter = $true
        }
        
        PSPlaceCloseBrace = @{
            Enable = $true
            NewLineAfter = $true
        }
        
        PSUseConsistentIndentation = @{
            Enable = $true
            IndentationSize = 4
            PipelineIndentation = 'IncreaseIndentationForFirstPipeline'
            Kind = 'space'
        }
        
        PSUseConsistentWhitespace = @{
            Enable = $true
            CheckInnerBrace = $true
            CheckOpenBrace = $true
            CheckOpenParen = $true
            CheckOperator = $true
            CheckPipe = $true
            CheckSeparator = $true
        }
    }
}
```

## 🏗️ Structure de Développement

### Workflow Git Recommandé
```bash
# Configuration initiale
git config --global user.name "Votre Nom"
git config --global user.email "votre.email@example.com"
git config --global core.autocrlf true
git config --global pull.rebase false

# Clone et setup
git clone https://github.com/username/PowerShellAdminTool