# Architecture Technique - Script Tools Box (V3)

## Vue d'Ensemble

L'architecture repose sur un modèle **"Hub & Spoke"** où le **Launcher** agit comme le Hub central de sécurité et de gouvernance, et les **Scripts** sont des rayons (Spokes) exécutés dans des processus isolés.

```mermaid
graph TD
    subgraph "Launcher (Master Process)"
        L[Launcher.ps1] -->|Gère| DB[(SQLite Database)]
        L -->|Affiche| UI[WPF Dashboard]
        L -->|Authentifie| Azure[Azure AD (MSAL)]
    end

    subgraph "Child Process (Sandboxed)"
        S1[Script A]
        S2[Script B]
    end

    L -->|Start-Process w/ Auth Token| S1
    L -->|Start-Process w/ Auth Token| S2
    
    S1 -.->|Read/Write| DB
    S2 -.->|Read/Write| DB
    
    S1 -->|API Calls (SSO)| Graph[Microsoft Graph]
    S2 -->|API Calls (SSO)| SPO[SharePoint Online]
```

## Flux de Données

### 1. Authentification (Shared Token Cache)

Pour éviter que chaque script ne redemande une authentification à l'utilisateur :

1. Le **Launcher** s'authentifie interactivement (`User.Read`).
2. Le cache de token MSAL est stocké de manière sécurisée au niveau utilisateur Windows.
3. Lors du lancement d'un script enfant, le Launcher passe l'UPN et le ClientID.
4. Le script enfant utilise `Connect-MgGraph -ContextScope CurrentUser` pour réhydrater la session sans interaction (SSO).

### 2. Concurrence et Verrouillage

La base de données SQLite agit comme un sémaphore global.

* **Table `active_sessions`** : Chaque script s'y enregistre au démarrage (`RunID`, `PID`).
* **Check** : Avant lancement, le Launcher vérifie `COUNT(*)` vs `MaxConcurrentRuns`.
* **Cleanup** : Un Timer dans le Launcher vérifie si les PID listés dans la base sont toujours vivants. Si non, le verrou est supprimé (Self-Healing).

## Structure des Modules

| Module        | Rôle                                              |
| :------------ | :------------------------------------------------ |
| **Core**      | "Kernel" de l'application. Gestion config.        |
| **Database**  | ORM léger pour SQLite.                            |
| **Azure**     | Wrapper MSAL et Graph API.                        |
| **UI**        | Composants visuels, Styles, Thèmes.               |
| **Toolbox.*** | Bibliothèques métiers (AD, SharePoint, Security). |

## Sécurité des Secrets (V3 Target)

* **Certificats** : Stockés dans `Cert:\CurrentUser\My` avec flag **NonExportable**.
* **Mots de passe** : Aucun stockage local. Utilisation de **Azure Key Vault** (Roadmap V4) ou saisie à la volée.
