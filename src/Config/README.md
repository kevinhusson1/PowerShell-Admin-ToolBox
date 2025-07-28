# Gestion de la Configuration

Ce dossier contient le modèle de configuration (`settings.template.json`) pour la PowerShell Admin ToolBox.

## Fonctionnement

Au premier lancement, l'application va automatiquement copier ce template vers un emplacement spécifique à votre profil utilisateur :
`%APPDATA%\PSToolBox\settings.user.json`

C'est ce fichier **`settings.user.json`** que vous devez modifier pour adapter l'application à votre environnement.

**Ce fichier n'est jamais synchronisé avec Git, garantissant que vos informations sensibles restent locales.**