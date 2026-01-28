# SharePoint Deployer

**SharePoint Deployer** est l'interface utilisateur destinée aux opérateurs pour déployer des structures SharePoint standardisées en se basant sur des configurations prédéfinies par les administrateurs (via SharePoint Builder).

## Fonctionnalités Principales

*   **Catalogue de Configurations** : Affiche uniquement les configurations autorisées pour l'utilisateur connecté (filtrage par Groupes Azure AD).
*   **Formulaire Dynamique** : Génère automatiquement les champs de saisie basés sur les Règles de Nommage définies.
*   **Prévisualisation** : Affiche en temps réel le nom du dossier qui sera créé.
*   **Déploiement Asynchrone** : Exécute le déploiement en arrière-plan sans bloquer l'interface, avec logs en temps réel.
*   **Gestion des Métadonnées** : Supporte l'application automatique de métadonnées et le remplissage dynamique des tags `{Variable}` dans le modèle.

## Architecture Technique

Le script repose sur une architecture modulaire **Event-Driven** (Pilotée par événements) en PowerShell + WPF/XAML.

### Structure des Fichiers

*   **`SharePointDeployer.ps1`** : Point d'entrée. Initialise l'environnement, charge les modules, l'authentification et l'interface XAML.
*   **`SharePointDeployer.xaml`** : Définition de l'interface utilisateur (Structure, Styles, DataTemplates).
*   **`Functions/`** :
    *   **`Initialize-DeployerLogic.ps1`** : Orchestrateur qui charge les composants logiques et initialise les contrôles.
    *   **`Logic/`** :
        *   **`Get-DeployerControls.ps1`** : Mappe les éléments XAML dans une Hashtable `$Ctrl` pour un accès facile.
        *   **`Register-ConfigEvents.ps1`** : Gère le chargement des configurations depuis la BDD SQLite et le filtrage des droits.
        *   **`Register-FormEvents.ps1`** : Génère dynamiquement les champs du formulaire (TextBox, ComboBox) et gère la prévisualisation.
        *   **`Register-ActionEvents.ps1`** : Gère le clic sur "Déployer", la validation, et le lancement du Job d'arrière-plan.

### Flux de Données

1.  **Chargement** : `Register-ConfigEvents` interroge `sp_deploy_configs` (SQLite) et filtre selon les groupes de l'utilisateur.
2.  **Sélection** : L'utilisateur choisit une config. `Register-FormEvents` lit la règle de nommage associée (JSON) et dessine le formulaire.
3.  **Saisie** : L'utilisateur remplit les champs. Les valeurs sont stockées dans les contrôles UI.
4.  **Déploiement** :
    *   `Register-ActionEvents` extrait les données du formulaire (`FormValues`).
    *   Il sépare les valeurs servant aux Tags Dynamiques et celles à appliquer comme Métadonnées sur le dossier racine.
    *   Il lance un Job PowerShell (`Start-Job`) appelant `New-AppSPStructure` (Module `Toolbox.SharePoint`).
    *   Un `DispatcherTimer` remonte les logs du Job vers l'UI.

## Pré-requis

*   Module `PSSQLite`
*   Module `Toolbox.SharePoint`
*   Accès à la base de données SQLite configurée (`sp_deploy_configs`).
*   Authentification Azure AD valide avec droits sur les sites cibles.

## Utilisation

Lancer via le **Launcher** ou en ligne de commande :
```powershell
.\SharePointDeployer.ps1
```
*(Le Launcher passera automatiquement le contexte d'authentification)*
