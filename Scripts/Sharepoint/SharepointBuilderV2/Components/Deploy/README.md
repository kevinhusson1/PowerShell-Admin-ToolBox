# 🚀 Composant : Deploy (Déploiement)

## 📌 Présentation
Le composant **Deploy** est le cœur opérationnel du SharePoint Builder. C'est ici que l'utilisateur, après avoir rempli son formulaire dynamique basé sur une règle de nommage et une architecture, lance la création physique des dossiers, publications, liens et fichiers dans SharePoint via l'API Graph.

## 🏗️ Architecture du Composant

Ce composant est divisé en plusieurs fichiers pour séparer l'interface utilisateur (UI), la gestion des événements et la logique métier lourde :

- `Deploy.xaml` : Le dictionnaire de ressources WPF (Interface) contenant la définition visuelle de l'onglet Déploiement (Section 1: Cibles, Section 2: Aperçu et Section 3: Options d'exécution).
- `Deploy.ps1` : Gère le cycle de vie de l'onglet, notamment le bouton principal "Déployer" et la gestion des logs d'exécution.
- `Register-SiteEvents.ps1` : Gère de manière asynchrone le chargement des Sites SharePoint, des Bibliothèques (Drives) et la sélection des collections de sites.
- **Dossier `Actions/`** :
  - `Invoke-AppSPDeployValidate.ps1` : Valide la saisie avant déploiement.
  - `Invoke-AppSPDeployFilter.ps1` : Filtre l'arbre de dépendance à déployer.
  - `Invoke-AppSPDeployExecute.ps1` : Le moteur asynchrone principal utilisant des Jobs PowerShell pour ne pas figer l'interface. Effectue concrètement les appels Graph (Création de dossier, assignation de droits, création de lien, etc.).

## ⚙️ Fonctionnement Détaillé

### 1. Sélection de la cible (Register-SiteEvents)
L'utilisateur tape un mot-clé. Le script interroge l'API Graph (`Get-MgSite`) avec un Dispatcher Timer pour ne pas spammer l'API.
Une fois le site sélectionné, les bibliothèques (`Drives`) sont chargées.

### 2. Le Moteur de Déploiement (Invoke-AppSPDeployExecute)
Pour ne pas figer l'UI (Hub & Spoke), l'exécution est transférée à un Runspace / Job en arrière-plan.
Il suit un mécanisme de file d'attente :
1. **Création du dossier parent** (Racine).
2. **Récursivité** : Création des sous-dossiers.
3. **Application des Tags et Permissions** : Sur les dossiers fraîchement créés via `Update-MgSiteListItem`.
4. **Création des éléments terminaux** : Fichiers, Liens URL, ou Publications (Lien vers un dossier distant).

### 3. Mutualisation Visuelle
Ce composant importe le script partagé `Invoke-AppSPReassembleTree` (via `Update-TreePreview`) issu du dossier Core pour afficher le `TreeView` "Flat JSON" du modèle simulé.

## 💡 Exemple de Flux de Déploiement

```text
1. L'utilisateur sélectionne le Site "Ressources Humaines" et la lib "Documents".
2. Il génère la structure "CONCEPTION" -> "Sous-dossier" avec le modèle "Projet RH".
3. Clic sur "Déployer" -> Deploy.ps1 capture l'événement.
4. Le bouton est désactivé et l'UI passe en mode "Chargement" (ProgressBar).
5. Invoke-AppSPDeployExecute est lancé dans un nouveau Runspace.
6. Le Runspace envoie ses logs de progression via un objet thread-safe (Synchronized Hashtable) vers l'UI.
7. L'API Graph est appelée : 
   - Get-AppPnPFolder -> New-AppPnPFolder (/Ressources Humaines/Documents/CONCEPTION)
8. Fin de tâche -> Dispatcher UI remet le bouton à l'état actif.
```
