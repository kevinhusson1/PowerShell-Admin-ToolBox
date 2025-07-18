# Mémoire de Projet : PowerShell Admin ToolBox

## 1. Vision du Projet (Le But Final)
L'objectif du projet **PowerShell Admin ToolBox** est de créer une application de bureau de qualité professionnelle, open-source, destinée aux administrateurs systèmes et aux ingénieurs IT. Elle transcendera le concept de "lanceur de scripts" pour devenir une suite d'outils graphiques, intuitifs et intégrés, qui simplifient les tâches d'administration complexes sur des environnements hybrides (Active Directory, Azure AD, SharePoint, etc.).
Mémoire de Projet - PowerShell Admin ToolBoxLe projet doit être un parangon de qualité, démontrant comment allier la puissance de PowerShell à l'élégance des interfaces WPF, tout en suivant les meilleures pratiques de développement logiciel.

## 2. Objectifs Clés (Ce qu'il faut réaliser)
*   **Modularité Absolue :** Le cœur de l'application sera un module PowerShell (PSToolBox.Core) contenant des fonctions utilitaires robustes, testées et réutilisables pour l'UI, la journalisation et la gestion de la configuration.
*   **Extensibilité :** L'architecture permettra à quiconque (y compris la communauté) d'ajouter de nouveaux outils en créant simplement un dossier et un fichier manifeste, sans jamais toucher au code du lanceur principal.
*   **Expérience Utilisateur (UX) Exceptionnelle :** L'application sera visuellement cohérente, réactive et intuitive. La complexité sera masquée derrière des interfaces claires. L'esthétique n'est pas une option, c'est un prérequis.
*   **Maintenabilité :** En adoptant des patrons de conception comme le MVVM (Model-View-ViewModel), nous séparerons strictement l'interface (le "quoi") de la logique (le "comment"), rendant le code plus facile à lire, à déboguer et à faire évoluer.
Configuration Centralisée : Toutes les informations spécifiques à un environnement (IDs de tenant, noms de domaine, etc.) seront externalisées dans un fichier de configuration unique, rendant l'application facilement adaptable.

## 3. Principes Directeurs (Comment y arriver)
1. **"Style-Driven Development" :** La première phase de développement se concentrera sur la création d'un thème graphique complet et d'une "vitrine" de styles. Cette fondation visuelle garantira la cohérence de toutes les fenêtres développées par la suite.
2. **Architecture MVVM (Model-View-ViewModel) :** C'est notre dogme.
   _ **La Vue (View) :** Le fichier XAML. Il est "stupide". Il ne contient que la description de l'interface et des liaisons de données (Binding). **Aucun code logique. Aucun style en ligne.**
   _ **Le Modèle (Model) :** Les objets de données brutes (ex: un objet représentant un utilisateur AD).
   _ **Le ViewModel :** Un script PowerShell (*.ViewModel.ps1). Il est le cerveau. Il contient toute la logique, les propriétés (ex: la liste des utilisateurs à afficher) et les commandes (ex: la fonction à exécuter quand on clique sur un bouton). Il ne sait rien de l'existence des boutons ou des TextBox.
3. **"Everything is a Module" :** Les fonctions partagées seront dans un module Core. À terme, chaque outil pourrait même être son propre module, favorisant une isolation parfaite.
4. **"No Globals" Policy :** Nous éviterons au maximum les variables $global:. Les informations seront passées via les paramètres des fonctions, et les résultats seront retournés par les fonctions. Cela rend le flux de données prévisible et évite les effets de bord.