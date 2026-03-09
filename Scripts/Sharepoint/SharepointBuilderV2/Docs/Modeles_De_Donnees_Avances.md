# Guide de Conception : Modèles de Données Avancés (Dossiers SharePoint)

Ce document décrit le fonctionnement et les bonnes pratiques liés à l'architecture des "Dossiers Avancés" implémentée dans la PowerShell Admin ToolBox (module SharePointBuilderV2), spécifiquement pour le contexte de la GED Vosgelis.

## 🎯 Concept de "Dossier Avancé"

Dans SharePoint, un dossier standard n'est qu'un contenant et ne possède par défaut aucune métadonnée (colonne) personnalisée en dehors de son Nom.
Pour répondre aux besoins métiers de Vosgelis (Ex: suivre l'avancement d'un Dossier d'Achat, qualifier un Dossier de Personnel), nous avons mis au point une architecture basée sur l'**API Microsoft Graph** qui permet d'attacher des formulaires (schémas de données) directement aux dossiers.

Techniquement, l'outil SharePointBuilder génère un **Type de Contenu (Content Type)** personnalisé contenant des **Colonnes de Site (Site Columns)**, qui est ensuite publié sur les bibliothèques cibles.

## 📊 Les Types de Données (Colonnes) supportés

Lors de la création d'un "Dossier Avancé" depuis l'interface, vous pouvez ajouter autant de colonnes que nécessaire. Voici les types de données actuellement pris en charge et leurs cas d'usage optimaux :

| Type de donnée      | Traduction API Graph | Cas d'usage métier recommandé                                                                                             |
| :------------------ | :------------------- | :------------------------------------------------------------------------------------------------------------------------ |
| **Texte**           | `text`               | Noms, références courtes, identifiants, prénoms. (ex: `Matricule Employé`, `Ref Contrat`)                                 |
| **Nombre**          | `number`             | Quantités, compteurs, montants absolus. (ex: `Nombre de pièces`)                                                          |
| **Date et Heure**   | `dateTime`           | Calendrier ou jalons chronologiques. Point essentiel pour structurer une GED. (ex: `Date signature`, `Date relance`)      |
| **Oui/Non**         | `boolean`            | Interrupteur d'état, validation rapide. Apparaîtra sous forme de case à cocher. (ex: `Dossier Complet`, `Dossier Urgent`) |
| **Choix Multiples** | `choice`             | Liste fermée de valeurs, menus déroulants. Sécurise la saisie de l'utilisateur. (ex: `Statut`, `Service`)                 |

_Note: D'autres types avancés (Devise, Lien texte, etc.) pourront être ajoutés au moteur Graph ultérieurement selon les besoins._

## ⚠️ Règles Obligatoires (Bonnes Pratiques)

Pour garantir la fluidité et la stabilité du déploiement vers Microsoft 365 :

1. **Nom système de la colonne (Obligatoire)**
   - Il doit être unique au sein de votre modèle.
   - Ne doit pas contenir d'espaces ni de caractères spéciaux (Accents, Tirets de soulignement, ou ponctuation à éviter). _Ex: Préférez `DateSignature` au lieu de `Date de signature :`._
   - L'outil de construction SharePoint retirera automatiquement les symboles interdits en arrière-plan, mais une bonne nomenclature en amont évite les conflits d'URL internes (_Internal Name_).

2. **Propriété "Indexable" (Optionnelle)**
   - **Pourquoi indexer ?** Si une colonne est marquée comme indexable, SharePoint construira un index de recherche en arrière-plan. C'est crucial si vous prévoyez d'avoir plus de **5000 dossiers** dans une même bibliothèque (la fameuse limite de vue SharePoint) et que vous souhaitez pouvoir filtrer l'affichage selon cette colonne.
   - **Contrainte :** Une bibliothèque SharePoint ne peut avoir que **20 colonnes indexées au maximum**. Ne cochez donc cette option que pour les colonnes clés (ex: `Statut`, `Matricule`), pas pour les champs de notes libres.

3. **Ne pas créer de "Tag" interne**
   - L'outil SharePointBuilder génère automatiquement et de façon cachée une colonne technique nommée `FolderTagId` pour faire le lien fort entre le système central (fichiers de Propriétés) et le dossier SharePoint. Vous n'avez pas besoin d'en créer une de votre côté.

## 🚀 Le Cycle de Vie d'un Modèle

1. **Création UI** : L'administrateur crée le schéma depuis _SharePointBuilderV2 -> Modèles_.
2. **Sauvegarde locale** : Le modèle est sauvegardé dans la base SQLite au format JSON.
3. **Sélection au déploiement** : Lors d'un déploiement d'architecture, l'administrateur lie un modèle à un dossier racine ou un sous-dossier type.
4. **Injection Graph API (Backend)** :
   - Le script vérifie si les colonnes de sites existent déjà sur le Tenant (pour éviter les doublons). S'il en manque, elles sont créées.
   - Un Content Type spécifique à votre modèle est créé.
   - Le Content Type est injecté dans la (ou les) bibliothèque(s) cible(s).
5. **Instanciation SharePoint** : Des dossiers sont créés en s'appuyant sur ce Content Type. Ils disposent instantanément du formulaire de propriétés défini !
