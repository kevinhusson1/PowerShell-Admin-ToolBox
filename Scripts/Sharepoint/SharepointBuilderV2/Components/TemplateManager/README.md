# 🗃️ Composant : TemplateManager (Association Formulaire 🔁 Architecture)

## 📌 Présentation
Le composant **TemplateManager** est le lien qui unit un Formulaire (`FormEditor`) et une Architecture (`SchemaEditor`).
C'est le composant visible en premier lieu par l'utilisateur final à l'Étape 1 du déploiement.

Il récupère une Architecture (JSON de structure) et l'associe avec un Formulaire (JSON Visuel de Layout).

## 🏗️ Architecture du Composant

- `TemplateManager.xaml` : Interface utilisateur simplifiée offrant deux ComboBox majeures -> le choix du "Modèle de déploiement (Template de l'architecture)" et l'activation de la "Règle de formulaire associée".
- `TemplateManager.ps1` : Gère le moteur d'hydradation visuelle. C'est lui qui lit le JSON "Layout" du formulaire sélectionné et qui instancie en direct ("Live Rendering") les boîtes de texte, labels, et combobox correspondants.

## ⚙️ Fonctionnement Détaillé

### 1. Processus de Dynamisme (Rendering)
1. L'utilisateur sélectionne l'Architecture (Nommée "Template V3").
2. Ce modèle V3 est configuré en BDD pour appeler le Formulaire "Projet_V1".
3. `TemplateManager.ps1` capture cet événement d'association. 
4. Il lit la définition JSON du Formulaire.
5. Une boucle parcourt le JSON et appelle des fonctions natives WPF (ex: `New-Object System.Windows.Controls.TextBox`) pour recréer l'interface visuelle conçue dans FormEditor.

### 2. Transmission Prévisualisation (PreviewLogic)
Chaque contrôle dynamique textuel injecté par TemplateManager.ps1 reçoit un événement interactif (`Add_TextChanged` ou `Add_SelectionChanged`).
À chaque fois que l'utilisateur écrit une lettre ou change une valeur dans l'interface, la fonction centralisée `Get-PreviewLogic.ps1` du composant Core s'active.
- Cette fonction observe toutes les TextBox dynamiques.
- Elle recompose une Table Hash (`$Replacements`).
- Elle met à jour l'aperçu Texte et relance un `Update-TreePreview`.

## 💡 Exemple d'Utilisation

```text
1. L'utilisateur clique sur "Déploiement Complet".
2. Il choisit l'architecture : "Archivage Legal".
3. Cela déclenche l'apparition d'un formulaire dynamique :
    -> [Label] "Année à archiver :"
    -> [TextBox] Vide (nommée Input_Year)
4. L'utilisateur type "2025" dans la Textbox.
5. À chaque frappe (2, 0, 2, 5), le TemplateManager prévient le panneau de prévisualisation (Aperçu) qui remplace {Year} de son architecture par "2025".
6. Clic "Étape Suivante" pour passer à la phase Déploiement.
```
