# Plan Directeur de Migration : Script Tools Box V3.0 (Enterprise Edition)

**Version** : 3.0.0-DRAFT  
**Type** : Architecture & Roadmap  
**Statut** : Document de Référence Technique  
**Objectif** : Transition d'une collection de scripts vers une architecture applicative modulaire, asynchrone et sécurisée.

## 1. Vision et Principes Directeurs

L'objectif de la V3 est de transformer la "Toolbox" en une plateforme d'entreprise capable d'héberger n'importe quel outil d'administration sans compromettre la stabilité du lanceur principal ni la sécurité des identifiants.

### Les 4 Piliers de l'Architecture V3

*   **Local-First & Zero-Shared-State** : SQLite est strictement réservé à l'état local (cache, file d'attente). Aucune dépendance à une base de données sur partage réseau (SMB) pour éviter les verrous et la corruption.
*   **Hub & Spoke Asynchrone** : Le Launcher (Hub) ne fait rien de bloquant. Les Outils (Spokes) tournent dans des processus isolés et communiquent via Named Pipes (et non plus via fichiers ou DB polling).
*   **Identité Zero-Trust** : Les secrets ne sont jamais stockés en clair. Utilisation stricte de MSAL avec DPAPI (protection via l'identité Windows de l'utilisateur).
*   **Industrialisation (The Factory)** : Tout nouvel outil est généré par un template (Plaster). Le code est validé par un Linter (PSScriptAnalyzer) avant d'être accepté.

## 2. Architecture Technique Cible

### 2.1 Nouvelle Arborescence Standardisée

Cette structure sépare clairement le "Moteur" (Engine) des "Fonctionnalités" (Tools).

```text
/ScriptToolsBox
│
├── /Launcher.ps1            # Point d'entrée unique (Bootstrap & Update Check)
├── /ScriptToolsBox.psd1     # Manifeste global (Versionning du produit)
│
├── /Bin                     # Binaires et DLLs externes (non-PowerShell)
│   ├── sqlite3.dll
│   └── Microsoft.Identity.Client.dll
│
├── /Config                  # Configuration statique (JSON)
│   └── appsettings.json     # URLs API, TenantID par défaut (PAS DE SECRETS)
│
├── /Data                    # DONNÉES LOCALES (Exclu du Git)
│   ├── local.db             # SQLite (Session, Cache, Job Queue)
│   ├── logs.ndjson          # Logs structurés locaux
│   └── TokenCache.bin       # Cache MSAL crypté DPAPI
│
├── /Docs                    # Documentation technique
│
├── /Engine                  # Le Framework V3 (Cœur technique)
│   ├── /STB.Core            # Gestion des Processus, Named Pipes, Logging
│   ├── /STB.Database        # Abstraction SQLite (DAL) + Gestion WAL
│   ├── /STB.Identity        # Wrapper MSAL + Token Refresh
│   └── /STB.UI              # Composants XAML partagés, Thèmes, Styles
│
├── /Tools                   # Les Plugins Métiers (Ex-Scripts)
│   ├── /AD_UserManagement   # Exemple d'outil
│   │   ├── /Assets          # Icônes spécifiques
│   │   ├── /Localization    # fr-FR.json
│   │   ├── tool.manifest.json # Définition (Titre, Icône, Scopes requis)
│   │   ├── View.xaml        # Interface (Zéro Code-Behind)
│   │   └── Controller.ps1   # Logique métier (Reçoit le Context du Launcher)
│   └── /SharePoint_Builder
│
├── /Tests                   # Tests Unitaires (Pester)
│
└── /Vendor                  # Modules PowerShell externes gérés par PSDepend
    ├── /PSSQLite
    └── /ImportExcel
```

## 3. Spécifications Techniques Critiques

### 3.1 Base de Données (SQLite)
*   **Usage** : Uniquement pour la persistance locale (historique, cache).
*   **Mode Obligatoire** : `PRAGMA journal_mode=WAL;` doit être exécuté à chaque ouverture de connexion pour permettre la lecture/écriture simultanée.
*   **Gestion des Verrous** : `PRAGMA busy_timeout = 3000;` pour gérer automatiquement les micro-conflits.

### 3.2 Communication Inter-Processus (IPC)
*   **Problème V2** : Le Launcher lit la DB ou des fichiers pour savoir ce que fait le script enfant. C'est lent et génère des I/O disques inutiles.
*   **Solution V3 (Named Pipes)** :
    *   **Launcher (Serveur)** : Ouvre un pipe nommé `\\.\pipe\STB_Log_{ProcessID}`.
    *   **Outil (Client)** : Se connecte au pipe et envoie des objets JSON (Wait-Job n'est plus utilisé pour le monitoring temps réel).
    *   **Protocole** : NDJSON (Newline Delimited JSON) circulant dans le pipe.

### 3.3 Sécurité & Identité
*   **Stockage** : Utilisation de `Microsoft.Identity.Client.Extensions.Msal` pour écrire le cache de token sur disque protégé par **Windows DPAPI**. Le fichier ne peut être décrypté que par l'utilisateur courant sur sa machine.
*   **Passage de Contexte** : Le Launcher ne passe pas de token en paramètre (trop risqué si logging des commandes). Il passe un `AccountID`. Le script enfant utilise cet ID pour demander silencieusement le token au cache partagé sécurisé.

## 4. Roadmap de Migration (12 Semaines)

### Phase 1 : Fondations & Outillage (Semaines 1-2)
**Objectif** : Mettre en place l'usine logicielle avant de toucher au code métier.

- [ ] **Initialisation Git** : Créer la branche `develop-v3`.
- [ ] **Nettoyage** : Déplacer les scripts existants dans un dossier `_Legacy` pour référence.
- [ ] **Dépendances** : Configurer `PSDepend` et le fichier `requirements.psd1` pour installer `PSSQLite`, `Pester`, `Plaster`.
- [ ] **Scaffolding** : Créer le template Plaster `NewToolTemplate`.
    - *Livrable* : Une commande `Invoke-Plaster` génère un dossier d'outil conforme à la V3.
- [ ] **Linting** : Configurer `PSScriptAnalyzer` pour interdire `Write-Host` et l'usage direct de `System.Data.SQLite`.

### Phase 2 : Le Cœur (Engine Development) (Semaines 3-6)
**Objectif** : Construire le moteur qui fera tourner les outils.

- [ ] **Module STB.Core** :
    - Implémenter le `NamedPipeServer` (réception des logs asynchrones).
    - Créer le système de Logging centralisé (écriture dans `Data/logs.ndjson`).
- [ ] **Module STB.Database** :
    - Créer le wrapper `Invoke-STBQuery`.
    - Implémenter l'auto-maintenance (WAL Checkpoint).
- [ ] **Module STB.Identity** :
    - Intégrer la DLL MSAL.
    - Créer `Connect-STBLauncher` (Interactif) et `Connect-STBTool` (Silencieux).
- [ ] **Module STB.UI** :
    - Créer la fenêtre principale (Launcher Dashboard) en WPF pur avec un Frame de navigation.

### Phase 3 : Migration des Outils Pilotes (Semaines 7-9)
**Objectif** : Migrer 2 outils complexes pour valider l'architecture.

- [ ] **Pilote 1 : UserManagement (AD/Azure)**
    - Refondre l'UI en XAML "Logicless" (Binding uniquement).
    - Remplacer les appels SQL directs par `STB.Database`.
    - Remplacer `Write-Host` par `Send-STBLog` (qui écrit dans le Pipe).
- [ ] **Pilote 2 : SharePointBuilder**
    - Tester le chargement de grosses listes sans figer l'UI (Pattern `Dispatcher.InvokeAsync`).

### Phase 4 : Consolidation & Packaging (Semaines 10-12)
**Objectif** : Rendre la solution déployable.

- [ ] **Script de Build** : Créer `build.ps1` (Invoke-Build).
    - Nettoie les fichiers temporaires.
    - Exécute les tests Pester.
    - Vérifie la syntaxe (Analyzer).
    - Versionne le manifeste.
- [ ] **Mise à jour Auto** : Implémenter une logique simple dans `Launcher.ps1` qui compare son Hash avec une version sur URL/Partage et se met à jour si nécessaire.
- [ ] **Documentation** : Générer la doc des commandes via `PlatyPS`.

## 5. Règles de Développement (Developer Standards)

Pour garantir la maintenabilité, tout contributeur doit respecter ces règles impératives :

| Domaine   | Règle                | Justification                                                                                                                      |
| :-------- | :------------------- | :--------------------------------------------------------------------------------------------------------------------------------- |
| **UX**    | **Zéro Freeze**      | Interdiction d'exécuter du code lent (>200ms) sur le thread UI. Utiliser `Start-ThreadJob` ou `Runspaces`.                         |
| **Data**  | **Pas de SQL brut**  | Interdiction d'utiliser `Invoke-SqliteQuery` dans les outils. Passer par le module `STB.Database`.                                 |
| **Code**  | **Typage Fort**      | Utiliser `[string]$Nom` et des `Class` PowerShell plutôt que des `PSCustomObject` non typés.                                       |
| **Logs**  | **Structurés**       | Pas de texte libre. Les logs doivent être des objets (Timestamp, Source, Level, Message, Context).                                 |
| **Error** | **Try/Catch Global** | Chaque outil doit avoir un `Try/Catch` au niveau le plus haut qui capture toute erreur fatale et l'envoie au Launcher via le Pipe. |

## 6. Stratégie de Déploiement

Pour répondre au besoin de flexibilité ("N'importe quelle organisation") :

1.  **Mode Portable** : L'application est livrée sous forme d'archive ZIP ou d'EXE auto-extractible. Elle ne nécessite pas d'installation dans Program Files ni de droits Admin locaux (sauf si les scripts eux-mêmes le demandent pour leurs actions).
2.  **Configuration Dynamique** : Au premier lancement, si `Data/local.db` n'existe pas, le Launcher le crée et applique les schémas SQL (Migrations).
3.  **Indépendance** : Le dossier `/Vendor` contient **TOUS** les modules nécessaires. L'application n'essaie jamais de télécharger des modules depuis Internet (PSGallery) lors de l'exécution chez le client (souvent bloqué par proxy). Tout est "vendored" au moment du Build.