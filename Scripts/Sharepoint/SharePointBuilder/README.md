# Documentation Technique - SharePoint Builder v3.2

## 📋 Présentation

Le **SharePoint Builder** est une "usine de déploiement" conçue pour standardiser et automatiser la création d'architectures documentaires dans SharePoint Online. C'est une application graphique (GUI) basée sur PowerShell et WPF, intégrant des fonctionnalités avancées de gestion de modèles et de suivi de déploiement.

## 🛠 Architecture Technique

### Structure du Projet

Le script est organisé de manière modulaire pour séparer la vue (XAML) de la logique métier (PowerShell) :

- `SharePointBuilder.ps1` : **Point d'entrée**. Initialise l'environnement, charge les modules, connecte la base de données, gère l'authentification et lance l'interface graphique.
- `SharePointBuilder.xaml` : Définition de l'interface utilisateur en **WPF**. Utilise un système de "tokens" (`##loc:key##`) pour la localisation.
- `Functions/Logic/` : Contient les contrôleurs d'événements (Architecture V3 Modulaire) :
  - `Register-SiteEvents.ps1` : Explorateur de cible (Target Explorer), navigation PnP et pagination.
  - `Register-DeployEvents.ps1` : Moteur de déploiement (Jobs), validation (Test-AppSPModel) et persistance.
  - `Register-EditorLogic.ps1` : Contrôleur de l'éditeur de modèles (TreeListView CRUD complet).
  - `Register-FormEditorLogic.ps1` : Éditeur de règles de nommage (Dynamic Forms).
- `Localization/fr-FR.json` : Fichier de ressources pour la traduction de l'interface.

### Base de Données (SQLite)

L'application utilise une base de données locale SQLite pour la persistance :

- **Table `sp_deploy_configs`** : Sauvegarde des configurations de déploiement (Site, Biblio, Modèle, Dossier Cible, Options).
- **Table `sp_templates`** : Stockage des modèles de structure (JSON).
- **Table `sp_naming_rules`** : Règles de nommage pour les formulaires de destination.

---

## 🚀 Fonctionnalités Clés & Implémentation

### 1. Déploiement Asynchrone (Non-Bloquant)

Pour éviter de geler l'interface graphique (liée au Thread UI unique de WPF) lors des opérations longues PnP :

- Utilisation exclusive de `Start-Job` pour exécuter la logique de provisionning (`New-AppSPStructure`) dans un processus séparé.
- **Communication Inter-Processus** : Le Job renvoie des objets logs structurés via `Write-AppLog -PassThru`.
- **Streaming de Logs** : L'interface écoute les résultats du Job en temps réel via un `DispatcherTimer` et met à jour la `RichTextBox` et la `ProgressBar`.

### 2. Explorateur de Cible (TreeView Avancé)

L'arbre de sélection du dossier cible (`TargetExplorerTreeView`) implémente des logiques complexes pour la performance et l'UX :

- **Lazy Loading** : Les sous-dossiers ne sont chargés que lors de l'extension d'un nœud.
- **Pagination Client-Side** : Pour les dossiers contenant des milliers d'éléments, seuls les 10 premiers sont affichés, avec un bouton "Charger la suite..." pour éviter le freeze.
- **Auto-Pilot (Restauration)** : Lors du chargement d'une config sauvegardée, un algorithme récursif asynchrone développe automatiquement l'arbre niveau par niveau jusqu'au dossier cible sauvegardé.

### 3. Éditeur de Modèles Visuel (UX/UI v3.1)

Permet de manipuler des structures JSON complexes sans éditer le texte manuellement. La version 3.1 introduit une refonte ergonomique :

- **Toolbar Modernisée** : Remplacement des boutons textes par des icônes explicites avec Tooltips localisés.
- **Nouveaux Types de Nœuds** :
  - **Liens Internes** : Navigation intra-site.
  - **Publications** : Raccourcis vers d'autres collections de sites.
- **Configuration Avancée** :
  - **Permissions** : Gestion fine des droits sur les Dossiers.
  - **Tags** : Métadonnées SharePoint (Statiques ou Dynamiques).

### 4. Liens Internes & Navigation

Le Builder supporte désormais la création de **Liens Internes**, permettant de créer des raccourcis de navigation au sein même de la structure déployée.

- **Mapping d'IDs** : Avant le déploiement, le moteur indexe tous les dossiers cibles avec un ID unique.
- **Résolution Dynamique** : Lors de la création du lien, le moteur résout le chemin physique final (`/sites/MonSite/MaLib/MonDossierTarget`).
- **Implémentation** : Création de fichiers `.url` natifs SharePoint, supportant les métadonnées.

### 5. Gestion Avancée des Métadonnées (Moteur de Tags v2)

Le moteur d'application des tags (`New-AppSPStructure`) a été entièrement réécrit pour garantir l'intégrité des données existantes :

- **Mode "Append" (Non-Destructif)** : Le moteur lit les tags déjà présents sur un élément, les fusionne avec les nouveaux tags du modèle, et réapplique l'ensemble.
- **Support Multi-Valeurs (Arrays)** : Les tags multiples sont passés sous forme de vecteurs (`Array`) à PnP PowerShell.
- **Récupération d'Identité Robuste** : Utilisation de `Get-PnPFile -AsListItem` pour manipuler les fichiers complexes.

### 6. Authentification Hybride

L'application gère deux contextes d'authentification parallèles :

- **Microsoft Graph** (via `Connect-AppGraph`) : Pour la récupération de l'identité utilisateur.
- **PnP PowerShell** (via `Connect-AppSharePoint`) : Pour toutes les opérations SharePoint.

### 7. Système de Logging Centralisé

- Module `Logging` avec la fonction `Write-AppLog`.
- Supporte l'écriture multiple : Console (Verbose), Interface UI (RichTextBox), et Collection.
- Format standardisé `[HH:mm:ss] [LEVEL] Message`.

### 8. Validation Avancée (Multi-Niveaux)

Le Builder intègre un moteur de validation pré-déploiement (`Test-AppSPModel`) opérant en 3 passes :

- **Niveau 1 (Statique)** : Analyse syntaxique, longueur des noms, caractères interdits.
- **Niveau 2 (Connecté)** : Vérification de l'existence des users/groupes Azure AD et de la bibliothèque cible.
- **Niveau 3 (Métadonnées)** : Validation des colonnes et termes taxonomiques sur le site cible.

---

## ⚡ Nouveautés v3.2

### 9. Tags Dynamiques (Dynamic Metadata)

Les Tags Dynamiques permettent de définir une métadonnée dont la **valeur** ne sera connue qu'au moment du déploiement (saisie via formulaire).

- **Concept** : Associe une Colonne SharePoint (ex: `CodeClient`) à une Variable de Formulaire (ex: `NumDossier`).
- **Fonctionnement** :
    1. Dans l'éditeur, ajoutez un Tag Dynamique (Icône ⚡).
    2. Sélectionnez la Règle de Nommage source.
    3. Sélectionnez la variable (ex: `Annee`).
    4. Lors du déploiement, l'utilisateur saisit "2024" dans le formulaire.
    5. Le dossier créé reçoit le Tag `Annee` = "2024".

### 10. Options de Déploiement

- **Activation Métadonnées Racine** : Une nouvelle case à cocher "Appliquer les métadonnées sur ce dossier ?" permet de décider si le dossier racine (conteneur global) doit recevoir les tags ou rester neutre.
- **Support Multi-Utilisateurs (Publications)** : Le champ "Grant Access" des publications supporte désormais une liste d'emails séparés par virgule (ex: `user1@domaine.com, user2@domaine.com`), avec tentative de création de compte si l'utilisateur est inconnu.

### 11. Gestion Simplifiée des Publications

- La gestion des droits, auparavant intégrée aux nœuds "Publication", a été retirée pour plus de clarté.
- **Bonne pratique** : Les permissions doivent être définies explicitement sur le **dossier** cible lui-même, garantissant une lecture immédiate et sans équivoque de la sécurité dans l'arborescence.


### 12. Système de Tracking & Persistance (v3.3)

Le SharePoint Builder intègre désormais un système complet de traçabilité des déploiements ("Tracking").

- **Objectif** : Historiser chaque création de dossier et permettre la maintenance future (Renommage, Drift Detection).
- **Fonctionnement** :
    - Chaque dossier déployé est marqué avec un **GUID Unique** dans son Property Bag (`_AppDeploymentId`).
    - Une liste cachée **`App_DeploymentHistory`** est créée sur chaque site cible.
    - Cette liste stocke un **Snapshot Complet** du déploiement :
        - Le JSON de la structure (Arborescence).
        - Le JSON du formulaire (Structure des champs).
        - Les valeurs saisies par l'utilisateur.
- **Bénéfice** : Permet de reconstruire intégralement le contexte d'un dossier sans dépendre de la base de données locale de l'application.

> Pour plus de détails techniques, consulter : [Docs/SharePointBuilder-TrackingSystem.md](Docs/SharePointBuilder-TrackingSystem.md)

---


## 📝 Exemple de Scénario Complet

Voici un exemple de structure JSON typique supportée par le Builder v3.2 :

```json
{
  "Name": "Dossier Projet",
  "Folders": [
    {
      "Name": "01. Administratif",
      "Permissions": [
        { "Email": "direction@entreprise.com", "Level": "Full Control" }
      ],
      "Tags": [
        { "Name": "Confidence", "Value": "High" },       // Tag statique
        { "IsDynamic": true, "SourceVar": "CodeProjet" } // Tag dynamique
      ]
    },
    {
        "Name": "02. Technique",
        "Folders": [
            { "Name": "Plans", "Id": "PLANS_ROOT" },
            { "Name": "Rapports" }
        ]
    },
    {
        "Type": "InternalLink",
        "Name": "Accès Rapide Plans",
        "TargetNodeId": "PLANS_ROOT"
    },
    {
        "Type": "Publication",
        "Name": "Liens vers Archive 2023",
        "TargetSiteUrl": "https://tenant.sharepoint.com/sites/Archives",
        "TargetFolderPath": "/Documents Partages/2023"
    }
  ]
}
```

## ⚠️ Points d'Attention pour la Maintenance

1. **Thread UI & Dispatcher** : Toute modification de l'interface depuis un thread secondaire (ex: retour de timer ou event async) doit passer par le Dispatcher WPF.
2. **Localisation** : Ne pas coder de texte en dur dans le XAML. Ajouter une entrée dans `fr-FR.json` et utiliser `##loc:sp_builder.ma_cle##`.
3. **Module PnP** : Le module `Toolbox.SharePoint` charge dynamiquement le module `Logging`. En cas de modification des dépendances, vérifier `Toolbox.SharePoint.psm1`.
4. **Schema Database** : Si vous ajoutez des colonnes aux tables SQLite, pensez à ajouter une étape de migration dans `Initialize-AppDatabase.ps1`.
