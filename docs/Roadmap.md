# Le Plan de Développement Détaillé
## Phase 0 : Fondation et Environnement de Développement (Durée estimée : 1/2 journée)
*Objectif : Mettre en place un squelette de projet propre et professionnel avant d'écrire la moindre ligne de logique.*
**Création du Dépôt GitHub :**
- Créez un nouveau dépôt public sur GitHub (ex: PowerShell-Admin-ToolBox).
- Initialisez-le avec :
  - Un fichier README.md (même basique pour l'instant).
  - Une licence, par exemple MIT License, qui est permissive et très courante pour les projets open-source.
  - Un fichier .gitignore. Utilisez un template standard pour VisualStudioCode et PowerShell. Il doit ignorer les dossiers bin/, obj/, les fichiers de configuration utilisateur (*.user.json), etc.
**Mise en Place de la Structure des Dossiers :**
- Clonez le dépôt sur votre machine locale.
- Créez l'arborescence de dossiers exacte définie dans notre plan. **Ne sautez aucune étape.**
```
PowerShell-Admin-ToolBox/
├── docs/
├── src/
│   ├── PSToolBox/
│   │   ├── Assets/Styles/
│   │   ├── Views/
│   │   └── ViewModels/
│   ├── Modules/
│   │   ├── PSToolBox.Core/
│   │   │   ├── Public/
│   │   │   └── Private/
│   │   └── Tools/
│   └── Config/
├── tests/
└── .gitignore, LICENSE, README.md
```
**Création du Thème Graphique Central (Global.xaml) :**
- Créez le fichier src/PSToolBox/Assets/Styles/Global.xaml.
- **Action :** Définissez **uniquement** vos couleurs de base (`PrimaryColor`, `GrayColor`, etc.) et vos styles de texte (`H1Style`, `H2Style`, etc.) comme vous l'aviez fait dans votre ancien styles.xaml. Ne créez pas encore les styles pour les contrôles.
**Création de la Vitrine des Composants :**
- Créez un dossier src/Modules/Tools/ComponentShowcase/.
- À l'intérieur, créez un fichier Views/ComponentShowcase.View.xaml.
- **Action :** Dans ce fichier XAML, ajoutez une instance de chaque contrôle que vous prévoyez d'utiliser (Button, TextBox, ComboBox, DataGrid, etc.). Appliquez-leur les styles de texte que vous venez de créer (ex: `<TextBlock Style="{StaticResource H1Style}" Text="Titre de Niveau 1"/>`).
- Créez un script de lancement temporaire à la racine du projet (_runShowcase.ps1) qui charge et affiche cette fenêtre.
- Livrable de la Phase 0 : Un dépôt GitHub structuré, et une fenêtre "vitrine" qui s'affiche, même si les contrôles sont encore au style par défaut de Windows.
## Phase 1 : Développement du Module PSToolBox.Core (Durée estimée : 2 jours)
*Objectif : Construire la "boîte à outils" interne réutilisable, avec des fonctions robustes et testables.*
**Création du Manifeste du Module :**
- Créez le fichier src/Modules/PSToolBox.Core/PSToolBox.Core.psd1.
- **Action :** Remplissez les métadonnées de base (Author, Description). Dans la section FunctionsToExport, listez les noms des fonctions que nous allons créer ('Show-ToolBoxWindow', 'Get-ToolBoxConfig', 'Write-ToolBoxLog').
**Implémentation du Service de Configuration :**
- Créez le fichier de template src/Config/settings.template.json avec les clés dont vous aurez besoin (ex: ClientID, TenantID).
- **Action :** : Créez la fonction Get-ToolBoxConfig dans le dossier Public/ de votre module Core. Sa logique :
  - Trouver le dossier %APPDATA%\PSToolBox. Le créer s'il n'existe pas.
  - Vérifier si settings.user.json existe dedans.
  - S'il n'existe pas, copier settings.template.json vers cet emplacement.
  - Lire et retourner le contenu de settings.user.json sous forme d'objet PowerShell.
**Implémentation du Service de Journalisation :**
- **Action :** Créez la fonction Write-ToolBoxLog dans le dossier Public/. Elle doit prendre des paramètres comme -Message, -Level ('Info', 'Warning', 'Error'), et -Target (un ObservableCollection par exemple).
**Implémentation du Service de Fenêtrage (MVVM Glue) :**
- **Action :** Créez la fonction Show-ToolBoxWindow dans le dossier Public/. Ses paramètres seront `-ViewModel` et `-ViewPath`. Sa logique :
  - Charger le fichier XAML de la vue.
  - Lier le ViewModel à la vue : `$View.DataContext = $ViewModel`.
  - Appliquer le thème global : `$View.Resources.MergedDictionaries.Add($PathToGlobalXaml)`.
  - Afficher la fenêtre (Show() ou ShowDialog()).
**Tests Unitaires (Pester) :**
- **Action :** Créez le fichier tests/PSToolBox.Core.Tests.ps1. Écrivez un premier test simple qui vérifie que Get-ToolBoxConfig crée bien le fichier settings.user.json s'il est manquant.
- Conseil de Pro : Installez l'extension Pester pour VSCode.
## Phase 2 : Développement du Lanceur Principal (PSToolBox) (Durée estimée : 1 jour)
*Objectif : Créer la fenêtre principale qui découvre et affiche les outils disponibles.*
**Création du ViewModel Principal :**
- Créez le fichier `src/PSToolBox/ViewModels/Main.ViewModel.ps1`.
- Action : Ce script définira une classe ou un PSCustomObject qui contiendra :
  - Une propriété `[System.Collections.ObjectModel.ObservableCollection[PSCustomObject]]$Tools` pour la liste des outils.
  - Une propriété `$SelectedTool` pour l'outil actuellement sélectionné.
  - Une fonction/méthode Discover-Tools qui scanne `src/Modules/Tools/`, lit les manifestes `*.Tool.psd1` et peuple la collection $Tools.
  - Une Command (pour l'instant, une simple fonction) `Launch-SelectedToolCommand` qui lancera l'outil.
**Création de la Vue Principale :**
- Créez `src/PSToolBox/Views/MainWindow.xaml`.
- **Action :** Utilisez un ItemsControl lié à la propriété Tools du ViewModel (ItemsSource="{Binding Tools}"). L'élément sélectionné (SelectedItem) sera lié à la propriété $SelectedTool (SelectedItem="{Binding SelectedTool, Mode=TwoWay}"). Le bouton "Lancer" sera lié à la Command (Command="{Binding LaunchSelectedToolCommand}").
**Création du Point d'Entrée :**
- Créez src/PSToolBox/PSToolBox.ps1.
- **Action :** Ce script est très simple :
  - Import-Module ./Modules/PSToolBox.Core/PSToolBox.Core.psd1
  - Chargez et exécutez le script du ViewModel principal pour en créer une instance.
  -  Show-ToolBoxWindow -ViewModel $MainViewModel -ViewPath "./Views/MainWindow.xaml".
## Phase 3 : Implémentation du Premier Outil (AD-UserDisable) (Durée estimée : 2-3 jours)
*Objectif : Mettre en pratique l'architecture MVVM et créer un "modèle" pour tous les futurs outils.*
**Création du Manifeste de l'Outil :**
- Créez le dossier de l'outil et son manifeste .../Tools/AD-UserDisable/AD-UserDisable.Tool.psd1 en suivant le format que nous avons défini.
**Création du ViewModel (DisableUser.ViewModel.ps1) :**
- **Action :** C'est le cerveau. Créez toutes les propriétés nécessaires ($UserEmail, $SelectedUser, [ObservableCollection]$Logs) et les commandes ($SearchCommand, $DisableCommand). La logique de ces commandes appellera les cmdlets ActiveDirectory et Microsoft.Graph, et utilisera Write-ToolBoxLog du module Core pour la journalisation.
**Création de la Vue (DisableUser.View.xaml) :**
- **Action :** C'est la partie "stupide". Construisez l'interface en utilisant les styles de Global.xaml.
- Liez chaque contrôle à une propriété du ViewModel.
  - `<TextBox Text="{Binding UserEmail, Mode=TwoWay, UpdateSourceTrigger=PropertyChanged}" />`
  - `<TextBlock Text="{Binding SelectedUser.DisplayName}" />`
  - `<Button Content="Rechercher" Command="{Binding SearchCommand}" />`
- Liez la RichTextBox à la collection $Logs (cela demandera une petite fonction d'aide dans le module Core).
**Test de Lancement :**
- Lancez l'application principale (PSToolBox.ps1). L'outil "Désactivation Utilisateur AD" doit apparaître.
- Cliquez dessus. Le ViewModel du lanceur principal doit appeler Show-ToolBoxWindow et lancer votre outil.
- Livrable de la Phase 3 : Un premier outil entièrement fonctionnel, respectant scrupuleusement le pattern MVVM. C'est votre preuve de concept.
## Phase 4 : Expansion, Finalisation et Documentation
*Objectif : Valider l'architecture en migrant un second outil et préparer le projet pour la communauté.*
**Migration d'un Deuxième Outil :**
- **Action :** Répétez la Phase 3 pour un autre de vos outils, par exemple Graph-ListUsers. Cela vous permettra de valider et de consolider votre approche.
**Rédaction de la Documentation :**
- **Action :** Maintenant que le processus est clair, rédigez les fichiers dans le dossier docs/ :
  - `architecture.md` : Expliquez votre structure de dossiers.
  - `contributing-new-tool.md` : Rédigez un tutoriel "pas à pas" pour un développeur externe. C'est le document le plus important pour la croissance du projet.
**Amélioration du README.md Principal :**
- **Action :** Mettez-le à jour avec une description complète, des captures d'écran, et les guides d'installation et d'utilisation.