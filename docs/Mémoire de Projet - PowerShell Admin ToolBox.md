# PowerShell Admin ToolBox
![](https://img.shields.io/badge/status-in%20development-blue) ![](https://img.shields.io/badge/PowerShell-7.2+-blueviolet.svg) ![](https://img.shields.io/badge/License-MIT-green.svg)

Une suite d'outils graphiques, modernes et extensibles pour l'administrateur système moderne, construite avec la puissance de PowerShell et l'élégance de WPF.

## 📜 Synthèse (Executive Summary)

> Le projet **PowerShell Admin ToolBox** vise à développer une application de bureau open-source de qualité professionnelle pour les administrateurs et ingénieurs systèmes. L'objectif est de dépasser le stade du simple "lanceur de scripts" pour offrir une suite d'outils graphiques intégrés, modernes et intuitifs. En s'appuyant sur une architecture modulaire, le patron de conception **MVVM (Model-View-ViewModel)** et une approche rigoureuse du développement, ce projet a pour vocation de devenir un outil de référence dans la communauté PowerShell, ainsi qu'un exemple de ce qu'il est possible de réaliser en combinant la puissance de PowerShell et l'élégance de WPF.

## 🎯 Contexte et Problématique

L'administration des systèmes d'information modernes est devenue un exercice complexe, jonglant entre des environnements sur site (On-Premise) comme Active Directory et des services Cloud comme Azure AD, Exchange Online ou SharePoint. Les administrateurs s'appuient massivement sur PowerShell pour automatiser et gérer ces environnements, mais cela se traduit souvent par une multitude de scripts épars, des interfaces en ligne de commande austères et un manque de cohérence entre les outils.

Ce projet répond à un besoin critique : **centraliser, simplifier et moderniser l'outillage de l'administrateur système.** Il propose de remplacer la fragmentation des scripts par une application unique, cohérente et extensible.

## ✨ Vision et Objectifs Clés

**Vision :** Devenir la "caisse à outils" de prédilection des professionnels de l'IT utilisant PowerShell, en fournissant une plateforme stable, élégante et extensible qui transforme les tâches complexes en opérations simples et graphiques.

Pour réaliser cette vision, nous nous fixons les objectifs suivants :

*   **Modularité Absolue :** Le cœur de l'application sera un module PowerShell indépendant (`PSToolBox.Core`) contenant toutes les fonctions utilitaires communes (UI, logs, config), garantissant la non-répétition du code.
*   **Extensibilité Maximale :** L'architecture permettra à quiconque d'ajouter un nouvel outil en créant simplement un dossier autonome contenant un fichier "manifeste", sans jamais avoir besoin de modifier le code du lanceur principal.
*   **Expérience Utilisateur (UX) Exceptionnelle :** L'application offrira une interface visuellement cohérente, réactive et intuitive. La complexité technique sera masquée, pas exposée.
*   **Maintenabilité et Lisibilité :** En adoptant des standards de développement stricts, notamment le patron MVVM, le code sera facile à comprendre, à déboguer et à faire évoluer, que ce soit par les auteurs originaux ou par la communauté.
*   **Configuration Centralisée et Sécurisée :** Les informations de configuration spécifiques à un environnement (secrets, identifiants) seront gérées de manière sécurisée et externe au code source, permettant à chaque utilisateur d'adapter l'outil à son contexte sans risque.

## 🏗️ Architecture Technique

Le projet s'articulera autour d'une structure claire et éprouvée, favorisant la séparation des préoccupations.

### Structure du Répertoire

```bash
PowerShell-Admin-ToolBox/
├── .github/                  # Workflows CI/CD et modèles
├── docs/                     # Documentation du projet
├── src/                      # Code source de l'application
│   ├── PSToolBox/            # Le lanceur principal (le "Shell")
│   ├── Modules/
│   │   ├── PSToolBox.Core/   # Module des fonctions partagées
│   │   └── Tools/            # Chaque sous-dossier est un outil
│   └── Config/               # Gestion de la configuration
└── tests/                    # Tests unitaires Pester
```

### Description des Composants Clés

1.  **Le Lanceur Principal (`src/PSToolBox/`) :** C'est la coquille de l'application. Son unique rôle est de découvrir les outils disponibles et de les présenter à l'utilisateur. Il est léger et ne contient aucune logique métier.

2.  **Le Module Core (`src/Modules/PSToolBox.Core/`) :** La fondation technique. Il fournit des services essentiels sous forme de fonctions PowerShell réutilisables, telles que :
    *   L'affichage des fenêtres et des boîtes de dialogue.
    *   La journalisation (logging).
    *   La gestion de la configuration.

3.  **L'Écosystème d'Outils (`src/Modules/Tools/`) :** C'est le cœur vivant de l'application.
    *   Chaque sous-dossier (ex: `AD-UserDisable`) est un **outil autonome**.
    *   Chaque outil est défini par un **manifeste (`*.Tool.psd1`)** qui décrit son nom, son icône, sa description et son point d'entrée. C'est ce fichier qui permet au lanceur principal de découvrir l'outil dynamiquement.

### Le Patron de Conception MVVM (Model-View-ViewModel)

C'est le pilier de notre architecture logicielle pour chaque outil.

*   **La Vue (View - `.xaml`) :** L'interface graphique. Elle est "stupide". Elle ne fait que décrire l'apparence des éléments et comment ils sont liés (via `{Binding}`) aux données. **Zéro code logique.**
*   **Le Modèle (Model - `*.Model.ps1`) :** Les objets de données brutes. Par exemple, une classe `[AdUser]` avec des propriétés `[string]$DisplayName`, `[bool]$Enabled`.
*   **Le Vue-Modèle (ViewModel - `*.ViewModel.ps1`) :** Le cerveau de l'outil. C'est un script PowerShell qui contient toute la logique : les actions à exécuter (les `Commands`), les données à afficher (les propriétés comme `$ListOfUsers`) et l'état de l'interface (ex: `$IsSearchButtonEnabled`). **Il ne manipule jamais directement les contrôles de l'interface.**

## ⚖️ Principes de Conception (Notre "Constitution")

1.  **Le Modèle-Vue-VueModèle (MVVM) comme Dogme :** La séparation stricte entre l'interface et la logique est non négociable.
2.  **Une Approche Pilotée par le Style (`Style-Driven`) :** Un thème graphique global et unifié est défini en premier. Tout nouvel élément d'interface doit utiliser ce thème pour garantir la cohérence.
3.  **Tout est un Module :** La réutilisabilité est clé. Les fonctions partagées sont dans le module Core. À terme, chaque outil deviendra son propre module.
4.  **Politique "Zéro Global" :** Les variables `$global:` sont proscrites. Les données circulent via les paramètres et les valeurs de retour des fonctions, rendant le flux d'exécution prévisible.
5.  **La Sécurité n'est pas une Option :** Les informations sensibles (mots de passe, clés d'API, certificats) ne seront jamais stockées en clair dans le code source. Des mécanismes de gestion de secrets seront utilisés.

## 🗺️ Feuille de Route Initiale

Le développement se déroulera en phases séquentielles :

*   **Phase 0 : Fondation & Squelette :** Mise en place du dépôt Git, de la structure des dossiers et d'une "vitrine" de composants XAML pour valider le thème graphique.
*   **Phase 1 : Développement du Module `PSToolBox.Core` :** Création des services fondamentaux (fenêtrage, configuration, journalisation) et de leurs tests unitaires.
*   **Phase 2 : Développement du Lanceur Principal :** Création de l'interface principale capable de découvrir et d'afficher dynamiquement les outils via leurs manifestes.
*   **Phase 3 : Implémentation du Premier Outil (Preuve de Concept) :** Migration complète d'un premier outil (ex: `AD-UserDisable`) sur la nouvelle architecture MVVM pour valider le modèle.
*   **Phase 4 : Expansion et Documentation :** Migration d'un second outil pour consolider l'architecture, et rédaction d'une documentation complète pour les utilisateurs et futurs contributeurs.

## 🤝 Opportunités pour les Contributeurs

Ce projet est pensé pour être ouvert et communautaire. Les contributeurs de tous niveaux sont les bienvenus. Un guide détaillé (`contributing-new-tool.md`) sera créé pour permettre à quiconque de :

*   Proposer des améliorations aux outils existants.
*   Corriger des bugs.
*   Développer et soumettre de tout nouveaux outils qui s'intégreront de manière transparente à la ToolBox.

## ✅ Conclusion

Le projet **PowerShell Admin ToolBox** est plus qu'une simple collection de scripts. C'est une démarche visant à élever le standard de l'outillage PowerShell en y appliquant les principes d'ingénierie logicielle modernes. Le produit final sera non seulement un outil puissant pour les professionnels de l'IT, mais aussi une ressource d'apprentissage et un projet communautaire exemplaire.