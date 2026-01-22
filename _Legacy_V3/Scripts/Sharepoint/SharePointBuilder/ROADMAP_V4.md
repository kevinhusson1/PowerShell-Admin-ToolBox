# SharePoint Builder - Roadmap V4 (Enterprise Grade)

## 🎯 Vision et Objectifs

L'objectif de la version 4.0 est de faire passer le **SharePoint Builder** du statut d'outil fonctionnel (V3) à celui de **solution de production industrielle ("Enterprise Grade")**.
Cette évolution se concentre non plus sur l'ajout de fonctionnalités de base, mais sur la **robustesse**, la **prédictibilité** des actions, la **performance**, et l'outillage pour les utilisateurs avancés (DevOps).

Ce document sert de référence technique et fonctionnelle pour les futurs développements et doit inspirer la standardisation des autres outils de la `PowerShell-Admin-ToolBox`.

---

## 📅 Planning des Jalons (Milestones)

### 🥇 Phase 1 : Confiance & Fiabilité (Fondations)

**Priorité : CRITIQUE**
_L'objectif est de garantir qu'aucune régression par le code n'est possible et que l'utilisateur a une confiance aveugle dans les actions de l'outil avant qu'elles ne soient exécutées._

#### 1.1 Tests Unitaires & Non-Régression (Pester)

- **Objectif :** Sanctuariser la logique critique de déploiement.
- **Action :** Créer une suite de tests Pester pour le module `Toolbox.SharePoint`.
- **Détails Techniques :**
  - Mocker les commandes PnP (`Mock Connect-PnPOnline`, `Mock New-PnPFolder`) pour simuler les interactions SharePoint.
  - Tester les cas limites : noms de dossiers invalides, permissions manquantes, JSON malformé.
  - Intégration dans un pipeline CI/CD local (ex: script `Invoke-Build`).

#### 1.2 Mode Simulation "What-If" (Dry Run)

- **Objectif :** Permettre à l'administrateur de prévisualiser l'impact exact d'un déploiement sans toucher à la production.
- **Action :** Implémenter le switch `-WhatIf` sur `New-AppSPStructure`.
- **Sortie attends :** Un rapport détaillé (ex: Markdown ou GridView) listant chaque action :
  - `[SKIP]` Dossier 'Projet A' existe déjà.
  - `[CREATE]` Dossier 'Archive' sera créé.
  - `[GRANT]` Permission 'User X' sera ajoutée.

#### 1.3 Logging Structuré & Archivage

- **Objectif :** Faciliter le diagnostic post-mortem.
- **Action :** Évoluer du log visuel (RichTextBox) vers un log structuré.
- **Détails Techniques :**
  - Génération automatique d'un fichier de log structuré (JSON ou CSV) dans le dossier `Logs/` à chaque exécution.
  - Capture complète du contexte (Version du script, Utilisateur, Paramètres d'entrée, Exceptions avec StackTrace).

---

### 🥈 Phase 2 : Fonctionnalités "Power User" (Flexibilité)

**Priorité : ÉLEVÉE**
_Donner aux administrateurs experts les moyens de manipuler les données rapidement sans être contraints par l'interface graphique._

#### 2.1 Éditeur de Source JSON (Raw Mode)

- **Objectif :** Permettre l'édition rapide et massive de modèles complexes.
- **Action :** Ajouter un onglet "Code / Source" dans l'éditeur de modèles.
- **Fonctionnalités :**
  - Édition directe du JSON sous-jacent.
  - Validation syntaxique à la volée.
  - Synchronisation bidirectionnelle : une modif dans le JSON met à jour l'arbre visuel, et inversement.

#### 2.2 Portabilité des Modèles (Import/Export)

- **Objectif :** Faciliter le partage de configurations entre environnements ou collègues.
- **Action :** Ajouter des boutons d'Export/Import dans l'éditeur.
- **Format :** Fichiers `.json` autonomes contenant la structure + les métadonnées (description, auteur).

---

### 🥉 Phase 3 : Performance & UX (Optimisation)

**Priorité : MOYENNE**
_Améliorer la fluidité de l'outil et réduire la dépendance au réseau._

#### 3.1 Cache SQLite & Mode Offline

- **Objectif :** Affichage instantané au démarrage, indépendamment de la latence SharePoint/Graph.
- **Action :** Mettre en cache la liste des Sites et Bibliothèques dans la DB SQLite locale.
- **Mécanisme :**
  - Chargement immédiat depuis le cache au lancement de l'application.
  - Thread d'arrière-plan pour rafraîchir le cache ("Freshness check") et mettre à jour l'UI si des différences sont détectées.
  - Indicateur visuel "Données en cache" / "En ligne".

#### 3.2 Optimisation Asynchrone (RunspacePools)

- **Objectif :** Réduire l'overhead mémoire et CPU des Jobs PowerShell classiques.
- **Action :** Remplacer `Start-Job` (processus lourd) par des `Runspaces` (threads légers) pour les tâches fréquentes.
- **Cibles :** Validation N2/N3, listing des dossiers, vérifications d'existence utilisateu.

---

## 📐 Modèle de Référence pour la ToolBox

Cette roadmap V4 définit le standard de qualité pour tout futur développement dans la `PowerShell-Admin-ToolBox` :

1.  **Architecture V3** (Séparation Logic/UI/Data).
2.  **Validation pré-exécution** (Niveaux 1, 2, 3).
3.  **Tests automatisés** (Pester).
4.  **Mode What-If** natif.
