# SharePoint Deployer

## Description

L'outil **SharePoint Deployer** est une application graphique PowerShell (WPF) conçue pour simplifier et standardiser le déploiement de structures de dossiers, de permissions et de métadonnées dans SharePoint Online. Il permet aux utilisateurs de sélectionner des configurations pré-établies et de générer des dossiers respectant des règles de nommage strictes sans erreur manuelle.

## Fonctionnalités Principales

### 1. Interface Utilisateur Intuitive

- **Liste des Configurations** : Affichage clair des types de déploiements disponibles (ex: "Dossier Projet", "Appel d'offre", etc.), avec icône et description.
- **Formulaire Dynamique** : Génération automatique des champs de saisie (Texte, Listes déroulantes) basés sur la règle de nommage associée à la configuration choisie.
- **Prévisualisation en Temps Réel** : Affichage immédiat du nom du dossier qui sera créé (format : `DossierParent/NomDynamique`).
- **Support Multi-langue** : Interface entièrement localisée (via module de localisation).

### 2. Déploiement Automatisé

- **Création de Structure** : Déploie une arborescence complète de dossiers définie dans un modèle JSON (Template).
- **Gestion des Permissions** : Applique automatiquement les droits d'accès (Lecture, Contribution, Contrôle Total) sur les dossiers créés pour des utilisateurs ou groupes spécifiques.
- **Métadonnées (Tags)** : Associe des métadonnées SharePoint aux dossiers pour faciliter la recherche et le classement.
- **Raccourcis** : Capacité de créer des fichiers raccourcis (`.url`) à l'intérieur de l'arborescence générée.

### 3. Gestion Avancée des Dossiers

- **Dossier Parent Optionnel** : Possibilité de spécifier un dossier parent (existant ou à créer) pour classer le nouveau déploiement. L'outil gère la création récursive du chemin complet.
- **Validation des Données** : Système de validation qui avertit l'utilisateur si des champs du formulaire de nommage sont laissés vides avant le lancement.
- **Support des Chemins Complexes** : Gestion robuste des chemins profonds et conversion automatique des chemins en format "Site Relative" pour éviter les erreurs de permissions PnP.

### 4. Sécurité et Architecture

- **Authentification Azure AD** : Utilise le contexte de l'utilisateur connecté (Interactive) pour garantir que les actions sont effectuées avec ses propres droits d'accès.
- **Exécution Asynchrone** : Le processus de déploiement s'exécute dans un Job d'arrière-plan pour ne pas figer l'interface graphique.
- **Logs Détaillés** : Journal d'exécution intégré affichant chaque étape du processus (Connexion, Création, Permissions, Erreurs) avec un code couleur pour une lecture rapide.
- **Accès Direct** : Bouton "Ouvrir destination" disponible en fin de traitement (si succès) pour accéder immédiatement au dossier créé dans le navigateur.

## Pré-requis Techniques

- Environnement Windows avec PowerShell 5.1 ou ultérieur.
- Module PowerShell **PnP.PowerShell** installé.
- Accès à la base de données de configuration SQLite du projet.
- Modules internes du Toolbox chargés : `Toolbox.SharePoint`, `UI`, `Localization`.

## Guide d'Utilisation

1.  **Lancement** : Exécuter le script via le Launcher principal ou directement via `SharePointDeployer.ps1`.
2.  **Sélection** : Choisir une configuration cible dans le volet de gauche.
3.  **Saisie** :
    - Remplir les champs du formulaire dynamique (ex: Année, Type, Nom Projet).
    - (Optionnel) Indiquer un "Dossier Parent" pour organiser le classement.
4.  **Déploiement** :
    - Vérifier le nom final dans la zone de prévisualisation ("Nom : ...").
    - Cliquer sur le bouton **"DÉPLOYER"**.
    - Confirmer l'action si un avertissement de champ vide apparaît.
5.  **Suivi** : Consulter les logs en bas de fenêtre pour suivre l'avancement.
6.  **Accès** : Une fois le message "Déploiement terminé" affiché, cliquer sur le bouton **"Ouvrir destination"** (icône grise qui devient active) pour vérifier le résultat sur SharePoint.

## Architecture Technique (V3)

L'application suit l'architecture V3 modulaire du projet, séparant l'interface (XAML), la logique d'initialisation, et les gestionnaires d'événements.

### Structure des Fichiers

- `SharePointDeployer.ps1` : Point d'entrée, chargement des modules et BDD.
- `Functions/Initialize-DeployerLogic.ps1` : Orchestrateur principal.
- `Functions/Logic/` :
  - `Get-DeployerControls.ps1` : Mapping des objets UI (WPF).
  - `Register-ConfigEvents.ps1` : Chargement des configs (SQLite) et gestion de l'identité.
  - `Register-FormEvents.ps1` : Logique du formulaire dynamique et preview temps réel.
  - `Register-ActionEvents.ps1` : Exécution du déploiement (Job Asynchrone) et logs.

---

_Documentation générée pour le projet PowerShell-Admin-ToolBox._
