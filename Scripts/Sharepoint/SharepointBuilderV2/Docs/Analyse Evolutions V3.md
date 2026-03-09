# Rapport d'Analyse : Évolution de l'Architecture (V3)
**Sujet** : Intégration profonde du "Schéma Avancé" au cœur de toute l'application SharePoint Builder.

## 1. Compréhension du Besoin
L'objectif principal de cette évolution est de **fiabiliser et contraindre** la création de l'architecture SharePoint autour d'une colonne vertébrale unique : le **Schéma de Dossier Avancé** (Content Type).
Jusqu'à présent, les formulaires, les architectures et les schémas vivaient chacun de leur côté. La nouvelle vision impose une relation descendante claire pour éviter toute erreur de déploiement (comme essayer d'injecter une métadonnée d'un formulaire vers une colonne qui n'existe pas dans l'architecture cible).

## 2. L'Évolution Architecturale

### A. Le Paradigme Relationnel
La nouvelle règle d'or métier est la suivante : **Un formulaire ou une architecture n'a de sens que s'il est rattaché à un Schéma.**

1. **Le Schéma (Modèle Avancé)** : C'est le contrat de données (Définition des colonnes).
2. **Le Formulaire (Règle de nommage)** : Appartient à un Schéma. Il dicte comment on remplit les données de ce contrat au moment du déploiement.
3. **L'Architecture (Éditeur de modèle)** : Appartient à un Schéma. Elle dicte quels dossiers et sous-dossiers vont hériter de ce contrat.

### B. Impacts sur la Base de Données (SQLite & JSON)
Pour supporter cela, la structure de la base et des JSON doit évoluer :

*   **Table `sp_naming_rules` (Formulaires)** :
    *   Le JSON du formulaire doit stocker l'ID du Schéma parent au niveau de sa racine (`SchemaTargetId`).
    *   Chaque champ de type "Métadonnée" du formulaire doit stocker l'information `TargetColumnName` (le nom interne généré de la colonne SharePoint ciblée).
*   **Table `sp_templates` (Éditeur de Modèle)** :
    *   Un champ `SchemaTargetId` doit être ajouté à la table ou explicitement mis à la racine du JSON de la structure pour lier l'arbre de dossiers au bon modèle de données.

### C. Refactorisation UX/UI Menu par Menu

#### 1. Menu "Schéma dossier avancé"
*   **Action** : Renommage du titre du menu existant. Aucune modification logique majeure requise dans l'immédiat. L'UI est déjà fonctionnelle.

#### 2. Menu "Formulaire destination"
*   **Locking Initial** : Interface grisée/désactivée au démarrage tant qu'un formulaire n'est pas créé ou chargé (similaire à l'Éditeur de Modèle).
*   **Logique de Création** : Au clic sur "Nouveau", une popup demandera de **choisir le Schéma cible**.
*   **Configuration de champ** : 
    *   Lorsqu'on coche "Appliquer comme métadonnées", on affichera une seule liste déroulante (ComboBox) contenant **uniquement les colonnes du schéma lié à ce formulaire**. 
    *   *(Optimisation UX par rapport à la demande : Puisque le formulaire entier est lié à un schéma dès sa création, il est redondant de demander à l'utilisateur de re-sélectionner le schéma à CHAQUE champ. On affiche directement les colonnes adéquates).*
*   **JSON** : Restructuration du JSON généré pour bien identifier `IsMeta: true`, `TargetSchemaId : "..."` et `TargetColumnInternalName: "..."`.

#### 3. Menu "Éditeur de modèle" (Architecture)
*   **Locking Initial** : Interface grisée/désactivée au démarrage.
*   **Logique de Création** : Au clic sur "Nouveau", popup forcant le choix du Schéma cible. L'architecture est ainsi verrouillée sur ce contrat de données.
*   **Tags Dynamiques** : La liste "Variable Source" filtrera intelligemment les entrées pour ne proposer que les champs des formulaires existants qui (1) ont la case "Appliquer comme métadonnée" cochée ET (2) appartiennent au MÊME schéma que l'architecture en cours d'édition.

#### 4. Menu "Déploiement"
*   **Refonte de l'Étape 3 (Mandataire)** :
    *   Devient **obligatoire**.
    *   Lordre de sélection change : **Le choix du Schéma dicte le reste**.
    *   La case "Créer un dossier racine" est grisée tant qu'aucun schéma n'est sélectionné. L'aperçu est masqué tant que cette case n'est pas cochée.
    *   *Filtrage en cascade* : La liste des Formulaires (Règles de nommage) proposée ne contiendra QUE les formulaires qui ont été paramétrés pour ce schéma spécifique.
*   **Vérification de Validation** : Avant de permettre la sauvegarde ou le déploiement, le système s'assurera que `Template.SchemaTargetId == Form.SchemaTargetId == SelectedSchemaId`.
*   **Bug de Chargement des Sites** : Le script de déploiement (`Register-SiteEvents.ps1`) freeze actuellement de manière silencieuse dans son timer asynchrone pour certains environnements. Il recevra une passe de débogage renforcée (gestion locale du job + traçage d'erreurs en mode silencieux).

#### 5. Nouvel Onglet "Aide & Tutoriels" 
*   Création d'un module d'aide embarquant la documentation et la chronologie des étapes pour assister les administrateurs Vosgelis.

## 3. Stratégie d'Implémentation
La restructuration s'effectuera rigoureusement par niveaux de dépendance pour éviter de casser l'existant :
1.  **Backend** : Mise à jour des schémas JSON et de la logique métier de sauvegarde/chargement (BDD).
2.  **UI - Formulaires** : Implémentation du système de ciblage des colonnes.
3.  **UI - Architectures** : Verrouillage au démarrage et sélection du schéma racine pour un modèle.
4.  **UI - Déploiement** : Filtres en cascade et validation stricte.
5.  **Fix Bugs** : Aperçu de nom / Chargement liste des sites.
