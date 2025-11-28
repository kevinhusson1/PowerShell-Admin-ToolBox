# Cahier des Charges v2.1 - Plateforme de Gestion "Script Tools Box"

## 1. Vision et Objectifs du Projet

### 1.1. Vision Globale
La "Script Tools Box" est une plateforme d'entreprise modulaire développée en PowerShell 7+ et WPF. Elle ne se contente pas de lancer des scripts : elle centralise la gouvernance, la sécurité et la configuration de l'écosystème d'automatisation de l'entreprise. Elle agit comme un intermédiaire intelligent entre l'Active Directory (On-Premise & Azure) et les scripts opérationnels.

### 1.2. Objectifs Clés
*   **Centralisation Totale :** La configuration, la sécurité et l'état des scripts sont stockés dans une base de données SQLite unique.
*   **Sécurité Hybride :** Authentification via Azure AD (Entra ID) en mode "Delegated Permissions", avec gestion fine des autorisations locales (RBAC).
*   **Expérience Utilisateur "SaaS" :** Une interface moderne, réactive et esthétique (Design System standardisé), capable de gérer des interactions complexes (modifications non sauvegardées, feedback visuel immédiat).
*   **Modularité Totale :** Chaque script est une "mini-application" autonome capable de fonctionner dans le lanceur ou en mode standalone.

---

## 2. Architecture Technique

### 2.1. Principes Fondamentaux
1.  **Single Source of Truth (SQLite) :**
    *   Le fichier `database.sqlite` est maître absolu : paramètres globaux, droits d'accès, états d'activation, logs de session.
    *   Les fichiers `manifest.json` ne sont que des métadonnées techniques immuables (ID, Nom, Fichier).

2.  **Isolation des Processus (Sandboxing) :**
    *   **Scripts Enfants :** Lancés dans un processus PowerShell distinct (`Start-Process`). Ils ne partagent pas la mémoire du lanceur pour éviter les crashs en cascade.
    *   **Authentification Azure :** Les tests de connexion et l'authentification se font dans des processus isolés pour éviter le gel de l'interface graphique (Deadlock UI).

3.  **Système de Traduction "Fractal" :**
    *   Architecture en mille-feuille : Chargement des traductions Globales + Traductions du Module + Traductions du Script Local.
    *   Performance : Moteur de remplacement basé sur Regex pour une hydratation instantanée du XAML.

4.  **Identité "Dual Mode" :**
    *   **Mode Lanceur (Esclave) :** Le script reçoit son jeton d'identité du Lanceur via un paramètre encodé. Le bouton d'auth est en lecture seule.
    *   **Mode Autonome (Maître) :** Le script gère sa propre connexion Azure via la configuration BDD. Le bouton d'auth est actif.

### 2.2. Stack Technique
*   **Langage :** PowerShell 7.4+
*   **Interface :** WPF (XAML) chargé dynamiquement avec injection de ressources (`DynamicResource`).
*   **Données :** SQLite (via module PSSQLite embarqué).
*   **Connectivité :** Microsoft.Graph (Module PowerShell).

---

## 3. Modèle de Données (SQLite)

Le schéma de la base de données `database.sqlite` est le cœur du système.

### 3.1. Tables de Configuration & Sécurité
| Table | Description | Colonnes Clés |
| :--- | :--- | :--- |
| **settings** | Paramètres globaux de l'application (Clé/Valeur typée). | `Key` (PK), `Value`, `Type` |
| **script_settings** | Configuration propre à chaque script. | `ScriptId` (PK), `IsEnabled` (bool), `MaxConcurrentRuns` (int) |
| **script_security** | Table de liaison définissant les droits d'accès (RBAC). | `ScriptId`, `ADGroup` (PK Composite) |
| **known_groups** | Bibliothèque des groupes AD/Azure validés. | `GroupName` (PK), `Description` |

### 3.2. Tables Opérationnelles
| Table | Description | Colonnes Clés |
| :--- | :--- | :--- |
| **active_sessions** | Verrous d'exécution en cours (Concurrency). | `RunID`, `ScriptName`, `OwnerPID`, `StartTime` |
| **script_progress** | Communication temps-réel (Script -> Lanceur). | `OwnerPID`, `ProgressPercentage`, `StatusMessage` |
| **permission_requests** | File d'attente des demandes de droits Azure. | `RequestID`, `RequesterUPN`, `RequestedScope`, `Status` |

---

## 4. Fonctionnalités de l'Interface (Launcher)

### 4.1. Accueil (Onglet Scripts)
*   **Mode Déconnecté :** Affiche un message "Connexion Requise". Aucun script n'est visible.
*   **Mode Connecté :** Grille de tuiles filtrée selon les droits de l'utilisateur (croisement Groupes Azure / Table `script_security`).
*   **Tuiles Intelligentes :** Affichent l'état de chargement (Barre de progression) et l'état d'exécution (Bordure verte + Animation).

### 4.2. Onglet Gestion (Admin Only) - *Design "Figma"*
Interface ergonomique divisée en deux colonnes pour le pilotage des scripts.
1.  **Colonne Navigation (Gauche) :**
    *   **Bibliothèque de Groupes :** Ajout/Suppression de groupes avec validation Azure AD en temps réel.
    *   **Liste des Scripts :** Liste visuelle avec indicateurs d'état (Pastille verte/grise).
2.  **Colonne Configuration (Droite) :**
    *   **Cartes Sémantiques :** 
        *   🟩 **État :** Switch Activé/Désactivé.
        *   🟧 **Exécution :** Réglage de la concurrence (Max Runs).
        *   🟪 **Sécurité :** Liste de Toggles pour activer/désactiver l'accès par groupe.
    *   **Protection des Données :**
        *   Détection des modifications non sauvegardées ("Dirty State").
        *   Bouton "Enregistrer" changeant d'aspect (Orange/Vert).
        *   Protection contre la navigation accidentelle (Popup "Ignorer les modifications ?" avec Rollback automatique).

### 4.3. Onglet Gouvernance (Admin Only)
Tableau de bord pour l'auto-gestion des droits Azure (Self-Management).
*   **Demandes :** Workflow d'approbation des scopes demandés par les scripts.
*   **Permissions Actives :** Audit en temps réel du Service Principal via Graph API.
*   **Actions :** Ajout manuel de permissions, Synchronisation, Lien vers le "Consentement Administrateur".

### 4.4. Onglet Paramètres (Admin Only)
Configuration technique stockée dans la table `settings`.
*   **Sections :** Général, Azure (Tenant/AppID), Sécurité (Groupe Admin), Active Directory (Service Account).
*   **Tests Intégrés :** Boutons de validation pour tester la connexion Azure, l'infra AD et les identifiants de service sans quitter l'interface.

---

## 5. Workflows & Sécurité

### 5.1. Démarrage et "Bootstrap"
1.  L'application se lance.
2.  **Mode Bootstrap :** Si la base est vide -> Accès Admin temporaire pour configuration initiale.
3.  **Mode Production :** L'accès Admin est verrouillé. L'utilisateur doit s'authentifier via Azure AD. L'application vérifie son appartenance au groupe Admin défini en BDD.

### 5.2. Synchronisation des Scripts (Backend)
À chaque démarrage :
1.  Scan du dossier `/Scripts`.
2.  **Nouveau script :** Création des entrées par défaut en BDD (Activé, MaxRuns=1, Sécurité=Groupe Admin).
3.  **Script existant :** Aucune modification (La BDD est prioritaire sur le JSON).

### 5.3. Lancement d'un Script (Flow)
1.  **Vérification Concurrence :** `Test-AppScriptLock` consulte la BDD (`active_sessions` vs `MaxConcurrentRuns`).
2.  **Lancement :** `Start-Process` avec passage des paramètres :
    *   `-LauncherPID` (Pour lier le cycle de vie).
    *   `-AuthContext` (Objet JSON en Base64 contenant le token Azure).
3.  **Suivi :** Le Launcher surveille le PID enfant via un Timer.
    *   Mise à jour de la barre de progression via la table `script_progress`.
    *   Nettoyage automatique du verrou (`active_sessions`) à la fermeture du processus (même en cas de crash).

### 5.4. Golden Master (Template)
Tous les scripts doivent être créés à partir du modèle `Scripts/Designer/DefaultUI`. Ce modèle implémente nativement :
*   Le chargement des modules Core/UI/Database.
*   La gestion du verrouillage BDD.
*   L'interface XAML standardisée (Header/Content/Footer).
*   Le module d'identité (affichage du user connecté).