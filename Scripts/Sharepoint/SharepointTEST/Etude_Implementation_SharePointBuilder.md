# 🚀 Étude d'Implémentation : Intégration de Microsoft Graph API dans SharePointBuilder

**Date** : Mars 2026
**Objet** : Remplacement du moteur de déploiement SharePoint (PnP) par Microsoft Graph API pour fiabiliser la création de dossiers typés et de métadonnées ("Tags").

---

## 1. Contexte & Limites de l'Existant

Actuellement, `SharePointBuilder` (et par extension `SharePointRenamer`) s'appuyait sur le module **PnP.PowerShell** pour interagir avec SharePoint.

### Les problèmes majeurs rencontrés :
1. **Conflit de DLLs (Instabilité)** : Des incompatibilités bloquantes entre les librairies d'authentification (`Azure.Identity` / MSAL) et le module PnP ont rendu les scripts hautement instables et sensibles aux mises à jour.
2. **Gestion des "Tags" (Property Bags vs Colonnes)** : La V1 utilisait les *Property Bags* (sac de propriétés caché) qui ne sont pas supportés par le Modern UI de SharePoint. Il était donc impossible pour l'utilisateur de vérifier visuellement si un document ou dossier était lié à l'opération mère.
3. **Absence de requêtage global** : Retrouver les documents d'une même opération impliquait de parcourir physiquement l'arborescence, une opération extrêmement lente.

---

## 2. La Solution : L'Architecture Graph API (PoC Validé)

Le Proof of Concept récent a démontré avec succès que la **REST API de Microsoft Graph** (`Invoke-MgGraphRequest`) corrigeait tous ces points de friction sans avoir besoin de PnP.

### Gains apportés par la nouvelle architecture :
* **Authentification Silencieuse (App-Only)** : Dépendance exclusive au module `Azure` de la ToolBox. Stabilité garantie à 100%.
* **Métadonnées Visuelles ("Dossier Avancé")** : Via les "Content Types" Graph, le dossier devient une entité métier (ex: Dossier Opération). Les tags (ID Opération, Statut) sont injectés sous forme de vraies colonnes SharePoint, filtrables et visibles par l'humain dans le panneau d'information.
* **Recherche Transversale Instantanée** : La création d'un index de métadonnées permet de retrouver à n'importe quel moment "tous les dossiers liés au Lot n°12 de la Résidence Y", indépendamment de leur emplacement physique dans SharePoint.

---

## 3. Champ d'Application dans SharePointBuilder

La réécriture impactera directement les fonctionnalités fondamentales de `SharePointBuilder` (principalement le script de publication `New-AppSPStructure.ps1` et les fonctions sous-jacentes).

### Périmètre détaillé :

1. **Génération de l'ID Unique (Déploiement)** :
   * L'ID unique généré au démarrage par Builder ne sera plus enfoui dans un PropertyBag mais sera injecté en tant que "Tag" (`Vosgelis_AppDeploymentID`) dans les colonnes du dossier destination.

2. **Génération de l'Architecture (Custom Content Type)** :
   * Avant de créer le moindre dossier, SharePointBuilder vérifiera/créera le Type de contenu "Dossier Avancé" (ou "Dossier Vosgelis") et s'assurera qu'il est rattaché à la bibliothèque de destination.

3. **Création des Dossiers** :
   * Le script ne fera plus un simple "Add-PnPFolder". 
   * Il appellera `New-AppGraphFolder` (pour créer la couche physique).
   * Immédiatement suivi de `Set-AppGraphListItemMetadata` (pour modifier son ContentType et patcher toutes ses valeurs : `Vosgelis_RefOperation`, `Vosgelis_Statut`, etc.).

4. **Gestion des Droits (Permissions)** :
   * *(À valider)* Microsoft Graph permet également l'assignation fine des droits (`/permissions`), ce qui remplacera `Set-PnPFolderPermission`. La logique de cassage d'héritage fonctionnera sur le endpoint Graph des DriveItems.

5. **Liaison Inter-Bibliothèques** :
   * Les dossiers de Suivi DP (créés dans une autre bibliothèque) seront automatiquement taggés avec l'ID du dossier Parent (ex: l'Ordre de Service).

---

## 4. Impact sur le Code de SharePointBuilder

La refonte se concentrera sur le remplacement chirurgical des appels `*-PnP*`.

| Fonctionnalité Visée | Avant (PnP) | Après (Graph API ToolBox) |
| :--- | :--- | :--- |
| **Authentification** | `Connect-PnPOnline` | `Connect-AppAzureCert` |
| **Création Dossier** | `Add-PnPFolder` | `New-AppGraphFolder` |
| **Génération Taxonomie** | `Add-PnPContentType` / `Field` | `New-AppGraphContentType` / `SiteColumn` |
| **Application Propriétés**| `Set-PnPPropertyBagValue` | `Set-AppGraphListItemMetadata` |
| **Sécurité/Héritage** | `Set-PnPFolderPermission` | *(À développer via l'API Permissions Graph)* |

### Impacts collatéraux
* **Nettoyage des modules** : PnP.PowerShell sera retiré des fichiers `.psd1` et de l'initialisation.
* **Refonte de SharePointRenamer** : Renamer devra rechercher l'ID du dossier en lisant la colonne Graph du ListItem plutôt qu'en allant chercher le sac de propriétés PnP. (Le gain de performance sur Renamer sera de l'ordre de 400% grâce à la requête filtre Graph native).

---

## 5. Modifications Structurelles Complémentaires (Refactoring Identifié)

Au-delà de la bascule vers Microsoft Graph, d'autres modifications structurelles sur le code de `SharePointBuilder` sont requises pour garantir sa pérennité et sa maintenabilité :

1. **Abandon Total des Runspaces Manuels pour la UI** : 
   La version actuelle de SharePointBuilder utilise des `[runspacefactory]::CreateRunspace()` complexes pour gérer l'asynchronisme. La Toolbox dispose aujourd'hui d'un mécanisme standard bien plus fiable : les `Jobs` ou l'encapsulation `Runspace` native (cf. script *SharePointRenamer* ou le standard ToolBox). Il faut homogénéiser la gestion du BackgroundWorker UI avec le reste du projet.
2. **Découplage UI / Métier** :
   Le script `SharePointBuilder.ps1` (backend) est actuellement trop intriqué avec son frontend (`Update-UI`, variables globales liées à la fenêtre, etc.). Il faudra isoler la logique de création (Graph) dans une classe ou un orchestrateur distinct qui ne fait que "publier" son état vers l'interface WPF.
3. **Optimisation GDI (Fuites Mémoire WPF)** :
   Assainir les accès aux éléments UI via le `Dispatcher.Invoke` standardisé de la ToolBox.

---

## 6. Planning d'Implantation (Chantier V2)

Afin de garantir que la production actuelle (PnP) ne soit en aucun cas impactée durant la refonte, une stratégie de "Duplication V2" isolée est mise en place. 

Voici l'étendue claire des travaux, par ordre de dépendance stricte :

### Étape 1 : Isolation et Préparation de la "V2"
- [ ] Dupliquer intégralement le dossier `Scripts/Sharepoint/SharepointBuilder` vers `Scripts/Sharepoint/SharepointBuilderV2`.
- [ ] Générer un nouveau GUID et mettre à jour le `manifest.json`.
- [ ] Mettre à jour les labels de titre dans le `DefaultUI.xaml` pour indiquer "(Graph API V2)".

### Étape 2 : Nettoyage et Refonte des Fondations Métiers
- [ ] Retirer tout appel (import et chargement) au module `PnP.PowerShell` de l'initialisation de la V2.
- [ ] Intégrer les nouvelles commandes `*-AppGraph*` (créées durant le PoC) au sein de la logique métier.
- [ ] Refactoriser l'authentification (`Connect-AppAzureCert`).

### Étape 3 : Implémentation du moteur Graph (Remplacement de la fonction Set-AppSPFolderProperties)
- [ ] Remplacer les appels de création (`Add-PnPFolder`) par `New-AppGraphFolder`.
- [ ] Implémenter l'appel automatique de taxonomie: Création du `Content Type` "Dossier Avancé" à la volée.
- [ ] Remplacer le taggage "Property Bag" par `Set-AppGraphListItemMetadata` (Tags visibles).
- [ ] Assurer la propagation de l'ID Unique (DeploymentID) depuis le parent jusqu'à la racine via les champs Graph.

### Étape 4 : Gestion de la Sécurité (Si applicable)
- [ ] Étudier et remplacer `Set-PnPFolderPermission` par l'équivalent REST Microsoft Graph sur les `DriveItems` (Endpoint `/permissions`).

### Étape 5 : Refactoring Asynchrone / Interface (WPF)
- [ ] Remplacer la logique de Runspace manuel lourde par le modèle ToolBox optimisé.
- [ ] Lier les retours de Graph API (Succès/Échecs) au système de logs standard de la ToolBox (`Write-AppLog`).

### Étape 6 : Tests & Validation Finaux
- [ ] Déployer une architecture complète de test (Plusieurs sous-dossiers, droits limités) via la V2.
- [ ] Valider dans SharePoint la visibilité des colonnes (`Vosgelis_OperationID`).
- [ ] Faire un parallèle avec *SharePointRenamer* pour s'assurer que l'outil distant parvient à lire ces nouveaux tags Graph.
