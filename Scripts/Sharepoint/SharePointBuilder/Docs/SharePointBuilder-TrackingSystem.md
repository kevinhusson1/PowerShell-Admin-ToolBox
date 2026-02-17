# Système de Tracking & Persistance (SharePoint Builder)

> **Version** : 1.0  
> **Date** : Février 2026  
> **Module** : Toolbox.SharePoint

## 🎯 Objectif

Le système de Tracking a pour but de **tracer** chaque déploiement effectué par le SharePoint Builder afin de :
1.  Garder un historique des opérations (Qui, Quoi, Quand, Où).
2.  Permettre la reconstruction du contexte de déploiement (Templates, Formulaires) même si les données sources ont été modifiées ou supprimées de l'application.
3.  Servir de fondation pour les outils de maintenance (Renamer v2, Drift Detection) en identifiant formellement les dossiers gérés par l'outil.

## 🏗 Architecture Technique

Le système repose sur un modèle "Hub & Spoke" léger :
- **L'Application (Hub)** : Orchestre le déploiement et pousse les données.
- **La Liste (Spoke)** : Stocke l'historique localement sur chaque Site cible.
- **Le Dossier (Target)** : Porte un marqueur unique (ID).

### 1. La Liste `App_DeploymentHistory`

C'est une liste SharePoint **cachée** (`Hidden = $true`) créée automatiquement à la racine de chaque site cible lors du premier déploiement.

| Champ                  | Type | Description                                                         |
| :--------------------- | :--- | :------------------------------------------------------------------ |
| **Title**              | Text | **Deployment ID** (GUID). Clé unique du déploiement.                |
| **TargetUrl**          | Text | URL relative du dossier déployé (ex: `/sites/RH/Docs/Projet A`).    |
| **TemplateId**         | Text | ID du modèle d'arborescence utilisé.                                |
| **TemplateVersion**    | Text | Timestamp de la version du modèle.                                  |
| **ConfigName**         | Text | Nom de la configuration de déploiement utilisée.                    |
| **NamingRuleId**       | Text | ID de la règle de nommage (Formulaire).                             |
| **DeployedBy**         | Text | Nom/UPN de l'utilisateur ayant lancé le déploiement.                |
| **TemplateJson**       | Note | **Snapshot JSON** complet de la structure déployée.                 |
| **FormValuesJson**     | Note | Valeurs saisies par l'utilisateur (ex: `{"YEAR":"2025"}`).          |
| **FormDefinitionJson** | Note | **Schéma JSON** du formulaire utilisé. Permet de reconstruire l'UI. |

> **Pourquoi du JSON ?**  
> Plutôt que de créer des colonnes SharePoint dynamiques pour chaque champ de formulaire (ce qui polluerait le site et atteindrait vite les limites de SharePoint), nous stockons la définition et les valeurs sous forme de JSON sérialisé. Cela garantit une flexibilité totale et une indépendance vis-à-vis du schéma de liste.

### 2. Le Marquage (Property Bag)

Chaque dossier racine déployé reçoit une métadonnée invisible (Property Bag) contenant son ID de déploiement.

- **Clé** : `_AppDeploymentId`
- **Valeur** : GUID (Correspond au champ `Title` de la liste d'historique).

Ce lien permet à n'importe quel outil (comme le futur *Project Manager*) de scanner une bibliothèque et de savoir instantanément :
1. "Ce dossier est-il géré par l'outil ?" (Présence du Property Bag)
2. "Quelle est son histoire ?" (Lookup dans la liste `App_DeploymentHistory` via le GUID).

## 🔄 Flux de Données

1.  **Préparation** (`Register-DeployEvents.ps1`) :
    - L'application compile les données du formulaire, le JSON du modèle, et le JSON de la règle de nommage.
    - Tout est empaqueté dans un objet `$TrackingInfo`.

2.  **Exécution** (`New-AppSPStructure.ps1`) :
    - Le moteur vérifie/crée la liste `App_DeploymentHistory`.
    - Il génère un nouveau GUID (`$deployId`).
    - Il estampille le dossier cible avec `_AppDeploymentId = $deployId`.
    - Il crée une nouvelle entrée dans la liste avec toutes les données JSON.

## 🛠 Commandes Utiles

### Vérifier un dossier (PowerShell PnP)
```powershell
$folder = Resolve-PnPFolder -SiteRelativePath "Shared Documents/MonDossier"
$folder.EnsureProperties("Properties")
Write-Host "Deployment ID: $($folder.Properties["_AppDeploymentId"])"
```

### Supprimer/Reset la Liste d'Historique
Si la liste est corrompue ou pour repartir de zéro :
```powershell
Remove-PnPList -Identity "App_DeploymentHistory" -Force
# La liste sera recréée automatiquement au prochain déploiement.
```
