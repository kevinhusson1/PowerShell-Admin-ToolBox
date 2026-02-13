# 🛠️ SharePoint Renamer (ToolBox Plugin)

**Version**: 1.0.0
**Auteur**: Service IT
**Catégorie**: SharePoint / Maintenance

## 📋 Description
Le **SharePoint Renamer** est un outil de maintenance avancé conçu pour renommer des dossiers racines (ou sous-dossiers) dans SharePoint tout en préservant l'intégrité des données. Contrairement à un simple renommage via l'interface web, cet outil effectue un **"Deep Update"** (Mise à jour en profondeur).

### Fonctionnalités Clés
1.  **Renommage Atomique** : Utilise l'API PnP pour renommer le dossier physique.
2.  **Réparation des Liens** : Scanne tous les fichiers à l'intérieur du dossier renommé pour corriger les liens absolus cassés (ex: raccourcis Excel, liens HTML).
3.  **Mise à Jour Structurelle** : Ré-applique le modèle (Template) JSON associé au dossier. Cela inclut :
    *   Mise à jour des **Métadonnées** (Tags) sur le dossier et son contenu.
    *   Mise à jour des **Permissions** (si définies dans le modèle).
    *   Mise à jour des **Publications** (Raccourcis/Links) pointant vers ce dossier depuis d'autres sites.

## 🏗️ Architecture Technique
L'outil suit l'architecture standard "ToolBox Plugin" (WPF + PowerShell).

### Structure des Fichiers
*   `SharePointRenamer.ps1` : :rocket: **Point d'entrée**. Gère l'authentification, le chargement des modules, l'affichage de la fenêtre WPF (`ShowDialog`) et la boucle de messages.
*   `SharePointRenamer.xaml` : :art: **Interface Utilisateur**. Définition XAML de la fenêtre.
*   `manifest.json` : :page_facing_up: **Métadonnées**. ID, Version, Droits requis.
*   `Functions/Initialize-RenamerLogic.ps1` : :brain: **Orchestrateur**. Charge les sous-fonctions et initialise les événements.

### Modules Logiques (`Functions/Logic/`)
*   `Get-RenamerControls.ps1` : Mappe les objets XAML vers une Hashtable PowerShell `$Ctrl` pour un accès facile.
*   `Register-RenamerConfigEvents.ps1` : Gère le chargement de la configuration (Liste des Templates, Règles de nommage).
*   `Register-RenamerPickerEvents.ps1` : Gère l'ouverture du sélecteur de dossier (Folder Browser).
*   `Show-SPFolderPicker.ps1` : Fenêtre modale de sélection de dossier SharePoint.
*   `Register-RenamerFormEvents.ps1` : Gère le formulaire dynamique (champs de métadonnées générés selon le Template).
*   `Register-RenamerActionEvents.ps1` : :dvd: **Cœur du réacteur**. Contient la logique du bouton "Renommer", le **Job** d'arrière-plan, et le timer de logs.

## 🚀 Utilisation
1.  **Sélectionner une Configuration** : Choisir un modèle (ex: "Chantier", "Projet") dans la liste de gauche.
2.  **Choisir un Dossier** : Utiliser le bouton "Sélectionner..." pour parcourir SharePoint et choisir le dossier à renommer.
3.  **Remplir le Formulaire** : Saisir les nouvelles métadonnées (Code, Année, etc.).
4.  **Prévisualisation** : Le nouveau nom est calculé automatiquement selon les règles de nommage.
5.  **Exécuter** : Cliquer sur "Renommer".
    *   Une fenêtre de log affiche la progression.
    *   À la fin, le bouton "Ouvrir destination" permet d'accéder au nouveau dossier.

## ⚙️ Détails Techniques (Dev)
*   **Background Jobs** : Le renommage s'exécute dans un `Start-Job` pour ne pas figer l'UI.
*   **Logging** : Les logs sont capturés via `Receive-Job` et affichés en temps réel dans la `RichTextBox` de l'UI.
*   **Deep Update** : Utilise la commande `New-AppSPStructure` (Module `Toolbox.SharePoint`) pour réappliquer toute la configuration sur le dossier renommé.
