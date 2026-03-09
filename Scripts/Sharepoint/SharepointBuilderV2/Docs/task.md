# 🏗️ Nouvelles Évolutions V3 : Intégration Profonde des Schémas Avancés

**Objectif** : Verrouiller la cohérence de l'architecture SharePoint en forçant la liaison des Formulaires (Règles de nommage) et des Architectures (Éditeur de Modèle) à un Schéma cible commun.

---

## 🏗️ Phase 1 : Infrastructure & Modifications DB / JSON
*   [x] **1.1 Base de données (Schémas)** : Renommer le menu existant "Modèle Avancé" en "Schémas de Dossiers Avancés" pour plus de clarté.
*   [x] **1.2 Base de données (Formulaires)** : Modifier la logique de sauvegarde/chargement des `sp_naming_rules` pour inclure l'identifiant du schéma cible (`TargetSchemaId`) à la racine du JSON.
*   [x] **1.3 Base de données (Architectures)** : Modifier la logique de sauvegarde/chargement des `sp_templates` pour inclure l'identifiant du schéma cible (`TargetSchemaId`) à la racine du JSON de structure.

## 📝 Phase 2 : Formulaires de Destination
*   [x] **2.1 Verrouillage initial** : Désactiver le panneau de paramètres de champ et la liste des champs tant qu'un formulaire n'est pas sélectionné/créé.
*   [x] **2.2 Bloquage Création** : Ajouter une sélection obligatoire du Schéma Cible à la création d'un nouveau formulaire.
*   [x] **2.3 Configuration des Champs** : Ajouter une ComboBox dynamique qui liste les colonnes du Schéma cible lorsqu'on coche "Appliquer comme métadonnées".
*   [x] **2.4 JSON** : Enregistrer le Nom Interne de la colonne ciblée dans la définition du champ.

## 🗂️ Phase 3 : Éditeur de Modèle (Architecture)
*   [x] **3.1 Verrouillage initial** : Désactiver l'interface (arbre de dossiers) tant qu'un modèle n'est pas créé ou chargé.
*   [x] **3.2 Bloquage Création** : Au clic sur "Nouveau", forcer l'utilisateur à créer une nouvelle instance d'architecture liée à un Schéma précis contenu en base de données.
*   [x] **3.3 Tags Dynamiques** : Afficher en lecture seule le Schéma et le Formulaire en haut de l'éditeur de modèle (TargetSchemaDisplay).
*   [x] **3.4 Logique Folder** : Restreindre la liste déroulante "Variable Source" aux champs identifiés comme métadonnées ET provenant uniquement des formulaires liés au même Schéma cible.
*   [x] **3.5 Sélection Colonne Tag** : Remplacer la saisie libre du nom de colonne dans les Tags statiques par une ComboBox basée sur le Schéma cible.

## Phase 4 : Menu Déploiement (Terminée)
- [x] 4.1 Étape 3 Obligatoire : Retirer la mention "(Optionnel)" et repenser la validation pour inclure la sélection du Modèle.
- [x] 4.2 Filtres en cascade :
- [x] Refonte Menu Déploiement (Phase 4)
    - [x] Nettoyage UI (Retrait (Optionnel), regroupement)
    - [x] Logique filtres en cascade (Schéma -> Architecture -> Formulaire)
    - [x] Validation de cohérence finale (Triade)
- [x] Phase 4 - Correctifs (Régressions)
    - [x] Fix Job SharePoint (Remove-Job / Receive-Job)
    - [x] Réorganisation XAML Étape 3 (Schéma en premier)
    - [x] Fix Visibilité Preview & Formulaire (Enums & Indexation)
    - [x] Fix TreeView Étape 2 (Architecture vs TargetExplorer)
    - [x] Fix Chargement Libs & Preview Meta (PSModulePath & Events)
    - [x] Fix Reset intelligent des modèles (CbTemplates)
    - [x] Fix Masquage SiteLoadingBar (Tag Timer)
    - [x] Fix Auto-sélection bibliothèque unique
    - [x] Fix Régression Sélection Site ($site variable)
    - [x] Fix Recherche Débounce (v2.8)
    - [x] Fix Activation CbLibs & Loader (v2.8)
    - [x] Fix Forçage UI Dispatcher (v2.9)
    - [x] Fix Activation Permanente CbLibs (v3.0)
    - [x] Fix Parallélisation Sélection Lib (v3.0 - Anti-Freeze)
    - [x] Fix Activation CbLibs (v2.6 - Threading UI)
    - [x] Fix Expansion Récursive (v4.0 - Closures & FullPath)
    - [x] Diagnostic de Sélection v4.2 (Logs & Bubbling)
    - [x] Rapport de Transfert v4.2 (Handoff)
- [ ] Finalisation & Tests Déploiement (Prochaine session)
- [ ] Documentation et Aide (Phase 5)
*   [ ] **5.1 Nouvel Onglet Aide** : Développer un nouveau Tab_Help.xaml décrivant :
    *   Le workflow pour réaliser un déploiement, étape par étape.
    *   À quoi sert chaque menu ("Pourquoi ce système découplé ?").
*   [ ] **5.2 Implémentation visuelle de l'Aide** : Injecter l'onglet dans [SharePointBuilderV2.ps1](file:///c:/CLOUD/Github/PowerShell-Admin-ToolBox/Scripts/Sharepoint/SharepointBuilderV2/SharePointBuilderV2.ps1) et s'assurer que sa présentation (Markdown ou RichText) est formatée correctement.
