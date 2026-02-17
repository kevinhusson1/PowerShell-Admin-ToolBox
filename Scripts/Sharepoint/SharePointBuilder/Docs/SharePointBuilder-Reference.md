# Documentation de Référence - SharePoint Builder

Ce document sert de référence unique pour l'utilisation de **SharePoint Builder**. Il détaille le fonctionnement de l'éditeur de modèle et du concepteur de formulaire.

## 1. Éditeur de Modèle (Model Editor)

### Barre d'outils (Toolbar)

Les actions sont contextuelles et dépendent de la sélection dans l'arbre.

| Icône | Action             | Description                                                                                                             | Contexte Requis       |
| :---- | :----------------- | :---------------------------------------------------------------------------------------------------------------------- | :-------------------- |
| 🆕     | **Nouveau**        | Efface tout et réinitialise l'espace de travail.                                                                        | Aucun                 |
| 🏗️     | **Racine**         | Ajoute un dossier racine (Top Level).                                                                                   | Aucun (ou Arbre vide) |
| 🔗     | **Lien Racine**    | Ajoute un lien à la racine du modèle.                                                                                   | Aucun (ou Arbre vide) |
| 📂     | **Enfant Dossier** | Crée DEUX sous-dossiers exemples dans le dossier sélectionné.                                                           | Dossier               |
| 🔗     | **Enfant Lien**    | Crée DEUX liens exemples dans le dossier sélectionné.                                                                   | Dossier               |
| 🔗📅    | **Lien Interne**   | Crée un raccourci `.url` pointant vers un autre dossier **du même modèle**. Ouvre une fenêtre de sélection de la cible. | Dossier               |
| 🌏     | **Publication**    | Crée un noeud de type "Publication" (Miroir ou Lien vers un autre site/lib).                                            | Dossier               |
| 📄     | **Fichier**        | Ajoute un fichier à copier depuis une URL source.                                                                       | Dossier               |
| ❌     | **Supprimer**      | Supprime le noeud sélectionné (et ses enfants).                                                                         | Sélection active      |

### Actions de Propriétés (Globales)
Ces boutons ajoutent des métadonnées ou des permissions au noeud sélectionné.

*   **Ajouter Permission** : Ajoute une entrée ACL (Utilisateur/Groupe + Niveau).
    *   *Note* : Non applicable aux Liens ou Publications.
*   **Ajouter Tag** : Ajoute une paire Clé/Valeur statique (Colonne SharePoint).
*   **Ajouter Tag Dynamique** : Ajoute un Tag dont la valeur sera issue du formulaire de saisie au moment du déploiement.

### Propriétés des Noeuds (Détails)

Selon le type de noeud sélectionné, le panneau de droite affiche différentes options.

#### 1. Dossier (Folder)
*   **Nom** : Nom du dossier. Supporte les variables `{Form:NomChamp}`.
*   **Couleur** : Aide visuelle dans l'éditeur uniquement.

#### 2. Publication (Publication)
Sert à créer une passerelle vers un autre emplacement documentaire.
*   **Nom** : Nom du raccourci créé localement (si applicable).
*   **Target Site URL** : URL absolue du site de destination.
    *   Si vide et Mode=Auto, cible le site courant.
*   **Target Folder Internal Path** : Chemin relatif dans la bibliothèque cible (ex: `/Dossier/SousDossier`).
*   **Use Model Name** : Si coché, le dossier final sera `TargetFolderPath` + `NomRacineModele`.
    *   *Exemple* : Si le modèle déploie "Projet A" et la cible est `/Public/`, le résultat sera `/Public/Projet A`.
*   **Target Site Mode** :
    *   `Auto (Current)` : Reste sur le site du déploiement.
    *   `Url` : Change de site collection (nécessite auth).
*   **Use Form Metadata** : Si coché, applique les métadonnées du formulaire (celles marquées `IsMetadata`) sur le dossier cible distant.

#### 3. Fichier (File)
Copie un fichier depuis une source vers le dossier cible.
*   **Source URL** : URL HTTP(S) directe du fichier. Peut être une URL SharePoint (sera authentifiée) ou Web publique.
*   **File Name** : Nom du fichier une fois copié sur SharePoint.
*   **Bouton "Fetch Info"** : Tente de deviner le nom du fichier à partir de l'URL.

#### 4. Lien Interne (Internal Link)
Raccourci de navigation au sein de la structure.
*   **Target Node** : ID interne du dossier cible.
*   Le lien sera créé sous forme de fichier `.url` pointant vers l'URL absolue future du dossier cible.

#### 5. Permission / Tag
*   **Permission** : Identité (Email/Groupe) et Niveau (`Read`, `Contribute`, `Full Control`).
*   **Tag** : Nom de la colonne (InternalName) et Valeur.
    *   Si **Dynamique** : La valeur est liée à une variable du formulaire (`Source Form` / `Source Variable`).


---

## 2. Concepteur de Formulaire (Naming Rules)

Cette section permet de définir les règles de nommage et les formulaires de saisie qui seront présentés à l'utilisateur lors du déploiement.

### Types de Contrôles

#### 1. Label (Texte Fixe)
Affiche un texte informatif non modifiable.
*   **Content** : Le texte à afficher.
*   **Width** : Largeur du contrôle (défaut : 100).
*   *Note* : N'a pas de variable associée, sauf si `IsMetadata` est coché (dans ce cas, `Name` sert de clé).

#### 2. TextBox (Champ Texte)
Champ de saisie libre.
*   **Name (Variable)** : Nom de la variable interne (ex: `NomProjet`). Utilisé pour les substitutions `{Form:NomProjet}`.
*   **Default Value** : Valeur pré-remplie.
*   **Is Uppercase** : Force la saisie en majuscules.
*   **Is Metadata** : Si coché, la valeur saisie sera également appliquée comme métadonnée sur le dossier racine (si une colonne interne porte le nom de la Variable).

#### 3. ComboBox (Liste Déroulante)
Liste de choix prédéfinis.
*   **Name (Variable)** : Nom de la variable interne.
*   **Options** : Liste des valeurs séparées par des virgules (ex: `A,B,C`).
*   **Default Value** : Valeur sélectionnée par défaut.

### Fonctionnalités Clés

*   **Variables de Formulaire** :
    *   Chaque champ (TextBox/ComboBox) définit une variable via sa propriété **Name**.
    *   Dans l'Éditeur de Modèle, vous pouvez utiliser ces variables dans les noms de dossiers : `{Form:MaVariable}`.
    *   Lors du déploiement, `{Form:MaVariable}` sera remplacé par la valeur saisie par l'utilisateur.

*   **Métadonnées (Is Metadata)** :
    *   Si la case **Is Metadata** est cochée pour un champ, sa valeur ne sert pas uniquement au nommage.
    *   Elle est aussi transmise au moteur de déploiement pour taguer le **Dossier Racine** (et les Publications si configurées).
    *   *Condition* : La bibliothèque SharePoint cible doit posséder une colonne dont le `InternalName` correspond exactement au **Name** du champ.
