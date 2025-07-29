# PowerShell Admin ToolBox 🧰

[![PowerShell Core](https://img.shields.io/badge/PowerShell-7.5+-blue.svg)](https://github.com/PowerShell/PowerShell)
[![.NET](https://img.shields.io/badge/.NET-9.0+-purple.svg)](https://dotnet.microsoft.com/download)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Build Status](https://img.shields.io/github/actions/workflow/status/username/PowerShellAdminToolBox/ci.yml?branch=main)](https://github.com/username/PowerShellAdminToolBox/actions)
[![Contributors](https://img.shields.io/github/contributors/username/PowerShellAdminToolBox.svg)](https://github.com/username/PowerShellAdminToolBox/graphs/contributors)

## 🎯 Vision du Projet

**PowerShell Admin ToolBox** est une application de bureau open-source de qualité professionnelle, conçue spécifiquement pour les administrateurs et ingénieurs systèmes. 

L'objectif est clair : **dépasser le stade du simple "lanceur de scripts"** pour offrir une véritable suite graphique d'outils intégrés, modernes, intuitifs et extensibles.

## ✨ Caractéristiques Principales

### 🏗️ Architecture Moderne
- **100% PowerShell Core 7.5+** - Aucun code C# ou DLL externe
- **Pattern MVVM strict** - Architecture maintenable et testable
- **Modularité exemplaire** - Ajout de fonctionnalités sans modification du cœur
- **Framework .NET 9.0+** - Technologies les plus récentes

### 🔧 Fonctionnalités Clés
- **Gestion utilisateurs AD/Azure** - Création, désactivation, export complet
- **Outils SharePoint** - Création d'arborescences avec gestion des droits
- **Processus isolés** - Chaque script s'exécute dans son propre processus PowerShell
- **Interface non-bloquante** - Fenêtres flottantes avec barres de progression
- **Système de logs avancé** - Multi-destinations avec colorisation

### 🛡️ Sécurité & Authentification
- **Authentification hybride** - AD/Azure ou certificat applicatif
- **Gestion des droits granulaire** - Outils réservés selon permissions
- **Stockage sécurisé** - Pas de secrets dans le code source

## 🚀 Démarrage Rapide

### Prérequis
- **PowerShell Core 7.5+** installé
- **Framework .NET 9.0+** installé
- **Modules PowerShell** : Microsoft.Graph, PnP.PowerShell
- **Permissions** : Administrateur système (AD/Azure)

### Installation

```powershell
# Cloner le repository
git clone https://github.com/username/PowerShellAdminToolBox.git
cd PowerShellAdminToolBox

# Installer les dépendances
.\scripts\Install-Dependencies.ps1

# Configurer l'application
.\scripts\Initialize-Configuration.ps1

# Lancer l'application
.\scripts\Start-ToolBox.ps1
```

### Premier lancement
1. L'application détecte automatiquement vos permissions
2. Configure l'authentification selon votre environnement
3. Charge les modules disponibles selon vos droits
4. Affiche l'interface principale avec les outils accessibles

## 📖 Documentation

| Document | Description |
|----------|-------------|
| [Guide Utilisateur](docs/USER_GUIDE.md) | Utilisation complète de l'application |
| [Architecture](docs/ARCHITECTURE.md) | Détails techniques et design patterns |
| [Développement](docs/DEVELOPMENT.md) | Guide pour contributeurs |
| [API Modules](docs/API.md) | Documentation API pour créer des modules |
| [Déploiement](docs/DEPLOYMENT.md) | Instructions de déploiement |

## 🧩 Modules Disponibles

### 👤 Gestion Utilisateurs
- **Création comptes** AD/Azure avec attribution automatique licences/groupes
- **Désactivation comptes** avec sauvegarde historique dans SharePoint
- **Export complet** utilisateurs Azure avec toutes leurs propriétés

### 📁 Outils SharePoint  
- **Import XML** pour définition d'arborescences complexes
- **Création automatique** de structures avec droits de contribution
- **Gestion permissions** granulaire par dossier

### 📊 Rapports & Export
- **Formats multiples** : CSV, Excel, JSON, PDF
- **Planification** : Exports automatiques selon planning
- **Notifications** : Email et Teams intégrées

## 🏗️ Architecture du Projet

```
PowerShellAdminToolBox/
├── src/
│   ├── Core/                 # Module PowerShell central
│   ├── UI/                   # Interface XAML/WPF
│   └── Modules/              # Modules fonctionnels extensibles
├── docs/                     # Documentation complète
├── tests/                    # Tests unitaires et d'intégration
└── scripts/                  # Scripts utilitaires
```

### Principes de Conception

- **MVVM comme dogme** - Séparation stricte View/ViewModel/Model
- **Approche Style-Driven** - Thème graphique unifié
- **Tout est un module** - Chaque brique réutilisable isolée
- **Politique "Zéro Global"** - Pas de variables globales
- **Sécurité intégrée** - Gestion secrets via mécanismes externes

## 🤝 Contribution

Nous accueillons chaleureusement les contributions ! Ce projet est conçu pour être accessible aux administrateurs PowerShell de tous niveaux.

### Démarrage Contributeur
1. Consultez le [Guide de Contribution](CONTRIBUTING.md)
2. Regardez les [Issues "good first issue"](https://github.com/username/PowerShellAdminToolBox/labels/good-first-issue)
3. Suivez le [Guide de Développement](docs/DEVELOPMENT.md)

### Types de Contributions
- 🐛 **Corrections de bugs**
- ✨ **Nouvelles fonctionnalités** 
- 📝 **Amélioration documentation**
- 🌍 **Traductions** (actuellement FR/EN)
- 🧪 **Tests** et amélioration qualité
- 💡 **Idées** et suggestions

## 📅 Roadmap

### 🎯 Phase 1 - Fondations (Q1 2025)
- [x] Architecture MVVM et système modulaire
- [x] Interface principale avec thème global
- [x] Système d'authentification hybride
- [x] Framework de logs multi-destinations

### 🎯 Phase 2 - Modules Core (Q2 2025)
- [ ] Module gestion utilisateurs AD/Azure complet
- [ ] Module outils SharePoint avec import XML
- [ ] Système de notifications (Email/Teams)

### 🎯 Phase 3 - Extensions (Q3 2025)
- [ ] Système de plugins tiers
- [ ] API REST pour intégrations externes
- [ ] Support GLPI et autres ITSM

### 🎯 Phase 4 - Maturité (Q4 2025)
- [ ] Tests automatisés complets
- [ ] Distribution Winget/Chocolatey
- [ ] Documentation interactive

## 🏆 Communauté & Support

- 💬 **Discussions** : [GitHub Discussions](https://github.com/username/PowerShellAdminToolBox/discussions)
- 🐛 **Bugs** : [Issues](https://github.com/username/PowerShellAdminToolBox/issues)
- 📧 **Contact** : admin-toolbox@example.com
- 💡 **Idées** : [Feature Requests](https://github.com/username/PowerShellAdminToolBox/issues/new?template=feature_request.yml)

## 📊 Statistiques Projet

![GitHub stars](https://img.shields.io/github/stars/username/PowerShellAdminToolBox?style=social)
![GitHub forks](https://img.shields.io/github/forks/username/PowerShellAdminToolBox?style=social)
![GitHub issues](https://img.shields.io/github/issues/username/PowerShellAdminToolBox)
![GitHub pull requests](https://img.shields.io/github/issues-pr/username/PowerShellAdminToolBox)

## 📜 Licence

Ce projet est sous licence [MIT](LICENSE) - voir le fichier LICENSE pour plus de détails.

## 🙏 Remerciements

- **Communauté PowerShell** pour l'inspiration et les retours
- **Contributeurs** qui font vivre ce projet
- **Microsoft** pour PowerShell Core et les APIs Graph/PnP

---

<div align="center">

**⭐ Si ce projet vous aide, n'hésitez pas à lui donner une étoile ! ⭐**

[🚀 Commencer](docs/USER_GUIDE.md) • [📖 Documentation](docs/) • [🤝 Contribuer](CONTRIBUTING.md) • [💬 Discussions](https://github.com/username/PowerShellAdminToolBox/discussions)

</div>