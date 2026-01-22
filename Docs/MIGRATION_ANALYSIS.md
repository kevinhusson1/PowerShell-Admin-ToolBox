# ANALYSE DE L'EXISTANT & STRATÉGIE DE MIGRATION (V4 HYBRIDE)

## 1. ANALYSE PROFONDE DE L'EXISTANT (V2/V3)

### A. Structure des Données (SQLite)
Actuellement, `Config/database.sqlite` est le point de défaillance unique (SPOF).
*   **Contenu Mixte** : Il mélange de la configuration froide (`sp_templates`) et de l'état chaud (`active_sessions`, `script_progress`).
*   **Problème Majeur** : Les tables "Chaudes" (`active_sessions`) subissent des écritures fréquentent (polling) qui verrouillent le fichier pour les lectures de configuration ("Froides"), causant les crashs `SQL_BUSY`.

### B. Architecture des Scripts (Ex: SharePointBuilder)
Les scripts actuels sont des "Monolithes" autonomes.
*   **Ils font tout** : Chargement de DLLs, Initialisation BDD, Auth MSAL, Construction XAML, Gestion des événements UI.
*   **Redondance du Code** : Chaque script recharge `Microsoft.Identity.Client.dll`. Chaque script instancie sa connexion SQLite.
*   **Faiblesse** : Si on veut changer la couleur du thème sombre, il faut modifier le module UI et espérer que tous les scripts l'utilisent correctement.

### C. Gestion de Configuration
La configuration est stockée sous forme de chaînes JSON dans des colonnes TEXT de SQLite (ex: `sp_templates.StructureJson`). C'est flexible mais opaque pour le moteur SQL (pas de requêtes JSON faciles).

---

## 2. STRATÉGIE DE MIGRATION VERS "C# HOST"

### A. La Bataille du Stockage : Où vont les données ?

Dans la nouvelle architecture, nous allons **séparer les responsabilités** pour éliminer les verrous.

| Type de Donnée                            | Stockage Actuel            | Stockage Cible (V4)        | Justification                                                                                                  |
| :---------------------------------------- | :------------------------- | :------------------------- | :------------------------------------------------------------------------------------------------------------- |
| **État Runtime** (Jobs, Progress, RAM)    | SQLite (`active_sessions`) | **RAM (.NET Objects)**     | La barre de progression d'un script ne doit jamais toucher le disque dur. Le C# Host garde ça en mémoire vive. |
| **Config Statique** (Templates, Settings) | SQLite (`sp_templates`)    | **SQLite (Lecture Seule)** | Le Host charge la config au démarrage. Les scripts la demandent au Host (`Get-HostConfig`).                    |
| **Logs & Audit**                          | Fichiers/SQLite            | **SQLite (WAL Mode)**      | Seul le Thread de Logging du Host a le droit d'écriture. Aucun verrou possible.                                |
| **Secrets Utilisateur**                   | Fichiers Cache             | **MSAL Encryption**        | Géré 100% par le Host C#. Le script ne touche jamais au fichier de cache.                                      |

### B. Le Nouveau Contrat Script <-> Host

Le Script ne sera plus un programme autonome mais un **Service**.

**Exemple de Transformation :**

*Avant (`SharePointBuilder.ps1`)* :
```powershell
# Charge XAML, Connecte BDD, Affiche Fenêtre...
$window.ShowDialog()
```

*Après (`SharePointBuilder.ps1` - Migré)* :
```powershell
# Le Host a déjà chargé l'UI et l'Auth.
# Le script reçoit un objet $HostContext
param($HostContext)

function Start-Build {
    # Demande la config au Host (pas de SQL direct)
    $config = $HostContext.GetConfig("sp_templates")
    
    # Envoie du progrès au Host (pas d'écriture BDD)
    $HostContext.ReportProgress(10, "Initialisation...")
    
    # Fait le travail technique
    New-PnPSite -Url ...
}
```

### 3. ANALYSE DE FAISABILITÉ & RISQUES

#### Faisabilité : ÉLEVÉE (VERT)
*   **Technologies** : Nous restons sur PowerShell pour le métier. Le C# ne sert que de "cadre".
*   **Code Existant** : 80% du code des modules actuels (`Core`, `SharePoint`) est réutilisable tel quel. Seule la couche "UI" et "Data" de chaque script doit être retirée.

#### Points de Blocage Potentiels (ROUGE)
1.  **Auth "On-Behalf-Of"** : Comment le Host (C#) passe-t-il le token au Runspace PowerShell ?
    *   *Solution* : Injection de variable. Le Host fait `$Runspace.SessionStateProxy.SetVariable("Global:GraphToken", $token)`.
2.  **Affichage Dynamique** : Certains scripts (SharePoint) génèrent des formulaires dynamiques basés sur du JSON.
    *   *Solution* : Le script PowerShell peut renvoyer du XAML brut ou une définition JSON que le Host C# rendra.

#### Roadmap de Migration des Données
1.  **Backup** : Exporter `database.sqlite` en JSON complet.
2.  **Schema V4** : Créer le nouveau schéma SQLite allégé (sans tables `active_sessions`).
3.  **Import** : Réimporter les templates et settings.

### 4. CONCLUSION

Cette évolution est non seulement réalisable mais **simplificatrice**.
*   On supprime le code de gestion de fenêtre des scripts (moins de bugs).
*   On supprime les accès concurrents à SQLite (plus de crashs).
*   On centralise l'intelligence dans le Host C#.
