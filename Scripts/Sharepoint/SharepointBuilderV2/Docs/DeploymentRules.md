# Documentation Profonde : Architecture & Règles de Déploiement SharePoint (v5.0)

Ce document constitue la référence ultime pour comprendre le fonctionnement interne, les dépendances et les mécanismes de résilience de **SharePointBuilderV2**.

---

## 1. Principes Fondamentaux de l'Architecture

### Moteur "Stateless" vs "Stateful"
Le moteur de déploiement est conçu pour être transactionnel. Il ne se contente pas de créer des dossiers ; il établit une **corrélation** entre une définition logique (le modèle JSON) et une réalité physique (SharePoint).

#### Le Mapping d'Identifiants (ID Correlation)
Chaque élément défini dans le TreeEditor possède un `Id` (GUID unique interne). Lors du déploiement :
1.  Le script crée l'élément sur SharePoint.
2.  L'API Graph retourne un `id` SharePoint (ex: `01ABCD...`).
3.  Le script alimente une table de correspondance dynamique : `$DeployedFoldersMap`.
**Cette table est cruciale** car elle permet aux phases suivantes (Permissions, Tags, Liens Internes) de cibler les éléments créés, même s'ils sont imbriqués très profondément.

---

## 2. Cycle de Vie détaillé d'un Déploiement

### Phase A : Pré-Calcul & Planification
La fonction `Get-AppSPDeploymentPlan` aplatit la structure hiérarchique en une liste ordonnée d'opérations. 
-   **Variables Dynamiques** : Résolution des expressions type `🎯 NomVariable` à partir des `FormValues`.
-   **Analyse de portée** : Détermination des types (Dossier, Fichier, Lien, Publication).

### Phase B : Création Physique (Dossiers)
Utilise `New-AppGraphFolder`.
-   **Règle d'Identité** : Si un dossier racine est défini (`RootFolderName`), il devient le "Point Zéro". Tous les autres dossiers sont créés relativement à son `id`.
-   **Résilience** : En cas de dossier déjà existant, le moteur récupère l'ID existant au lieu de provoquer une erreur de doublon.

### Phase C : Métadonnées & Schémas
C'est ici que l'API **Graph Beta** intervient.
-   **Content Types** : Le script vérifie la présence du modèle de dossier (`SBuilder_NomDuSchema`). S'il est absent de la bibliothèque cible, il l'injecte dynamiquement.
-   **Mapping de Colonnes (Variable -> Interne)** : 
    -   Le script consulte la définition du formulaire (`FormDefinitionJson`). 
    -   Il fait la correspondance entre le nom "humain" (Ex: `Année`) et le nom technique SharePoint (Ex: `Year`).
-   **Formatage Multi-Choix** : Pour les colonnes de type "Choix Multiple", le payload est automatiquement enveloppé dans une `Collection(Edm.String)` pour satisfaire les exigences de l'API Graph Beta.

### Phase D : Liens Internes (Deep Linking)
Les liens internes sont des fichiers `.url` dont la destination dépend d'un autre élément du déploiement en cours.
-   Le moteur attend que la cible (Ex: Dossier "CONCEPTION") soit créée.
-   Il récupère le `webUrl` de la cible fraîchement créée.
-   Il génère le fichier `.url` à la source demandée avec l'URL exacte du nouvel élément.

---

## 3. Publication : La Notion de Miroir

La publication (`Type: Publication`) n'est pas une simple copie, c'est la création d'un point d'accès dans une zone partagée (souvent une bibliothèque différente).

### Logique `UseFormName` & `UseFormMetadata`
-   **Hiérarchisation** : Si `UseFormName` est actif, le script crée un "Dossier Projet" (ex: `/PUBLICS/PRJ-2025-001`).
-   **Héritage de Context** : Si `UseFormMetadata` est actif, le script reporte les tags du déploiement principal (Année, Secteur, etc.) sur ce nouveau dossier projet dans la zone publique.
-   **Sécurité** : Utilisation d'un mécanisme de vérification préalable (`GET` avant `POST`) pour éviter de casser des dossiers sous "Hold" ou verrouillés par SharePoint.

---

## 4. Persistance & État (State In-Situ)

A la fin de chaque déploiement réussi, un fichier invisible `.sbuilder_state.json` est déposé à la racine du dossier projet SharePoint.

### Pourquoi ce fichier est vital ?
1.  **Réparation/Mise à jour** : Si l'utilisateur renomme un dossier manuellement sur SharePoint, le Builder s'y perdrait. Grâce au State, le Builder peut lire le fichier caché, retrouver la correspondance ID Interne / ID Graph, et appliquer les modifications au bon endroit.
2.  **Audit** : Il contient l'horodatage, l'ID du modèle utilisé et l'intégralité des valeurs de formulaire saisies à l'instant T.

---

## 5. Historique & Tracking

Le déploiement alimente une liste de suivi centralisée (Tracking). 
-   **Détail** : Qui a déployé ? Quel modèle ? Quelles variables ? Quelle URL finale ?
-   **But** : Permettre aux administrateurs de piloter le parc documentaire et de détecter d'éventuels écarts (Drift Analysis).

---

## 6. Table de Récapitulation des Règles d'Or

| Concept | Règle Impérative | Pourquoi ? |
| :--- | :--- | :--- |
| **Permissions** | `sendInvite = $false` | Éviter le spam par email lors de créations massives. |
| **Noms de Dossiers** | Nettoyage des caractères interdits | `[\\/:*?"<>\|#%]` font planter l'API Graph. |
| **Schéma** | Utiliser `TargetColumnInternalName` | Indispensable pour que le tag dynamique trouve sa colonne cible. |
| **Graph Beta** | Usage spécifique pour `ListItem` | Nécessaire pour mettre à jour les colonnes de données sans passer par le mode édition web. |
| **Liens Internes** | Résolution post-création | On ne peut pas créer un lien vers un dossier qui n'a pas encore d'ID SharePoint. |

---

## 7. Exemple de Flux Complet
1.  **Formulaire** : L'utilisateur saisit `RH` dans le champ `Services`.
2.  **Mapping** : Le script identifie que `Services` doit être écrit dans la colonne interne `SBuilder_Services`.
3.  **Déploiement** : 
    -   Dossier "RACINE" créé.
    -   Sous-dossier "DOCS" créé.
    -   Fichier `.url` généré pointant vers "RACINE".
    -   Permissions `Collaborateur` appliquées sur "DOCS".
4.  **Finalisation** : Le `.sbuilder_state.json` est écrit, validant la fin du cycle.
