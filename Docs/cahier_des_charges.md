# Cahier des Charges v2.0 - Plateforme de Gestion "Script Tools Box"

## 1. Vision et Objectifs du Projet

### 1.1. Vision Globale
La "Script Tools Box" est une plateforme d'entreprise modulaire développée en PowerShell 7+ et WPF. Elle ne se contente pas de lancer des scripts : elle centralise la gouvernance, la sécurité et la configuration de l'écosystème d'automatisation de l'entreprise. Elle agit comme un intermédiaire intelligent entre l'Active Directory (On-Premise & Azure) et les scripts opérationnels.

### 1.2. Objectifs Clés
*   **Centralisation Totale :** La configuration, la sécurité et l'état des scripts sont stockés dans une base de données unique.
*   **Sécurité Hybride :** Authentification via Azure AD (Entra ID) pour l'identité, mais gestion fine des autorisations (RBAC) via la base de données locale.
*   **Gouvernance Azure Dynamique :** Capacité pour l'application de gérer ses propres permissions API (Scopes) et de valider les membres des groupes directement depuis l'interface.
*   **Expérience Utilisateur Adaptative :** L'interface change radicalement selon que l'utilisateur est un Administrateur (Tableaux de bord, Gestion) ou un Utilisateur Standard (Liste épurée).

---

## 2. Architecture Technique

### 2.1. Principes Fondamentaux
1.  **Base de Données comme Source de Vérité (Single Source of Truth) :**
    *   Le fichier `database.sqlite` contient tout : paramètres globaux, droits d'accès aux scripts, état d'activation, bibliothèque de groupes, et logs de session.
    *   Les fichiers ne servent qu'au code. La politique est dans la donnée.

2.  **Séparation Manifeste / Politique :**
    *   Le fichier `manifest.json` d'un script ne définit que ses caractéristiques techniques inmuables (ID, Nom, Fichier).
    *   La sécurité (qui a le droit ?) et la configuration (est-il actif ?) sont définies en base de données via l'interface de gestion.

3.  **Authentification Utilisateur Exclusive :**
    *   Abandon de l'authentification par certificat (Service Principal) pour le lanceur.
    *   L'application utilise des "Delegated Permissions". Chaque action est tracée au nom de l'utilisateur connecté.
    *   L'application possède des droits élevés (`Application.ReadWrite.All`, `Directory.Read.All`) lui permettant de s'auto-gérer via l'interface d'administration.

4.  **Verrouillage Distribué :**
    *   Gestion de la concurrence (MaxConcurrentRuns) via la table `active_sessions` pour empêcher les conflits d'exécution, même sur des sessions multiples.

### 2.2. Stack Technique
*   **Langage :** PowerShell 7.4+
*   **Interface :** WPF (XAML) chargé dynamiquement.
*   **Données :** SQLite (via module PSSQLite embarqué).
*   **Connectivité :** Microsoft.Graph (Module PowerShell).

---

## 3. Modèle de Données (SQLite)

Le schéma de la base de données `database.sqlite` est le cœur du système.

### 3.1. Tables de Configuration & Sécurité
| Table | Description | Colonnes Clés |
| :--- | :--- | :--- |
| **settings** | Paramètres globaux de l'application (Clé/Valeur). | `Key` (PK), `Value`, `Type` |
| **script_settings** | Configuration propre à chaque script (surcharge le manifest). | `ScriptId` (PK), `IsEnabled` (bool), `MaxConcurrentRuns` (int) |
| **script_security** | Table de liaison définissant les droits d'accès (N-N). | `ScriptId`, `ADGroup` (PK Composite) |
| **known_groups** | Bibliothèque des groupes AD/Azure validés et utilisables. | `GroupName` (PK), `Description` |

### 3.2. Tables Opérationnelles
| Table | Description | Colonnes Clés |
| :--- | :--- | :--- |
| **active_sessions** | Verrous d'exécution en cours. | `RunID`, `ScriptName`, `OwnerPID`, `StartTime` |
| **script_progress** | Communication temps-réel (Script -> Lanceur). | `OwnerPID`, `ProgressPercentage`, `StatusMessage` |
| **permission_requests** | File d'attente des demandes de droits utilisateurs. | `RequestID`, `RequesterUPN`, `RequestedScope`, `Status` |

---

## 4. Le Manifeste de Script (manifest.json)

Le manifeste est désormais allégé. Il ne contient plus de données de sécurité.

```json
{
    "id": "Create-User-v1",             // Identifiant unique technique
    "scriptFile": "CreateUser.ps1",     // Point d'entrée
    "lockFile": "CreateUser.lock",      // (Legacy/Optionnel)
    "name": "scripts.create-user.name", // Clé de traduction
    "description": "scripts.create-user.description", // Clé de traduction
    "version": "1.0.0",
    "category": "UserManagement",
    "author": "Service IT",
    "icon": { 
        "type": "png", 
        "value": "user-add.png",
        "backgroundColor": "#3b82f6" 
    }
    // Note : Pas de "security" ni "enabled" ici. C'est géré par la BDD.
}
```

## 5. Fonctionnalités de l'Interface (Launcher)

### 5.1. Accueil (Onglet Scripts)
*   **Mode Déconnecté :** Affiche un message de verrouillage ("Connexion Requise") et masque les listes. Aucun script n'est visible par sécurité.
*   **Mode Connecté (Utilisateur) :** Affiche uniquement les scripts pour lesquels l'utilisateur appartient à un groupe autorisé (vérification croisée entre ses groupes Azure et la table `script_security`).
*   **Mode Connecté (Admin) :** Affiche tous les scripts.
*   **Barre d'état :** Affiche le nombre de scripts *visibles* (filtrés par l'état activé) et le nombre de scripts *en cours d'exécution*.

### 5.2. Onglet Gouvernance (Admin Only)
Un tableau de bord en 3 colonnes pour gérer la relation avec Azure AD.
1.  **Demandes en attente :** Liste les demandes d'élévation de privilèges des utilisateurs (stockées en BDD).
    *   *Actions :* Valider (Déclenche l'ajout dans Azure) / Refuser.
2.  **Permissions Actives :** Affiche les permissions API (Scopes) réelles de l'application (lues depuis Azure via `Get-AppServicePrincipalPermissions`).
    *   *Indicateurs :* Vert (Consentement accordé) / Orange (Consentement manquant).
    *   *Actions :* "Ajouter manuellement" (Injection via Graph API), "Valider les droits" (Lancement URL Admin Consent), "Synchroniser".
3.  **Membres & Rôles :** Audit en temps réel des membres du groupe Administrateur configuré.

### 5.3. Onglet Gestion (Admin Only)
L'interface de pilotage des scripts (CRUD) et de la sécurité granulaire.
*   **Bibliothèque de Groupes (Gauche-Haut) :** 
    *   Zone pour ajouter des groupes Azure AD à une liste de "Groupes Connus".
    *   Vérification en temps réel de l'existence du groupe dans Azure avant ajout.
    *   Suppression possible via bouton corbeille.
*   **Liste des Scripts (Gauche-Bas) :** 
    *   Liste de tous les scripts détectés sur le disque.
    *   Indicateur visuel d'état (Pastille Verte=Actif, Grise=Inactif).
*   **Panneau de Détail (Droite) :**
    *   Switch **Activé/Désactivé** (Impact immédiat pour tous les utilisateurs).
    *   Configuration du **Max Concurrent Runs** (Nombre d'instances simultanées globales).
    *   **Sécurité & Accès :** Liste à cocher générée depuis la Bibliothèque de Groupes. Cocher une case autorise immédiatement le groupe pour ce script.

### 5.4. Onglet Paramètres (Admin Only)
Configuration technique de l'application (stockée dans la table `settings`).
*   **Général :** Nom de l'entreprise, Langue, Logs Verbose, Dimensions de la fenêtre Admin.
*   **Azure :** Tenant ID, App ID, Scopes par défaut.
*   **Sécurité :** Définition du groupe Administrateur (Clé de voûte de l'accès).
*   **Active Directory :** Configuration du compte de service On-Prem et des serveurs (AD Connect, Fichiers).
    *   Boutons de validation technique : "Tester les identifiants", "Valider les serveurs", "Valider les objets AD".

---

## 6. Workflows & Sécurité

### 6.1. Démarrage et "Bootstrap"
1.  L'application se lance.
2.  **Mode Bootstrap :** Si la base est vide OU si l'App ID Azure est manquant -> L'accès Admin est accordé temporairement pour permettre la configuration initiale.
3.  **Mode Verrouillé :** Si la config est présente -> L'accès Admin est refusé par défaut. L'utilisateur doit se connecter via le bouton d'authentification.

### 6.2. Synchronisation des Scripts (Backend)
À chaque démarrage ou action d'administration (via `Sync-AppScriptSettings`) :
1.  Le système scanne le dossier `/Scripts`.
2.  **Nouveau script ?** 
    *   Création de l'entrée dans `script_settings` (Enabled=1, MaxRuns=1).
    *   Création de l'entrée dans `script_security` (Ajout du groupe Admin par défaut pour sécurité).
3.  **Script existant ?** 
    *   On ne touche à rien. La base de données est prioritaire sur le fichier `manifest.json`.

### 6.3. Exécution d'un Script
1.  L'utilisateur double-clique sur une tuile.
2.  `Start-AppScript` est appelé.
3.  **Vérification 1 (Disponibilité) :** Le script est-il `Enabled` en BDD ?
4.  **Vérification 2 (Sécurité) :** L'utilisateur connecté appartient-il à un des groupes listés dans `script_security` pour cet ID ?
5.  **Vérification 3 (Concurrence) :** Le nombre d'instances en cours (table `active_sessions`) est-il inférieur au `MaxConcurrentRuns` de la BDD ?
6.  Si tout est OK -> Lancement du processus enfant isolé avec passage du `LauncherPID`.
7.  Enregistrement du verrou dans `active_sessions`.

### 6.4. Gestion des Droits Azure (Self-Management)
*   L'application utilise la permission `Application.ReadWrite.All` (consentie au préalable) pour modifier son propre objet Service Principal.
*   Lorsqu'un admin ajoute une permission (ex: `Mail.Read`) via l'onglet Gouvernance, le Launcher appelle l'API Graph (`Update-MgApplication`) pour mettre à jour le manifeste de l'application dans Azure.