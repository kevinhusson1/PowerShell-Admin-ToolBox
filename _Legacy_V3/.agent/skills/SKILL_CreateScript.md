---
name: create_toolbox_script
description: Crée un nouveau script (plugin) pour la PowerShell Admin ToolBox en suivant l'architecture standard.
---

# Création d'un Nouveau Script (Plugin)

Cette procédure permet de créer un nouveau module fonctionnel (Script) qui sera automatiquement détecté par le Launcher.

## Pré-requis
*   Avoir accès au dossier `Scripts/`.
*   Connaître le nom technique (ID) et le nom d'affichage du script.

## Étapes

1.  **Duplication du Template**
    *   Copier le dossier `Scripts/Designer/DefaultUI`.
    *   Coller dans la catégorie appropriée (ex: `Scripts/Management/` ou `Scripts/SharePoint/`).
    *   Renommer le dossier avec le nom PascalCase du script (ex: `UserAudit`).

2.  **Configuration du Manifeste**
    *   Ouvrir `manifest.json` dans le nouveau dossier.
    *   Générer un nouvel `id` unique.
    *   Mettre à jour `scriptFile` (ex: `UserAudit.ps1`).
    *   Mettre à jour `name` et `description` (clés de traduction).

3.  **Renommage des Fichiers**
    *   Renommer `DefaultUI.ps1` -> `[NomDuScript].ps1`.
    *   Renommer `DefaultUI.xaml` -> `[NomDuScript].xaml`.

4.  **Configuration de la Localization**
    *   Ouvrir `Localization/fr-FR/DefaultUI.json`.
    *   Renommer le fichier si nécessaire (optionnel, le dossier est scanné).
    *   Ajouter les clés définies dans le manifeste.

5.  **Ajustement du Code (PS1)**
    *   Ouvrir le `.ps1`.
    *   Mettre à jour le chargement du XAML : `$xamlPath = Join-Path $PSScriptRoot '[NomDuScript].xaml'`.
    *   Adapter le titre de la fenêtre.

## Exemple de Manifeste
```json
{
    "id": "User-Audit-Tool",
    "scriptFile": "UserAudit.ps1",
    "name": "scripts.useraudit.name",
    "description": "scripts.useraudit.desc",
    "version": "1.0.0",
    "category": "Audit",
    "icon": { 
        "type": "png", 
        "value": "search.png" 
    }
}
```
