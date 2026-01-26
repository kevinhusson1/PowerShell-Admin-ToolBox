# Annuaire Utilisateurs Microsoft Graph

Ce script fournit une interface graphique moderne pour consulter et exporter l'annuaire d'entreprise via Microsoft Graph. Il est conçu pour être rapide, réactif et facile à utiliser.

## Fonctionnalités Clés

-   **Chargement Asynchrone** ⚡ : L'interface reste fluide pendant la récupération des données grâce à l'utilisation de Jobs d'arrière-plan.
-   **Filtres Dynamiques** 🔍 : Filtrez instantanément par Poste, Service ou Recherche textuelle (Nom, Email, Téléphonie).
-   **Panneau de Détails Interactif** ℹ️ :
    -   Consultation rapide des informations détaillées (Manager, ID Objet, Localisation).
    -   **Actions Rapides** : Chat Teams, Envoi de Mail, Copie d'adresse.
-   **Export Avancé** 💾 :
    -   Sélection personnalisée des colonnes à exporter.
    -   Formats supportés : **CSV** (Compatible Excel), **HTML** (Rapport Web), **JSON** (Données brutes).
    -   Encodage UTF-8 avec BOM pour une compatibilité maximale.

## Prérequis

-   PowerShell 5.1 ou PowerShell 7+ (Recommandé).
-   Modules : `ThreadJob` (inclus/requis), `Azure`, `Core`, `UI`.
-   Authentification :
    -   Certificat (Service Principal) configuré dans `GlobalConfig.json` (Recommandé).
    -   Ou contexte utilisateur interactif (Limité selon droits).

## Structure du Script

-   `ListUserGraph.ps1` : Point d'entrée principal.
-   `ListUserGraph.xaml` : Définition de l'interface graphique.
-   `Functions/` :
    -   `Initialize-ListUserUI.ps1` : Logique UI, Filtres et Événements.
    -   `Show-ExportOptionsDialog.ps1` : Fenêtre de dialogue pour l'export.
    -   `Export-UserDirectoryData.ps1` : Moteur d'exportation.
-   `Localization/` : Fichiers de traduction JSON (fr-FR par défaut).

## Utilisation

Lancer simplement le script depuis le Launcher ou via PowerShell :

```powershell
.\ListUserGraph.ps1
```
