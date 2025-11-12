# Cahier des Charges v2.0 - Plateforme de Scripts "Script Tools Box"
## 1. Vision et Objectifs du Projet
### 1.1. Vision Globale
Développer une plateforme modulaire, transportable et pilotée par les données permettant de centraliser, sécuriser et exécuter des scripts PowerShell dotés d'interfaces graphiques au sein d'une entreprise.
### 1.2. Objectifs Clés Atteints
`Modularité Extrême :` L'application est découpée en modules fonctionnels (Core, Database, UI, LauncherUI, etc.).
`Autonomie des Scripts :` Chaque script est une application 100% autonome, responsable de son propre cycle de vie.
`Configuration Centralisée :` Tous les paramètres sont stockés dans une base de données SQLite unique, modifiable via l'interface.
`Sécurité Basée sur Azure AD :` L'accès aux scripts et aux fonctionnalités d'administration est contrôlé par l'appartenance à des groupes Azure AD.
`Transportabilité :` L'application est autonome, avec sa seule dépendance (PSSQLite) embarquée dans le projet.
## 2. Architecture Technique
### 2.1. Principes Fondamentaux
1) `Autonomie des Scripts Enfants :` Le lanceur ne fait que démarrer des processus. Chaque script est responsable de sa propre initialisation (configuration, authentification, verrouillage) et de son nettoyage. Il n'y a aucun passage de contexte via des fichiers de session.
2) `Base de Données comme Source de Vérité Unique :` Un seul fichier database.sqlite centralise la configuration de l'application, les paramètres de sécurité et l'état des verrous d'exécution. Les fichiers .json de configuration ont été abandonnés.
3) `Verrouillage Distribué via la Base de Données :` Un système de verrouillage basé sur la table active_sessions de la base de données empêche les exécutions multiples non désirées, y compris entre différentes machines (si la base de données est sur un partage réseau).
4) `Authentification par Cache Partagé :` L'authentification repose sur le cache de jetons du module Microsoft.Graph, offrant une expérience de "Single Sign-On" transparente entre le lanceur et les scripts enfants.
5) `Modularité Stricte :` Le code est organisé en modules PowerShell distincts avec des responsabilités claires. Le Launcher.ps1 est un simple orchestrateur, toute la logique complexe est déléguée aux modules.
### 2.2. Technologies et Dépendances
* Langage : PowerShell 7+
* Framework UI : WPF (Windows Presentation Foundation)
* Base de Données : SQLite
* Dépendances Embarquées :
PSSQLite : Module PowerShell stocké dans le dossier /Vendor pour interagir avec la base de données.
* Dépendances Externes (Prérequis sur le poste client) :
Microsoft.Graph : Pour l'authentification et les appels à l'API Microsoft Graph.

## 3. Arborescence du Projet

Toolbox/
├── Launcher.ps1                      # Point d'entrée principal, simple orchestrateur.
│
├─ Config/
│  └─ database.sqlite                # SOURCE DE VÉRITÉ UNIQUE : config, sécurité, verrous.
│
├─ Docs/
│  └─ cahier_des_charges.md            # Ce document.
│
├─ Localization/                       # Traductions globales du lanceur.
│  ├─ en-US.json
│  └─ fr-FR.json
│
├─ Logs/                               # Dossier pour les futurs logs sur fichier.
│
├─ Modules/                            # API interne de l'application.
│  ├─ Azure/                          # Gère l'interaction avec Azure AD (connexion, groupes).
│  ├─ Core/                           # Fonctions de base (découverte de scripts, abstraction de la config).
│  ├─ Database/                       # Seul module autorisé à parler à la base de données.
│  ├─ LauncherUI/                     # Toute la logique de l'interface du lanceur.
│  ├─ Localization/                   # Moteur de traduction.
│  ├─ Logging/                        # Moteur de logging (Write-AppLog).
│  └─ UI/                             # Fonctions UI génériques (chargement XAML, composants).
│
├─ Scripts/                            # Contient tous les outils métier.
│  └─ UserManagement/
│     └─ CreateUser/                  # Exemple de script 100% autonome.
│        ├─ Localization/              # Traductions spécifiques à ce script.
│        ├─ CreateUser.ps1             # Le code du script.
│        ├─ CreateUser.xaml            # L'interface du script.
│        └─ manifest.json              # Métadonnées et contrat de sécurité du script.
│
├─ Templates/                          # Fichiers XAML réutilisables.
│  └─ ...
│
└─ Vendor/                             # Dépendances tierces embarquées.
   └─ PSSQLite/
      └─ ...
## 4. La Base de Données (database.sqlite)
Le cœur de l'application. Initialisée et mise à jour automatiquement.
#### Table `settings`
| Colonne | Type | Description                                          | Exemple Clé                | Exemple Valeur |
|---------|------|------------------------------------------------------|----------------------------|----------------|
| Key     |	TEXT | Nom unique du paramètre (ex: ui.launcherWidth).      | `app.companyName`          | `VOSGELIS`     |
| Value   |	TEXT | Valeur du paramètre, toujours stockée en texte.      | `ui.launcherHeight`        | `750`          |
| Type    |	TEXT | Type de données original (string, integer, boolean). | `security.startupAuthMode` | `User`         |
#### Table `active_sessions`
| Colonne    | Type    | Description                                 |
|------------|---------|---------------------------------------------|
| RunID      |	INTEGER | Clé primaire unique pour chaque exécution.  |
| ScriptName |	TEXT	  | id du script en cours (depuis le manifest). |
| OwnerPID   |	INTEGER | PID du processus détenant le verrou.        |
| OwnerHost  |	TEXT	  | Nom de la machine où le script s'exécute.   |
| StartTime  |	TEXT	  | Horodatage du début de l'exécution.         |

## 5. Le Manifeste de Script (manifest.json)
Chaque script doit fournir un manifeste qui est son contrat avec le lanceur et le système de verrouillage.
Clé	Obligatoire	Description
id	Oui	Identifiant unique du script (ex: create-user-v1).
scriptFile	Oui	Nom du fichier .ps1 à exécuter.
name	Oui	Clé de traduction pour le nom affiché du script.
description	Oui	Clé de traduction pour la description.
security.allowedADGroups	Non	Tableau de noms de groupes Azure AD. Si présent, seuls les membres peuvent voir et exécuter le script. Si absent, le script est public.
maxConcurrentRuns	Non	Nombre d'exécutions simultanées autorisées. 1 par défaut. -1 pour illimité.
icon	Non	Objet décrivant l'icône à afficher dans le lanceur.
...		version, author, category, etc.
## 6. Workflows Clés
### 6.1. Démarrage du Lanceur
1.  Charge les modules (y compris `PSSQLite` embarqué).
2.  Appelle `Initialize-AppDatabase` qui vérifie/crée le schéma de la DB.
3.  Appelle `Get-AppConfiguration` pour charger tous les paramètres depuis la DB dans `$Global:AppConfig`.
4.  Lit le paramètre `security.startupAuthMode` depuis la configuration. Si la valeur est `User`, tente une connexion automatique via `Connect-MgGraph` (qui sera silencieuse si un jeton est en cache).
5.  Appelle `Get-FilteredAndEnrichedScripts` qui filtre les scripts visibles en fonction des droits de l'utilisateur (s'il est connecté) ou affiche les scripts publics (s'il est en mode Système).
6.  Charge l'interface WPF et la peuple avec les données.
6.2. Cycle de Vie d'un Script Enfant (ex: CreateUser.ps1)
Démarrage : Le script est lancé (par le lanceur ou en autonome).
Prérequis : Charge les assemblages WPF et importe tous les modules nécessaires.
Verrouillage :
Appelle Initialize-AppDatabase.
Lit son propre manifest.json.
Appelle Test-AppScriptLock pour vérifier les limites de concurrence dans la DB. Si la limite est atteinte, il s'arrête.
Appelle Add-AppScriptLock pour enregistrer sa session (avec son propre $PID) dans la DB.
Initialisation :
Appelle Get-AppConfiguration pour charger les paramètres.
Appelle Connect-MgGraph (utilise le cache si disponible).
Charge ses traductions locales avec Add-AppLocalizationSource.
Exécution : Charge son XAML, affiche sa fenêtre et exécute sa logique métier.
Nettoyage (finally block) :
Appelle toujours Unlock-AppScriptLock -OwnerPID $PID pour supprimer sa propre entrée de la table active_sessions.
S'il a été lancé en autonome, il supprime son fichier de session de développement.

## 7. Logging
Le système de logging est centralisé autour de la fonction Write-AppLog.
Write-AppLog : Fonction universelle qui formate un message et peut l'écrire dans le flux Verbose. Elle peut aussi le transmettre à une RichTextBox via la fonction Update-AppRichTextBox du module UI.
Write-LauncherLog : Fonction privée au lanceur qui appelle Write-AppLog en ciblant la RichTextBox du journal principal.
Chaque script enfant est responsable d'instancier sa propre RichTextBox et de la passer à Write-AppLog pour son logging interne.