# 🛠️ Composant : FormEditor (Éditeur de Règles de Nommage)

## 📌 Présentation
L'Éditeur de Formulaires, ou FormEditor, permet à un administrateur de concevoir l'interface de saisie (le formulaire dynamique) qui sera présentée aux utilisateurs finaux lors du déploiement d'une architecture. C'est ici que sont définies les questions, les champs textes, les listes déroulantes, etc.

Le résultat produit par cet éditeur est enregistré en tant que **"Naming Rule" (Règle de Nommage)**.

## 🏗️ Architecture du Composant

Cet éditeur dispose d'une interface graphique interactive définie en WPF.

- `FormEditor.xaml` : L'interface définissant la grille d'édition. Elle offre un panneau central simulant le rendu final et un panneau de droite pour l'ajout d'éléments.
- `FormEditor.ps1` : Gère le cycle de vie de l'éditeur (Chargement JSON des définitions préexistantes, manipulation de l'arbre visuel WPF, mapping des événements, enregistrement de la Règle de nommage en base de données).
- **Dossier `Actions/`** :
  - `Invoke-AppSPFormEditor.ps1` : Gère la logique interne des éléments de formulaire générés dynamiquement (Création de blocs TextBlock, gère les ajouts/modifications des propriétés comme Nom, Options d'une liste déroulante ou le type de champ Métadonnées).

## ⚙️ Fonctionnement Détaillé

### 1. Structure JSON Générée
Chaque formulaire (NamingRule) enregistré via cet onglet génère un JSON contenant la structure visuelle (Layout). 
```json
{
  "Layout": [
    {
      "Type": "Label",
      "Content": "Sélectionnez le service :",
      "IsMetadata": false
    },
    {
      "Type": "ComboBox",
      "Name": "Service",
      "Options": ["RH", "IT", "Direction"],
      "IsMetadata": true
    }
  ]
}
```

### 2. Ajout de contrôles (Interaction UI)
Lorsqu'un administrateur clique sur "Ajouter une ComboBox" dans l'UI :
- Le PowerShell instancie concrètement un objet `System.Windows.Controls.ComboBox` et l'ajoute au `StackPanel` central.
- Le clic sur ce nouvel élément déclenche l'événement "Sélection" qui met à jour le panneau de droite "Propriétés" avec les attributs de l'élément cliqué (Nom interne de la variable, texte par défaut).

### 3. Gestion des Tags (IsMetadata)
Une case importante est "Utiliser en tant que Tag/Meta". Si coché, l'input dynamique de l'utilisateur viendra alimenter un Tag dynamique de SharePoint.

## 💡 Exemple d'Utilisation

```text
1. L'administrateur crée une Règle Nommée "Projet RH 2025".
2. Il ajoute un "Text Input" -> Nom : "NomProjet".
3. Il ajoute un Label -> "Quel service pilote ?"
4. Il ajoute une "Liste Déroulante" -> Nom : "ServicePilote", Options : "Formation, Paie". Case [x] Tag coché.
5. Clic sur Enregistrer.
6. Résultat -> En Base de Données, ce formulaire sera disponible sous forme de Règle de Déploiement pour construire un template d'architecture complet.
```
