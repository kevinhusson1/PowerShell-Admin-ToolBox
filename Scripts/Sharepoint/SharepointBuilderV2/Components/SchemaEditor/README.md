# 🏗️ Composant : SchemaEditor (Éditeur d'Architecture)

## 📌 Présentation
Le **SchemaEditor** est le point central de conception des arborescences de dossiers SharePoint.
Contrairement à la V1 où le formulaire et l'arborescence ne faisaient qu'un, la V2 propose le concept de modèle "Schéma" réutilisable.
Un "Schéma" est un gabarit d'architecture (Dossiers, Liens, Fichiers, Publications). Il peut s'y incruster des concepts dynamiques (via des `{Variables}`) qui se rattachent à un formulaire.

## 🏗️ Architecture du Composant

Cet éditeur visuel s'appuie fortement sur l'API native `TreeView` de WPF.

- `SchemaEditor.xaml` : Interface utilisateur avec au centre un TreeView complet et interactif, et la barre de menu d'ajout de nœuds/propriétés.
- `SchemaEditor.ps1` : Fichier de mapping des actions spécifiques à l'éditeur (Barre d'outils, sauvegardes).
- **Dossier `Actions/`** :
  - `Invoke-AppSPRenderBatch.ps1` : Gère le mode rendu massif (batch), notamment la gestion de sélection multiple.

*Note : La logique lourde du `TreeView` (Serialization, Hydration, Interactions des boutons du menu) est déléguée au module `Core/TreeEditor` mutualisé pour ne pas dupliquer le code complexe de gestion de l'arbre graphique WPF.*

## ⚙️ Fonctionnement Détaillé

### 1. Types de Nœuds (Nodes)
Le TreeView est alimenté par différents types de nœuds, définis par leur propriété native `.Tag.Type` :
- **Folder (Dossier)** : Nœud parent capable de contenir n'importe quel autre nœud.
- **Publication** : Nœud hybride servant de terminal cible dynamique. Interdit d'y ajouter des enfants. Possède une configuration (Auto/Manuel) pour le site parent.
- **Link (Lien Internet)** : Nœud `.url` classique pointant vers un site Web.
- **InternalLink (Lien Interne)** : Nœud `.url` pointant vers un Dossier ou Fichier configuré dans l'arbre lui-même.
- **File (Fichier Template)** : Représentation d'un fichier hébergé sur SharePoint qui sera copié lors du déploiement.

### 2. Composants Hiérarchiques (Métadonnées & Sécurité)
Sur n'importe quel nœud compatible (Surtout `Folder`), on peut attacher des propriétés qui se dessinent comme des Faux-Nœuds (Nodes de données visuelles) :
- **Tags (Métadonnées)** : Fixes ou Dynamiques (Liées à Variables de Formulaire `{Var}`).
- **Permissions** : Affectation des listes de lectures / écritures.

### 3. Logique de "Sibling"
Une fonctionnalité UX de cette version : Lorsqu'un utilisateur sélectionne une Métadonnée (Permission/Tag) dans l'arbre, la barre d'outils reste accessible et ajoutera la nouvelle métadonnée *au même niveau* (sur le dossier parent), simplifiant la création massive.

## 💡 Exemple d'Utilisation

```text
1. L'administrateur crée une "Architecture Ressources Humaines".
2. Il ajoute le nœud Racine "PROJET_{NomProjet}".
3. Dedans, 3 sous dossiers "01-Conception", "02-Realisation", "03-Livraison".
4. Sur "01-Conception", il ajoute le Permis (Lecture : "Direction").
5. Sur la racine, il ajoute un nœud Fichier "Template_KickOff.docx".
6. L'utilisateur enregistre. Le fichier SchemaEditor transmet les données au `Serialization-Editor.ps1` qui transforme le TreeView visuel en un "JSON Flat" propre pour le moteur de base de données.
```
