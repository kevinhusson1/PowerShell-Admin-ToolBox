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
        Import-Module ".\src\Core\PowerShellAdminToolBox