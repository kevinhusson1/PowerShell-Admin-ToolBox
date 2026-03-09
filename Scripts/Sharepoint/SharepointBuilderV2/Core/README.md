# 🧠 Noyau Principal : Le Core

## 📌 Présentation
Le dossier **Core** contient toute la tuyauterie interne et l'intelligence logicielle partagée entre tous les composants (`FormEditor`, `SchemaEditor`, `Deploy`, `TemplateManager`).  
C'est le moteur qui rend la V2 modulaire, DRY (Don't Repeat Yourself), et facile à maintenir.

Ce dossier n'est pas responsable d'une interface utilisateur dédiée, mais manipule en arrière-plan tous les contrôles WPF globaux de `SharePointBuilderV2.xaml` et `MainWindow.xaml`.

## 🏗️ Architecture du Noyau

Le dossier Core est scindé en deux compartiments vitaux :

### 1. Dossier `Shared/` (Fonctions transverses)
Il contient les outils appelés par au moins 2 composants différents.

- `Get-BuilderControls.ps1` : Effectue le binding WPF. Ce script parcourt l'arbre visuel WPF de la fenêtre et enregistre les références de tous les TextBox, TreeView et Buttons sous forme de `$Ctrl["NomDuControl"]` (Hashtable globale). **Zéro magie, mapping manuel forcé** pour des questions de performances et de debug.
- `Get-PreviewLogic.ps1` : Déclare la logique d'état (Activé/Désactivé) du bouton Déployer. C'est ici qu'on vérifie si "Site + Lib + TexteFormulaire" sont remplis.
- `Reassemble-ArchitectureTree.ps1` (Invoke-AppSPReassembleTree) : Fonction partagée indispensable pour hydrater la structure du "Flat JSON Format". Refait les associations Parent/Enfant des Tags, Perms, Publications et Links sur les Dossiers.
- `Shared-TreeBuilder.ps1` : Fabrique les objets visuels TreeViewItem nativement compatibles avec nos icônes et nos standards WPF.
- `Update-TreePreview.ps1` : Connecteur utilisé par "Deploy", appelant le TreeBuilder partagé avec le dictionnaire `$Replacements` pour convertir les variables {TOTO} en vrai texte.

### 2. Dossier `TreeEditor/` (Moteur SchemaEditor)
Dédié de manière pointue au SchemaEditor et à l'édition d'Architecture. C'est la "Bibliothèque de dessin d'arbres".

- `Editor/` (Sous-dossier) :
  - `New-EditorNode.ps1`, `New-EditorInternalLinkNode.ps1`, etc. : Ce sont les usines (Factories) qui instancient spécifiquement la vue WPF (L'icône "Dossier Jaune", l'icône "Navette Spatiale" pour la Pub).
  - `Register-EditorLogic.ps1` et `Serialization-Editor.ps1` : Le transformateur "UI-To-JSON" et "JSON-To-UI".
  - Les événements complexes : Saisie clavier sur le TreeView, Hover (Survol), Sélection multiple.

## ⚙️ Philosophie & Avantages

- **Unidirectionnel & Flat JSON** : 
  Historiquement, JSON = Dossier > Sous-Dossier > Sous-Dossier (Récursion profonde).  
  Maintenant (V2/V3), JSON = `Folders` (Récursifs), mais `Publications`/`Links`/`Files` sont stockés dans un tableau plat avec un `ParentId`.
  > **Avantage** : Pour le module SQL ou le module Graph d'API de déploiement, il devient incroyablement plus facile de manipuler les fichiers ou de vérifier la liste de toutes les Publications sans parcourir l'arbre complet avec un ForEach.
- **Ré-Assemblage Central (Reassemble-ArchitectureTree)** :
  L'adoption du *Flat JSON* exige un moment de "Ré-hydratation" visuelle. Le dossier Core expose la méthode `Invoke-AppSPReassembleTree`. L'Éditeur ET le Déployeur appellent cette même fonction pour un affichage parfaitement cohérent garant des normes.

## 💡 Exemple d'Orchestration Globale du Core
```text
1. Lancement SharePointBuilderV2.ps1 -> Importe tout le Core.
2. Initialize-BuilderLogic.ps1 appelle `Get-BuilderControls`.
3. Désormais `$Ctrl` référence TOUS les boutons WPF.
4. L'utilisateur charge une Architecture -> Appelle `Convert-JsonToEditorTree` (Serialization-Editor.ps1).
5. Ce script invoque `Invoke-AppSPReassembleTree` (Shared) -> Le GUI est mis à jour.
6. Changement du nom du dossier -> `Get-PreviewLogic.ps1` est déclenché -> Le Bouton "Déploiement" passe au Vert.
```
