# Plan de Migration V3 - SharePoint Deployer

## 📊 État des Lieux
Le script `SharePointDeployer` est actuellement en architecture **V2 (Monolithique)**. 
Bien qu'il utilise le module partagé `New-AppSPStructure` (qui est, lui, à jour en V3), le Deployer lui-même souffre de plusieurs dettes techniques par rapport au `SharePointBuilder` :

1.  **Code Monolithique** : `Initialize-DeployerLogic.ps1` contient tout (gestion UI, chargement Azure, Formulaire dynamique, Job deployment). C'est difficile à maintenir.
2.  **Validation Faible** : Il vérifie seulement si les champs sont vides. Il n'utilise pas `Test-AppSPModel` pour vérifier les permissions, l'existence du site, ou la validité des URL avant le déploiement.
3.  **UX Datée** : La gestion des logs et de la progression est moins riche que celle du Builder.

## 🎯 Objectifs de la Migration
Aligner le Deployer sur les standards V3 établis avec le Builder pour garantir :
- **Support complet des Publications** (déjà supporté par le backend, mais invisible dans l'UI).
- **Validation Robuste** (Niveaux 1, 2, 3) pour éviter les échecs de déploiement.
- **Maintenance Facile** (Découpage en fichiers logiques).

---

## 📅 Étapes de Mise à Jour

### Étape 1 : Refactoring Architecture (Découpage)
Éclater le fichier `Initialize-DeployerLogic.ps1` en composants spécialisés dans `Functions/Logic/` :

*   `Get-DeployerControls.ps1` : Indexation propre des contrôles UI (HashTable `$Ctrl`).
*   `Register-ConfigEvents.ps1` : Chargement de la liste des configs (filtrage par groupes) et sélection.
*   `Register-FormEvents.ps1` : Génération et gestion du formulaire dynamique (dossier cible).
*   `Register-ActionEvents.ps1` : Gestion du bouton Déployer et du Job asynchrone.

### Étape 2 : Intégration de la Validation V3
Utiliser le module `Test-AppSPModel` avant d'autoriser le déploiement.

1.  Au moment de la sélection d'une config ou modification du formulaire :
    - Construire le JSON temporaire (fusion Template + Données Formulaire).
    - Appeler `Test-AppSPModel -Level 2` (Connecté).
2.  Si Validation **KO** : Désactiver le bouton "Déployer" et afficher les erreurs dans le log.
3.  Si Validation **OK** : Activer le bouton.

### Étape 3 : Amélioration UI & Localisation
1.  **Logs** : Standardiser la consommation des logs du Job (flux `LogType = 'AppLog'`) pour avoir les couleurs et icônes (via `Get-AppLocalizedString`).
2.  **Résumé** : Ajouter dans la `DetailGrid` (résumé de config) une ligne pour indiquer si le modèle contient des Publications ("Partages Externes : Oui (2)").

---

## 🛠 Procédure Technique

1.  Créer le dossier `Functions/Logic`.
2.  Extraire `Get-DeployerControls` depuis le début de `Initialize-DeployerLogic`.
3.  Migrer la logique de chargement dans `Register-ConfigEvents`.
4.  Migrer la logique de formulaire dans `Register-FormEvents`.
5.  Migrer l'action Deploy dans `Register-ActionEvents` et y injecter l'appel à `Test-AppSPModel`.
6.  Mettre à jour le script principal `SharePointDeployer.ps1` pour charger ces nouveaux fichiers (comme fait dans `Initialize-BuilderLogic.ps1`).

**Note :** Cette migration ne nécessite pas de modifier `SharePointDeployer.xaml` (interface), sauf pour ajouter des labels de feedback validation si souhaité.
