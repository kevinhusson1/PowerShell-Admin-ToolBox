# Schéma JSON de Déploiement SharePoint Builder (v2.0)

Ce document décrit la structure formelle des fichiers JSON générés par le **SharePoint Builder V3.0** (Architecture "Flat JSON"). 
Contrairement aux précédentes versions où tous les éléments (fichiers, liens, publications) étaient profondément imbriqués dans les dossiers, ce schéma utilise une approche relationnelle à plat via des `ParentId` pour simplifier le parsing et l'itération des moteurs de déploiement.

## Vue d'ensemble du Schéma (Root)

L'objet racine JSON contient la version du schéma et 5 collections principales contenant les objets à déployer.

```json
{
  "SchemaVersion": "2.0",
  "Folders": [],
  "Publications": [],
  "Links": [],
  "InternalLinks": [],
  "Files": []
}
```

---

## 1. La collection `Folders`

C'est la seule collection qui reste **hiérarchique** (imbriquée). Les dossiers contiennent d'autres dossiers dans leur propriété `Folders`.
Chaque noeud défini ici dicte la structure physique de la bibliothèque SharePoint.

```json
{
  "Type": "Folder",
  "Id": "9ba5db78-2df5-40d4-ab12-70e82aaf6ba9",
  "Name": "Dossier 1er niveau",
  "RelativePath": "/Dossier 1er niveau",
  "Permissions": [
    {
      "Email": "utilisateur@domaine.com",
      "Level": "Read"
    }
  ],
  "Tags": [
    {
      "Name": "Statut",
      "Value": "Actif",
      "IsDynamic": false,
      "SourceForm": null,
      "SourceVar": null
    }
  ],
  "Folders": [
    {
       // Sous-dossiers exacts suivant le même modèle...
    }
  ]
}
```

---

## 2. Collections à plat (Contenu)

Toutes les autres collections (`Publications`, `Links`, `InternalLinks`, `Files`) sont stockées à la racine du JSON pour simplifier le travail du script de déploiement (pas besoin de récursion lourde pour chercher les fichiers).

**Lien parent-enfant :**
Chaque élément de contenu possède une propriété `ParentId` définissant le Guid du `Folder` auquel il appartient.

### 2.1 Collection `Publications`

Lien intelligent (sous forme de fichier `.url`) redirigeant vers une autre bibliothèque ou un autre site.

```json
{
  "Type": "Publication",
  "Id": "b5b351db-1127-473b-85c9-e54b65fdfe01",
  "ParentId": "9ba5db78-2df5-40d4-ab12-70e82aaf6ba9",
  "Name": "Vers Site...",
  "TargetSiteMode": "Url", 
  // "Auto" (=Site de déploiement courant) ou "Url" (=Autre Site)
  "TargetSiteUrl": "https://vosgelis365.sharepoint.com/sites/DP",
  "TargetFolderPath": "/Shared Documents/PUBLICS",
  "RelativePath": "https://vosgelis365.sharepoint.com/sites/DP/Shared Documents/PUBLICS/{FormFolderName}/Vers Site....url",
  "UseFormName": true,
  // Si true, le sous-dossier dynamique `{FormFolderName}` est ajouté au chemin
  "UseFormMetadata": true,
  // Si true, le dossier distant hérite des métadonnées du formulaire courant
  "Permissions": [],
  "Tags": []
}
```
*Note sur RelativePath* : Représente ici l'URL **absolue finalisée** vers laquelle pointera le raccourci si la cible est externe. L'outil éditeur nettoie automatiquement les URLs copiées/collées (`/:f:/r/` ou `AllItems.aspx?id=...`).

### 2.2 Collection `Links`

Lien hypertexte classique (Externe) générant un fichier `.url` dans le répertoire parent.

```json
{
  "Type": "Link",
  "Id": "647274f9-d804-477d-94a7-20e865876c0a",
  "ParentId": "9ba5db78-2df5-40d4-ab12-70e82aaf6ba9",
  "Name": "Nouveau Lien",
  "RelativePath": "/Dossier 1er niveau/Nouveau Lien.url",
  "Url": "https://pnp.github.io/",
  "Tags": []
}
```

### 2.3 Collection `InternalLinks`

Raccourci de navigation pour rebondir d'un sous-dossier à un autre au sein du même modèle de déploiement.

```json
{
  "Type": "InternalLink",
  "Id": "341c5de2-99ab-4411-bdv3-12f86587ab09",
  "ParentId": "9ba5db78-2df5-40d4-ab12-70e82aaf6ba9",
  "TargetNodeId": "9f69fcbc-4455-4e8f-9430-4174856de8b0",
  // Pointeur d'entité vers un dossier de l'arbre
  "Name": "Raccourci vers Sous Dossier",
  "RelativePath": "/Dossier 1er niveau/Raccourci vers Sous Dossier.url",
  "Tags": []
}
```

### 2.4 Collection `Files`

Fichier physique à télécharger depuis une source pour l'ajouter au dossier.

```json
{
  "Type": "File",
  "Id": "bc7274f9-1234-44aa-11c7-20e8658734x9",
  "ParentId": "9ba5db78-2df5-40d4-ab12-70e82aaf6ba9",
  "Name": "Template.docx",
  "SourceUrl": "https://vosgelis365.sharepoint.com/sites/Templates/Template.docx",
  "RelativePath": "/Dossier 1er niveau/Template.docx",
  "Tags": []
}
```

---

## Modèle de conception pour le moteur de déploiement (Étape B)

L'avantage de JSON Flat v2.0 est que les futurs moteurs de la `ToolBox` (`New-AppSPStructure.ps1`) ou de Réparation (`Repair-AppSPStructure`) n'ont plus à naviguer la hiérarchie pour trouver les objets. 

**Logique algorithmique attendue pour le parser :**
1. **Passe 1 : Folders**
   - Itérer récursivement `json.Folders`.
   - Créer chaque dossier cible (`Resolve-PnPFolder`).
   - Mettre en correspondance en mémoire Dictionary (Dictionnaire hash map) la relation `[Id] => [Url Absolue Créée sur SharePoint]`.
2. **Passe 2 : Publications, Links, InternalLinks, Files**
   - Itérer simplement la liste racine (`json.Publications`, `json.Links`, etc.).
   - Utiliser leur `ParentId` pour retrouver l'URL SharePoint du dossier conteneur dans le dictionnaire de la Passe 1.
   - Créer le fichier (`.url` ou physique) dans le dossier Parent ciblé.
   - Idem pour résoudre les `TargetNodeId` des InternalLinks.
