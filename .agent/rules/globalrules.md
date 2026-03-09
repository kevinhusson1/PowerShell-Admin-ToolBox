---
trigger: always_on
---

# Règles de Développement - PowerShell Admin ToolBox
Règle globale a appliquez, ne me répond qu'en français. tes pistes de réflexion interne peuvent etre en anglais mais la réponse final ou les artefact que tu génère doivent etre en français.

Ces règles doivent être impérativement suivies pour garantir la stabilité, la sécurité et la maintenabilité du projet.

## 1. Conventions Générales & Langue
*   **Langue** : Tout le contenu généré (commentaires, documentation, messages de commit, échanges) doit être en **Français**.
*   **Encodage** : Tous les fichiers (PS1, XAML, JSON, MD) doivent être en **UTF-8 with BOM** (ou UTF-8 standard si BOM pose problème, mais cohérent).

## 2. Architecture & Structure
*   **Hub & Spoke** : Ne jamais bloquer le thread du Launcher. Les tâches longues doivent être déléguées à des scripts enfants ou des Jobs.
*   **Entrées/Sorties** :
    *   Ne jamais utiliser `Write-Host`. Utilisez `Write-AppLog` (Module Logging).
    *   Ne jamais accéder à `Config/database.sqlite` directement. Utilisez les fonctions du module `Database` (`Set-App...`, `Get-App...`).
*   **Modules** :
    *   Les fonctions réutilisables vont dans `Modules/`.
    *   Une fonction = Un fichier `.ps1` dans `Modules/NomDuModule/Functions/`.

## 3. Développement UI (XAML/WPF)
*   **Séparation** : Pas de logique complexe dans le XAML. Le XAML est pour la présentation, le PS1 pour l'interaction.
*   **Localization** : 
    *   Ne jamais hardcoder de texte dans le XAML.
    *   Utilisez toujours la syntaxe `##loc:cle_de_traduction##`.
    *   Ajoutez les clés correspondantes dans `Localization/fr-FR/` et `Localization/en-US/`.
*   **Contrôles** : Accédez aux éléments UI via la hashtable globale `$Global:AppControls`.
*   **WPF Binding** : Pour les contrôles liés (ComboBox, ItemsSource), privilégiez la création d'objets `[PSCustomObject]` propres plutôt que l'utilisation de `Add-Member` sur des objets existants pour garantir la détection des propriétés par le moteur de binding.
*   **Rendu d'Icônes** : 
    *   Pour les petites icônes (boutons 34x34 ou moins), utilisez `RenderOptions.BitmapScalingMode="HighQuality"` dans le XAML pour éviter le flou.
    *   Soyez précis avec les `Margins` (ex: 4px au lieu de 5px) pour éviter la troncation sur les petits conteneurs.

## 4. Sécurité
*   **Zéro Secret** : Aucun mot de passe, token, ou secret en clair dans le code ou les JSON.
*   **Credentials** : Utilisez `Get-ADServiceCredential` ou les mécanismes intégrés Azure.
*   **Injection SQL** : Toujours utiliser les paramètres dans les requêtes SQLite (géré par le module Database, mais à garder en tête).

## 5. Création de Scripts (Plugins)
*   Toujours partir du modèle `Scripts/Designer/DefaultUI`.
*   Chaque script doit avoir son `manifest.json` valide avec un ID unique.
*   Le script doit gérer sa propre fermeture et la libération de son verrou BDD (`Remove-AppScriptLock`).

## 6. Qualité du Code
*   Utilisez `try/catch` pour toutes les opérations risquées (IO, Réseau, BDD).
*   Nommez les variables en **CamelCase** (`$maVariable`).
*   Nommez les fonctions en **PascalCase** avec verbe approuvé (`Get-AppUser`, `Set-AppConf`).
*   **Gestion des Portées (Closures)** : Utilisez systématiquement `.GetNewClosure()` lors de la définition de scripts blocks pour les événements (`Add_Click`, `Add_TextChanged`, etc.) afin de figer le contexte des variables (`$Ctrl`, `$selectedItem`).

## 7. Utilisation des skills
*   Utiliser toujours les skills mis à disposition en particulier celui des powershell_rules