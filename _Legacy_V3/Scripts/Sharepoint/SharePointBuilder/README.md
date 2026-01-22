# Documentation Technique - SharePoint Builder v3.0

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

### 3. Éditeur de Modèles Visuel

Permet de manipuler des structures JSON complexes sans éditer le texte manuellement :

- Gestion complète de l'arborescence (Ajout Racine/Enfant, Suppression).
- Configuration détaillée des nœuds :
  - **Permissions** : Gestion fine des droits (Utilisateurs/Groupes Azure AD).
  - **Tags** : Métadonnées SharePoint (Taxonomie ou Champs Texte).
  - **Publications** : Création de liens transverses (`.url`) sécurisés vers d'autres sites.
- Feedback visuel en temps réel et validation des données.

### 4. Authentification Hybride

L'application gère deux contextes d'authentification parallèles :

- **Microsoft Graph** (via `Connect-AppGraph`) : Pour la récupération de l'identité utilisateur et les opérations transverses Azure AD.
- **PnP PowerShell** (via `Connect-AppSharePoint`) : Pour toutes les opérations SharePoint. Supporte l'authentification **App-Only** (Certificat) pour les opérations "Sadmin" et **Interactive** pour l'accès standard.

### 5. Système de Logging Centralisé

- Module `Logging` avec la fonction `Write-AppLog`.
- Supporte l'écriture multiple : Console (Verbose), Interface UI (RichTextBox), et Collection (Listes.
- Format standardisé `[HH:mm:ss] [LEVEL] Message` garantissant une traçabilité uniforme entre le lanceur, l'application et les jobs enfants.

### 6. Validation Avancée (Multi-Niveaux)

Le Builder intègre un moteur de validation pré-déploiement (`Test-AppSPModel`) opérant en 3 passes :

- **Niveau 1 (Statique)** : Analyse syntaxique, longueur des noms, caractères interdits.
- **Niveau 2 (Connecté)** : Vérification de l'existence des users/groupes Azure AD et de la bibliothèque cible.
- **Niveau 3 (Métadonnées)** : Validation des colonnes et termes taxonomiques sur le site cible.
Les résultats sont présentés avec localisation précise des erreurs (Node Path).

---

## ⚠️ Points d'Attention pour la Maintenance

1. **Thread UI & Dispatcher** : Toute modification de l'interface depuis un thread secondaire (ex: retour de timer ou event async) doit passer par le Dispatcher WPF.
2. **Localisation** : Ne pas coder de texte en dur dans le XAML. Ajouter une entrée dans `fr-FR.json` et utiliser `##loc:sp_builder.ma_cle##`.
3. **Module PnP** : Le module `Toolbox.SharePoint` charge dynamiquement le module `Logging`. En cas de modification des dépendances, vérifier `Toolbox.SharePoint.psm1`.
4. **Schema Database** : Si vous ajoutez des colonnes aux tables SQLite, pensez à ajouter une étape de migration dans `Initialize-AppDatabase.ps1` (pattern "Check if column exists, if not ADD COLUMN").
