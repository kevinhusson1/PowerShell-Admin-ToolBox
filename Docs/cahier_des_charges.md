# Cahier des Charges v3.0 - Plateforme de Gestion "Script Tools Box"

## 1. Vision et Objectifs du Projet

### 1.1. Vision Globale
La "Script Tools Box" est une plateforme d'entreprise modulaire développée en PowerShell 7+ et WPF. Elle centralise la gouvernance, la sécurité et la configuration de l'écosystème d'automatisation de l'entreprise.
**Evolution V3.0** : La plateforme pivote vers une architecture "Cloud-First" et "Zero Trust", minimisant l'empreinte locale et sécurisant les secrets via Azure.

### 1.2. Objectifs Clés
*   **Sécurité "Zero Trust" (Nouveau)** :
    *   **Zero Local Secret** : Aucun mot de passe ou certificat exportable ne doit résider sur le poste administrateur.
    *   **Identité Forte** : Utilisation exclusive du SSO Azure AD pour l'accès utilisateur et l'accès aux ressources (Key Vault).
*   **Centralisation Hybride** :
    *   Configuration locale (Cache SQLite) pour la performance hors-ligne.
    *   Configuration distante (Azure App Config / Blob) pour la gouvernance centralisée (Règles de nommage, Versions min).
*   **Expérience Utilisateur "SaaS"** : Interface WPF fluide, moderne et réactive.
*   **Modularité** : Architecture en "Plugins" où chaque script est indépendant.

---

## 2. Architecture Technique

### 2.1. Principes Fondamentaux
1.  **Hybride Data Model (SQLite + Cloud)** :
    *   `database.sqlite` (Local) : Cache de session, configuration utilisateur, logs temporaires.
    *   Azure (Distant) : Source de vérité pour les configurations critiques et les secrets.

2.  **Isolation des Processus (Sandboxing)** :
    *   Scripts enfants lancés via `Start-Process` pour éviter les crashs en cascade.
    *   Authentification déléguée : Le token est acquis par le Launcher et transmis de manière sécurisée (Cache MSAL partagé) aux enfants.

3.  **Identité et Sécurité** :
    *   **Utilisateur** : Authentification interactive MSAL (Delegated).
    *   **Application** : Authentification par Certificat (App-Only) pour les tâches de fond. Le certificat est stocké de manière sécurisée (Non-Exportable localement ou Azure Key Vault).

### 2.2. Stack Technique
*   **Langage** : PowerShell 7.4+ (Core)
*   **Interface** : WPF (XAML) avec Binding MVVM-like.
*   **Données** : SQLite (Module `PSSQLite`).
*   **Connectivité** : Microsoft.Graph SDK, PnP.PowerShell.

---

## 3. Modèle de Données (SQLite Local)

Le schéma local sert de relais de performance et de file d'attente hors-ligne.

### 3.1. Tables de Configuration
| Table | Description |
| :--- | :--- |
| **settings** | Paramètres techniques (TenantID, AppID, Chemins). |
| **script_settings** | Override local des paramètres de scripts (MaxRuns, Enabled). |
| **known_groups** | Cache des groupes AD/Azure utilisés fréquemment. |

### 3.2. Tables Opérationnelles
| Table | Description |
| :--- | :--- |
| **active_sessions** | Gestion des verrous d'exécution (Concurrency Control). |
| **permission_requests** | File d'attente locale des demandes de droits avant synchro Azure. |

---

## 4. Fonctionnalités de l'Interface (Launcher)

### 4.1. Accueil (Onglet Scripts)
*   Affichage filtré par droits (RBAC Azure).
*   Feedback temps-réel (Barre de progression, Status).

### 4.2. Onglet Gestion (Admin)
*   **Bibliothèque** : Gestion des groupes Azure AD autorisés.
*   **Visualisation** : État de santé des scripts, activation/désactivation rapide.
*   **Sécurité** : Association simple Script <-> Groupe Azure AD.

### 4.3. Onglet Gouvernance
*   **Approbation** : Validation des demandes de scopes d'API.
*   **Audit** : Vue des permissions accordées au Service Principal.

---

## 5. Workflows & Sécurité

### 5.1. Bootstrap Sécurisé
1.  **Premier lancement** : Configuration des IDs Azure (Tenant, App, Cert Thumbprint).
2.  **Validation** : Le Launcher vérifie la cohérence du certificat et des droits Graph API.

### 5.2. Lancement Sécurisé d'un Script
1.  **Autorisation** : Vérification des droits utilisateur (Membre du groupe autorisé ?).
2.  **Concurrence** : Vérification des verrous (`active_sessions`).
3.  **Démarrage** :
    *   Le Launcher prépare le contexte d'authentification.
    *   Le script enfant démarre et récupère la session Azure sans re-demander de credentials (SSO).

### 5.3. Standards de Développement
*   **Golden Master** : Tout script doit hériter du template `Scripts/Designer/DefaultUI`.
*   **Sanitization** : Toutes les entrées utilisateur doivent être validées et les requêtes SQL paramétrées.