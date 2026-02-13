# 🗺️ Roadmap du Projet PowerShell Admin ToolBox

Ce document recense la vision à long terme, les chantiers techniques prioritaires et les fonctionnalités prévues. Il sert de guide pour transformer cet outil d'administration en une solution de niveau "Entreprise", sécurisée et scalable.

---

## 🎯 Vision & Objectifs

* **Sécurité "Zero Trust"** : Aucun secret ne doit résider sur le poste de l'administrateur.
* **Architecture Cloud-First** : Configuration et secrets pilotés depuis Azure.
* **Expérience Utilisateur (UX) Premium** : Une interface fluide, réactive et moderne (WPF).
* **Qualité Industrielle** : Code testable, typé et validé automatiquement (CI/CD).

---

## 🚨 Court Terme : Sécurité & Durcissement (v3.1)

*Priorité absolue : Combler les failles de sécurité identifiées lors de l'audit 2026.*

### 🛡️ Sécurité des Secrets (Immédiat)

* [x] **Suppression des Mots de Passe en Clair** : Retirer le stockage du mot de passe AD (`servicePassword`) de la base SQLite locale.

* [x] **Certificats Non-Exportables** : Modifier la procédure d'installation (`Install-AppCertificate.ps1`) pour interdire l'exportation de la clé privée depuis le magasin Windows.

* [x] **Sanitization SQL** : Remplacer l'échappement manuel des chaînes (`Replace("'", "''")`) par des requêtes paramétrées pour prévenir les injections SQL.

### 🧹 Nettoyage & Robustesse

* [x] **Gestion des Verrous** : Améliorer la résilience du mécanisme de verrouillage (`active_sessions`) pour gérer les crashs du Launcher (nettoyage au démarrage).
* [x] **Dépendances** : Mettre en place un script de mise à jour automatique pour `Vendor\PSSQLite`.

---

## 🛠️ Moyen Terme : Modernisation & Industrialisation (v3.5)

*Objectif : Rendre le code plus maintenable, performant et testable.*

### 💻 Modernisation du Code PowerShell

* [ ] **Adoption des Classes (Class-based)** : Remplacer les `PSCustomObject` par des classes PowerShell 7+ typées (ex: `class AppConfig`, `class AppScript`).
  * *Gain* : Autocomplétion, validation de type à la compilation, meilleures performances.

* [ ] **Refonte du Logging** : Migrer vers un système de logs structurés (JSON) compatible avec Azure Log Analytics.

### 🧪 Qualité & Tests

* [ ] **Tests Unitaires (Pester)** : Créer une suite de tests pour valider les modules "Core" et "Database" avant tout déploiement.
  * Validation des fichiers de configuration JSON.
  * Validation des migrations de schéma SQLite.

* [ ] **Pipeline CI/CD** : Automatiser l'analyse statique du code (PSScriptAnalyzer) à chaque commit.

---

## 🚀 Long Terme : Architecture v4 "Cloud Native"

*Objectif : Découpler totalement l'outil du poste de travail.*

### ☁️ Configuration Centralisée

* [ ] **Remote Settings** : Déplacer la configuration des scripts (règles, versions) vers Azure App Configuration ou un Blob Storage JSON.
  * *Avantage* : Mise à jour des règles de nommage ou les versions minimales sans redéployer l'outil chez les clients.

### 🔐 Zero Local Secret (Azure Key Vault)

* [ ] **Intégration Azure Key Vault** :
  * Stocker le certificat `.pfx` dans AKV.
  * Le Launcher s'authentifie via son utilisateur Azure AD (SSO).
  * Le certificat est récupéré **en mémoire RAM uniquement** pour établir la connexion PnP/Graph.
  * **Aucune écriture sur disque**.

---

## ✨ Fonctionnalités & UI/UX (Backlog)

*Améliorations visibles pour l'utilisateur final.*

### Interface Graphique

* [ ] **Dashboard d'Accueil** : Vue synthétique de l'état des services (Azure AD, SharePoint, Exchange).

* [ ] **Système de Notifications** : "Toasts" WPF pour alerter l'utilisateur sans bloquer l'interface (remplacement des MessageBox intrusives).
* [ ] **Thèmes Personnalisés** : Sélecteur de thème (Dark/Light/High Contrast) persistant.

### Fonctionnalités SharePoint

* [ ] **Gestion des Sites Hub** : Interface graphique pour associer/dissocier des sites aux Hubs.

* [ ] **Site Designs** : Application de modèles de sites (Site Scripts) via l'interface.

### Fonctionnalités Active Directory

* [ ] **Audit des Groupes** : Rapport visuel des membres des groupes sensibles (Admins du domaine).

* [ ] **Délégation** : Interface simplifiée pour déléguer des droits sur des OU spécifiques.
