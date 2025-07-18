# Feuille de Route de Développement
Voici les étapes détaillées, du plus simple au plus complexe, pour construire notre application.

---

## Jalon 0 : Initialisation du Projet & Dépôt GitHub (Durée : ~1-2 heures)
*Cette phase met en place les fondations non-techniques.*
- **Tâche 0.1 :** Initialiser le dépôt GitHub avec les fichiers essentiels :
  - README.md : Description initiale du projet.
  - LICENSE : Choisir la licence **MIT**.
  - .gitignore : Utiliser un template standard pour "PowerShell" et "VisualStudioCode". Y ajouter immédiatement config.json et *.log.
- **Tâche 0.2 :** Créer la structure de dossiers finale dans le projet local et la commiter.

```
/PowerShell-Admin-ToolBox
├── .vscode/                    # Configuration VSCode
│   ├── tasks.json             # Tâches de build/test
│   ├── extensions.json        # Extensions recommandées
│   └── settings.json.template # Template de paramètres
├── assets/                    # Ressources visuelles
│   ├── icons/                 # Icônes .ico pour l'application
│   ├── images/                # Screenshots et documentation
├── config/                    # Configuration
│   ├── config.template.json   # Template de configuration
│   └── schemas/               # Schémas JSON pour validation
├── docs/                      # Documentation
│   ├── user-guide/           # Guide utilisateur
│   ├── dev-guide/            # Guide développeur
│   └── architecture/         # Diagrammes et spécifications
├── src/                       # Code source
│   ├── Modules/
│   │   ├── Core/             # Module utilitaire central
│   │   └── Tools/            # Outils individuels
│   ├── UI/
│   │   ├── Styles/           # Thèmes et styles XAML
│   │   ├── Views/            # Fenêtres XAML
│   │   └── ViewModels/       # ViewModels PowerShell
│   ├── Tests/                # Tests unitaires Pester
│   └── Launcher.ps1          # Point d'entrée principal
├── build/                     # Scripts de build et packaging
└── examples/                  # Exemples de configuration
```

## Jalon 1 : Le Cœur Visuel - Le Thème de l'Application (Durée : ~1-2 jours)
*C'est notre priorité absolue, comme demandé. Nous créons notre identité visuelle.*
- **Tâche 1.1 :** Recherche et Conception du Thème (4 heures)
**Objectif :** Définir l'identité visuelle moderne et professionnelle
Étapes de recherche :
1. **Analyse des tendances UI/UX 2025**
   - Étude des applications Microsoft (Teams, Visual Studio, Azure Portal)
   - Analyse des thèmes Material Design et Fluent Design
   - Benchmark des outils d'administration concurrents
2. **Définition de la palette de couleurs**
   - Couleur primaire : Bleu professionnel (`#0078d4`)
   - Couleur secondaire : Gris moderne (`#323130`)
   - Couleur d'accent : Orange énergique (`#ff8c00`)
   - Couleurs sémantiques : Succès (`#107c10`), Erreur (`#d13438`), Attention (`#ffd700`s)
3. **Choix typographique**
  - Police primaire : Segoe UI (natif Windows)
  - Police monospace : Consolas (pour les codes/logs)
  - Hiérarchie typographique : H1 (16pt), H2 (14pt), Body (12pt), Caption (10pt)
- **Tâche 1.2 :** Définir la palette de couleurs `(SolidColorBrush)` dans le thème : `PrimaryColor`, `SecondaryColor`, `AccentColor`, `TextColor`, `BorderColor`, `SuccessColor`, `ErrorColor`, etc.
- **Tâche 1.3 :** Créer les styles **implicites** (sans x:Key) pour les contrôles de base (`Window`, `Button`, `TextBox`, `TextBlock`, `DataGrid`, etc.). Ces styles définiront la police, la taille, les couleurs de base, mais JAMAIS de `Margin` ou `Padding`.
- **Tâche 1.4 :** Créer les styles explicites (x:Key="...") pour les variations :
  - Boutons : `PrimaryButton`, `SecondaryButton`, `SuccessButton`, `DangerButton`.
  - Textes : `H1`, `H2`, `DescriptionText`, `StatusText`.
  - Conteneurs : `PaddedGrid`, `SpacedStackPanel` (ces styles auront des Margin pour gérer l'espacement de manière cohérente).
- **Tâche 1.5 :** LA VITRINE DE STYLES
  - Créer `src/UI/Views/StyleShowcase.View.xaml`. Ce fichier contiendra un exemplaire de chaque contrôle, utilisant tous les styles que nous avons créés. C'est notre catalogue visuel.
  - Créer `src/UI/StyleShowcase.ps1`. Ce script aura pour unique rôle de charger et d'afficher la fenêtre StyleShowcase.View.xaml pour que nous puissions voir notre thème en action.

> [!IMPORTANT]
> Tout les scripts powershell seront réalisé en powershell 7.5 minimum.

## Jalon 2 : La Boîte à Outils - Le Module Core (Durée : ~2-3 jours)
*On forge les outils qui serviront à construire tout le reste.*
- **Tâche 2.1 :** Créer la structure du module : `src/Modules/Core/PSToolBox.Core.psm1` et le manifeste `PSToolBox.Core.psd1`.
- **Tâche 2.2 :** Développer la fonction `Get-ToolboxConfig` : Une fonction qui recherche, valide et charge le fichier `config.json` en un objet PowerShell accessible.
- **Tâche 2.3 :** Développer la fonction `Show-WpfWindow` : C'est le successeur de Load-File. Elle prendra en paramètre un chemin XAML, un ViewModel, et appliquera automatiquement le thème central.
- **Tâche 2.4 :** Développer la fonction `Invoke-Log` : Le successeur de `Add-RichText`. Elle écrira dans une RichTextBox de l'UI ET, si activé dans la config, dans un fichier log.
- **Tâche 2.5 :** Créer/Migrer les fenêtres de dialogue (`Show-MessageBox`, `Show-InputBox`, `Show-AdminLogin`) en fonctions propres dans le module Core. Elles doivent retourner un résultat ($true, $false, un objet, etc.) au lieu d'utiliser des variables globales.
- **Tâche 2.6 :** Créer un modèle de ViewModel de base (`ViewModel.Base.ps1`) que les autres ViewModels pourront utiliser (dot-source). Il implémentera `INotifyPropertyChanged` pour que l'UI se mette à jour automatiquement quand une propriété change. C'est la pierre angulaire du MVVM.

## Jalon 3 : Le Portail - L'Application Principale (Durée : ~2 jours)
*On assemble les pièces pour créer le lanceur.*
- **Tâche 3.1 :** Créer le ViewModel src/Launcher.ViewModel.ps1 :
  - Il utilisera le modèle `ViewModel.Base.ps1`.
  - Il aura une propriété `[ObservableCollection[object]]$Tools` et `$SelectedTool`.
  - Il aura une fonction `Load-Tools` qui scanne `src/Modules/Tools` à la recherche de fichiers manifestes (.tool.json).
  - Il aura une commande `Launch-SelectedTool` pour lancer l'outil sélectionné.
- **Tâche 3.2 :** Créer la vue `src/UI/Views/ToolBox.View.xaml` :
Elle sera entièrement construite avec les styles de notre thème.
Elle utilisera des Binding pour se lier aux propriétés du ViewModel.
- **Tâche 3.3 :** Mettre à jour src/Launcher.ps1 :
  1. `Import-Module ./Modules/Core/PSToolBox.Core.psm1`
  2. Charge la configuration.
  3. Crée une instance du `ToolBox.ViewModel.ps1`.
  4. Appelle la méthode `Load-Tools()` du ViewModel.
  5. Appelle Show-WpfWindow en lui passant le chemin du XAML et le ViewModel.

## Jalon 4 et Suivants : Développement des Outils
*À partir d'ici, chaque outil est un mini-projet qui suit le même patron.*
- Pour chaque outil (ex: `CheckModule`, `CreateUser`, etc.) :
  1. Créer son dossier : `src/Modules/Tools/CreateUser/`.
  2. Créer son manifeste : `CreateUser.tool.json`.
  3. Créer sa Vue : `CreateUser.View.xaml` (en utilisant les styles du thème).
  4. Créer son ViewModel : `CreateUser.ViewModel.ps1` (contenant toute la logique).
  5. Créer son point d'entrée : `CreateUser.ps1` (le script qui lie la Vue et le ViewModel).

## Jalon Final : Publication
*Préparation pour la communauté.*
- **Tâche F.1 :** Rédiger une documentation complète (`README.md`, `CONTRIBUTING.md`).
- **Tâche F.2 :** Créer une Release v1.0 sur GitHub avec un package .zip prêt à l'emploi.