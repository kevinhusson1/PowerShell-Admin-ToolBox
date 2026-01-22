---
trigger: always_on
---

# STANDARDS DE DÉVELOPPEMENT V4 (HYBRIDE)

Ce document définit les règles impératives pour tout développement sur le projet "Script Tools Box V4".

## 1. VISION & RESPONSABILITÉ

L'application est **Hybride** :

* **C# (.NET 8)** : C'est le STRUCTUREL (Hébergement, Affichage, Threading).
* **PowerShell 7** : C'est le FONCTIONNEL (La logique métier scriptée).

> **Règle d'Or** : Si ça concerne comment l'app *s'affiche* ou *tourne*, c'est du C#. Si c'est ce que l'app *fait* (créer un user AD, un site SP), c'est du PowerShell.

---

## 2. RÈGLES C# (LE HOST)

### 2.1 Conventions de Nommage

* **Classes/Méthodes/Propriétés** : `PascalCase` (`public class MainWindow`, `public void Initialize()`).
* **Champs privés** : `_camelCase` (`private readonly ILogger _logger;`).
* **Interfaces** : `IPascalCase` (`IAuthenticationService`).
* **Variables locales** : `camelCase` (`var userList = ...`).

### 2.2 Architecture

* **MVVM** : Obligatoire pour toute interface WPF.
  * `Views/*.xaml` : XAML pur (pas de code-behind logique).
  * `ViewModels/*ViewModel.cs` : Logique de présentation.
  * `Models/*.cs` : Données pures.
* **Dependency Injection** : Utiliser le conteneur intégré pour injecter les services. Pas de `new MyService()` dans les ViewModels.

### 2.3 Asynchronisme

* **Async/Await** : Tout I/O (Fichier, Réseau, DB) DOIT être asynchrone.
* **Suffixe** : Les méthodes asynchrones finissent par `Async` (`ConnectAsync()`).
* **UI Thread** : Ne jamais bloquer le thread UI (`.Result` ou `.Wait()` sont interdits). Utiliser `await`.

---

## 3. RÈGLES POWERSHELL (LES SCRIPTS)

### 3.1 Structure "Headless"

Les scripts V4 ne doivent **JAMAIS** :

* Charger `System.Windows.*` ou `PresentationFramework`.
* Utiliser `Write-Host` (Utiliser `$HostContext.Log()`).
* Utiliser `Read-Host` (Utiliser `$HostContext.Prompt()`).
* Gérer l'authentification MSAL (Le token est injecté).

### 3.2 Conventions

* **Encodage** : UTF-8 (sans BOM si possible, ou avec BOM pour compatibilité).
* **Fonctions** : `Verb-Noun` standard (`Get-STBUser`).
* **Gestion d'erreur** : `Try/Catch` obligatoire. Remonter les erreurs via `$HostContext.LogError()`.

---

## 4. RÈGLES DE DONNÉES

### 4.1 SQL & Configuration

* **Lecture Seule** : Les scripts ne doivent pas écrire dans la configuration globale.
* **Typage** : Utiliser Entity Framework Core côté C# pour l'accès aux données.
* **WAL** : La base SQLite est toujours ouverte en mode `Write-Ahead Logging`.

### 4.2 Sécurité

* **Zéro Secret** : Aucun mot de passe en dur.
* **DPAPI** : Les tokens sont stockés cryptés par le Host.

---

## 5. ENVIRONNEMENT & OUTILLAGE

### 5.1 Fichiers de Configuration

Chaque projet doit inclure :

* `.editorconfig` : Pour forcer le style de code (indents, accolades).
* `ruleset.xml` : Pour les règles d'analyse statique.

### 5.2 Git Flow

* **Branches** :
  * `main` : Prod stable.
  * `develop-v4` : Dev courant.
  * `feature/ma-feature` : Travail unitaire.
* **Commits** : Messages en Français, impératifs (`Ajoute le service de logs` et non `J'ai ajouté...`).

---

## 6. VALIDATION AUTOMATIQUE

Tout code poussé doit passer :

1. **Build** : `dotnet build` sans erreur ni warning critique.
2. **Lint PS** : `Invoke-ScriptAnalyzer` sans erreur Sévérité 1.
