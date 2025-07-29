# Guide de Contribution - PowerShell Admin ToolBox 🤝

Merci de votre intérêt pour contribuer à PowerShell Admin ToolBox ! Ce guide vous aidera à participer efficacement au projet.

## 🎯 Vision des Contributions

Nous recherchons des **administrateurs systèmes** et **développeurs PowerShell** désireux de :
- Simplifier les tâches répétitives d'administration
- Partager leurs scripts et bonnes pratiques
- Contribuer à un standard communautaire PowerShell

## 📋 Types de Contributions Recherchées

### 🐛 Corrections de Bugs
- Corrections de dysfonctionnements
- Améliorations de performance
- Corrections de sécurité

### ✨ Nouvelles Fonctionnalités
- Nouveaux modules d'administration
- Améliorations interface utilisateur
- Intégrations avec services externes

### 📝 Documentation
- Amélioration guides utilisateur
- Documentation technique
- Exemples d'utilisation

### 🌍 Internationalisation
- Traductions (actuellement FR/EN supportés)
- Adaptation culturelle des interfaces

### 🧪 Tests & Qualité
- Tests unitaires avec Pester
- Tests d'intégration
- Amélioration couverture de tests

## 🚀 Démarrage Rapide

### 1. Configuration Environnement

```powershell
# Prérequis système
- PowerShell Core 7.5+
- .NET Framework 9.0+
- Git
- Visual Studio Code (recommandé)

# Fork du projet
# 1. Cliquez sur "Fork" sur GitHub
# 2. Clonez votre fork localement
git clone https://github.com/VOTRE-USERNAME/PowerShellAdminToolBox.git
cd PowerShellAdminToolBox

# Configuration upstream
git remote add upstream https://github.com/ORIGINAL-OWNER/PowerShellAdminToolBox.git

# Installation dépendances
.\scripts\Install-Dependencies.ps1

# Vérification environnement
.\scripts\Test-Environment.ps1
```

### 2. Workflow de Développement

```powershell
# Synchronisation avec upstream
git checkout main
git pull upstream main

# Création branche feature
git checkout -b feature/nom-fonctionnalite

# Développement + commits
# ... votre travail ...
git add .
git commit -m "[FEAT] Description claire de la fonctionnalité"

# Push et Pull Request
git push origin feature/nom-fonctionnalite
# Créer PR via interface GitHub
```

## 🏗️ Standards de Développement

### Contraintes Techniques ABSOLUES
- ✅ **PowerShell Core 7.5+ uniquement**
- ✅ **Framework .NET 9.0 minimum**
- ❌ **Aucune classe personnalisée C#**
- ❌ **Aucune DLL externe à ajouter**
- ✅ **Respect strict du modèle MVVM**
- ✅ **Modularité exemplaire**

### Conventions de Code

#### Nomenclature
```powershell
# Functions : PascalCase avec verbe PowerShell approuvé
function Get-UserInformation { }
function New-SharePointStructure { }

# Variables : camelCase
$userName = "john.doe"
$currentUserContext = Get-Current-User

# Constantes : UPPER_CASE
$SCRIPT:LOG_LEVEL = "INFO"
$SCRIPT:DEFAULT_TIMEOUT = 300
```

#### Structure Fonctions
```powershell
function Verb-Noun {
    <#
    .SYNOPSIS
        Description courte en français
    
    .DESCRIPTION
        Description détaillée de la fonction
    
    .PARAMETER ParameterName
        Description du paramètre
    
    .EXAMPLE
        Verb-Noun -Parameter "Value"
        Description de l'exemple
    
    .NOTES
        Auteur: Nom Prénom
        Date: DD/MM/YYYY
        Version: 1.0.0
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RequiredParameter,
        
        [Parameter(Mandatory = $false)]
        [int]$OptionalParameter = 10
    )
    
    begin {
        Write-ToolBoxLog -Message "Début de Verb-Noun" -Level "Debug"
    }
    
    process {
        try {
            # Logique principale
            Write-ToolBoxLog -Message "Traitement en cours" -Level "Info"
            
            # Retour explicite
            return $result
        }
        catch {
            Write-ToolBoxLog -Message "Erreur : $($_.Exception.Message)" -Level "Error"
            throw
        }
    }
    
    end {
        Write-ToolBoxLog -Message "Fin de Verb-Noun" -Level "Debug"
    }
}
```

#### Classes PowerShell (MVVM)
```powershell
# ViewModel base conforme MVVM
class ViewModelBase : System.ComponentModel.INotifyPropertyChanged {
    # Événement PropertyChanged
    [System.ComponentModel.PropertyChangedEventHandler]$PropertyChanged
    
    # Méthode notification changement propriété
    [void] OnPropertyChanged([string]$propertyName) {
        if ($this.PropertyChanged) {
            $args = [System.ComponentModel.PropertyChangedEventArgs]::new($propertyName)
            $this.PropertyChanged.Invoke($this, $args)
        }
    }
    
    # Méthode setter avec notification
    [bool] SetProperty([ref]$field, $value, [string]$propertyName) {
        if (-not [object]::Equals($field.Value, $value)) {
            $field.Value = $value
            $this.OnPropertyChanged($propertyName)
            return $true
        }
        return $false
    }
}
```

### Gestion des Erreurs
```powershell
# Utilisation systématique try/catch
try {
    # Code à risque
    $result = Invoke-RiskyOperation
}
catch [System.UnauthorizedAccessException] {
    Write-ToolBoxLog -Message "Accès refusé : vérifiez les permissions" -Level "Error"
    throw "Erreur d'autorisation : $($_.Exception.Message)"
}
catch {
    Write-ToolBoxLog -Message "Erreur inattendue : $($_.Exception.Message)" -Level "Error"
    throw
}
```

## 🧪 Tests Obligatoires

### Tests Unitaires (Pester)
```powershell
# Exemple test fonction
Describe "Get-UserInformation" {
    Context "Avec utilisateur valide" {
        It "Retourne les informations utilisateur" {
            # Arrange
            $userName = "test.user"
            
            # Act
            $result = Get-UserInformation -UserName $userName
            
            # Assert
            $result | Should -Not -Be $null
            $result.Name | Should -Be $userName
        }
    }
    
    Context "Avec utilisateur inexistant" {
        It "Lève une exception" {
            # Arrange & Act & Assert
            { Get-UserInformation -UserName "inexistant" } | Should -Throw
        }
    }
}
```

### Tests d'Intégration
```powershell
# Test chargement module
Describe "Module Loading Integration" {
    It "Charge le module Core correctement" {
        Import-Module ".\src\Core\PowerShellAdminToolBox.Core.psd1"
        Get-Module "PowerShellAdminToolBox.Core" | Should -Not -Be $null
    }
    
    It "Charge les modules dynamiquement" {
        $moduleLoader = [ModuleLoader]::new()
        $modules = $moduleLoader.LoadAvailableModules()
        $modules.Count | Should -BeGreaterThan 0
    }
}
```

## 🎨 Standards Interface Utilisateur

### Structure XAML
```xml
<!-- Fenêtre standard avec styles globaux -->
<Window x:Class="ModuleName.WindowName"
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Style="{DynamicResource ToolBoxWindowStyle}"
        Title="{Binding WindowTitle}"
        Width="800" Height="600">
    
    <Grid Style="{DynamicResource MainGridStyle}">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto" />      <!-- Header -->
            <RowDefinition Height="*" />         <!-- Content -->
            <RowDefinition Height="Auto" />      <!-- Footer -->
        </Grid.RowDefinitions>
        
        <!-- Header avec titre et actions -->
        <Border Grid.Row="0" Style="{DynamicResource HeaderBorderStyle}">
            <TextBlock Text="{Binding PageTitle}" 
                      Style="{DynamicResource PageTitleStyle}" />
        </Border>
        
        <!-- Contenu principal -->
        <ContentPresenter Grid.Row="1" 
                         Content="{Binding CurrentView}" />
        
        <!-- Footer avec logs et progression -->
        <Border Grid.Row="2" Style="{DynamicResource FooterBorderStyle}">
            <StackPanel Orientation="Vertical">
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
```

### ViewModel Standard
```powershell
# ViewModel de module conforme aux standards
class ModuleViewModel : ViewModelBase {
    # Propriétés bindées
    [string] $PageTitle = "Nom du Module"
    [string] $WindowTitle = "PowerShell Admin ToolBox - Module"
    [bool] $IsProcessing = $false
    [int] $ProgressValue = 0
    [object] $CurrentView
    
    # Commands
    [System.Windows.Input.ICommand] $ExecuteCommand
    [System.Windows.Input.ICommand] $CancelCommand
    
    # Constructor
    ModuleViewModel() {
        $this.InitializeCommands()
        $this.InitializeView()
    }
    
    # Initialisation des commandes
    [void] InitializeCommands() {
        $this.ExecuteCommand = [RelayCommand]::new(
            { $this.ExecuteAction() },
            { $this.CanExecute() }
        )
        
        $this.CancelCommand = [RelayCommand]::new(
            { $this.CancelAction() },
            { $this.IsProcessing }
        )
    }
    
    # Actions principales
    [void] ExecuteAction() {
        try {
            $this.IsProcessing = $true
            $this.OnPropertyChanged("IsProcessing")
            
            # Exécution en processus séparé
            $scriptBlock = {
                # Logique métier du module
            }
            
            Start-PowerShellProcess -ScriptBlock $scriptBlock -ModuleName "ModuleName"
        }
        catch {
            Write-ToolBoxLog -Message "Erreur execution : $($_.Exception.Message)" -Level "Error"
        }
        finally {
            $this.IsProcessing = $false
            $this.OnPropertyChanged("IsProcessing")
        }
    }
}
```

## 📦 Structure d'un Nouveau Module

### 1. Créer la Structure
```powershell
# Script de création module
.\scripts\New-ToolBoxModule.ps1 -ModuleName "MonNouveauModule"

# Cela crée :
src/Modules/MonNouveauModule/
├── MonNouveauModule.psd1           # Manifest
├── MonNouveauModule.psm1           # Module principal
├── MonNouveauModuleWindow.xaml     # Interface
├── MonNouveauModuleViewModel.ps1   # ViewModel
└── Functions/
    └── Get-ModuleData.ps1          # Fonctions métier
```

### 2. Manifest Module (.psd1)
```powershell
@{
    RootModule = 'MonNouveauModule.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'GUID-UNIQUE'
    Author = 'Votre Nom'
    CompanyName = 'PowerShell Admin ToolBox'
    Copyright = '(c) 2025. All rights reserved.'
    Description = 'Description de votre module'
    
    # Version PowerShell minimum
    PowerShellVersion = '7.5'
    
    # Modules requis
    RequiredModules = @('PowerShellAdminToolBox.Core')
    
    # Fonctions exportées
    FunctionsToExport = @('Get-ModuleData', 'Set-ModuleConfig')
    
    # Métadonnées module ToolBox
    PrivateData = @{
        ToolBoxModule = @{
            DisplayName = 'Mon Nouveau Module'
            Category = 'Administration'
            RequiredPermissions = @('AdminSystem')
            WindowType = 'Floating'
            Icon = 'ModuleIcon.png'
        }
    }
}
```

## 🔧 Processus de Review

### Checklist Pull Request
- [ ] **Tests** : Tous les tests passent (`Invoke-Pester`)
- [ ] **Code Quality** : PSScriptAnalyzer sans erreur
- [ ] **Documentation** : Fonctions documentées avec Help
- [ ] **MVVM** : Respect strict du pattern
- [ ] **Modularité** : Aucune dépendance circulaire
- [ ] **Sécurité** : Pas de credentials hardcodés
- [ ] **Performance** : Tests de charge OK
- [ ] **Compatibilité** : PowerShell 7.5+ et .NET 9.0+

### Process de Validation
1. **Review automatique** : GitHub Actions
2. **Review par les pairs** : Minimum 1 approbation
3. **Tests manuels** : Validation fonctionnelle
4. **Merge** : Squash merge vers develop

## 🏷️ Gestion des Issues

### Labels Standard
- `bug` : Dysfonctionnement à corriger
- `enhancement` : Amélioration existante
- `feature` : Nouvelle fonctionnalité
- `documentation` : Amélioration docs
- `good-first-issue` : Idéal pour débuter
- `help-wanted` : Aide communauté souhaitée
- `question` : Question d'utilisation
- `wontfix` : Ne sera pas implémenté

### Templates Issues
Utilisez les templates GitHub pour :
- **Bug Report** : Reproduction, environnement, impact
- **Feature Request** : Besoin, solution proposée, alternatives
- **Question** : Contexte, question précise

## 📞 Communication

### Canaux Disponibles
- **GitHub Issues** : Bugs et demandes de fonctionnalités
- **GitHub Discussions** : Questions générales et idées
- **Pull Requests** : Review de code et discussions techniques
- **Email** : admin-toolbox@example.com pour questions privées

### Bonnes Pratiques Communication
- **Soyez respectueux** : Code de conduite obligatoire
- **Soyez précis** : Contexte, étapes de reproduction, environnement
- **Soyez patient** : Projet communautaire, temps de réponse variable
- **Aidez les autres** : Partagez vos connaissances

## 🎯 Priorités Contributions

### 🔥 Haute Priorité
- Corrections bugs critiques
- Tests manquants sur modules Core
- Documentation API manquante
- Performance et optimisation

### 📈 Moyenne Priorité  
- Nouveaux modules administration
- Améliorations interface utilisateur
- Traductions et internationalisation
- Intégrations services externes

### 💡 Idées Futures
- Système de plugins externes
- API REST pour intégrations
- Mode CLI pour automatisation
- Support containers/cloud

## 🏆 Reconnaissance Contributeurs

### Hall of Fame
Les contributeurs significatifs sont mis en avant :
- **README principal** : Section remerciements
- **CONTRIBUTORS.md** : Liste détaillée contributions
- **Releases** : Mention dans changelogs
- **GitHub** : Statut de collaborateur

### Types de Contributions Reconnues
- Code (fonctionnalités, corrections)
- Documentation (guides, exemples)
- Tests (couverture, qualité)
- Design (interface, expérience)
- Community (support, modération)

## 📚 Resources Utiles

### Documentation Technique
- [PowerShell Core](https://docs.microsoft.com/powershell/)
- [WPF MVVM Pattern](https://docs.microsoft.com/dotnet/desktop/wpf/data/data-binding-overview)
- [Pester Testing](https://pester.dev/)
- [PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer)

### Outils Recommandés
- **IDE** : Visual Studio Code avec extension PowerShell
- **Git GUI** : GitKraken, SourceTree, ou GitHub Desktop
- **Diff Tools** : Beyond Compare, WinMerge
- **Documentation** : PlatyPS pour génération help

---

## 🤝 Engagement Communautaire

En contribuant à PowerShell Admin ToolBox, vous rejoignez une communauté engagée à :

✅ **Partager les bonnes pratiques** PowerShell et administration système  
✅ **Simplifier la vie** des administrateurs IT au quotidien  
✅ **Maintenir la qualité** et la sécurité du code  
✅ **Accueillir chaleureusement** les nouveaux contributeurs  
✅ **Documenter clairement** pour faciliter l'adoption  

**Votre expertise compte !** Que vous soyez débutant ou expert, votre perspective unique enrichit le projet.

---

<div align="center">

**🚀 Prêt à contribuer ? Commencez par consulter les [Issues "good first issue"](https://github.com/username/PowerShellAdminToolBox/labels/good-first-issue) ! 🚀**

</div>