# 🐞 Known Issues & Debugging Status

**Date**: 13/02/2026

Ce document recense les problèmes connus, en cours d'investigation ou récemment résolus sur le **SharePoint Renamer**.

## 🔴 Problèmes Critiques (En cours)

### 1. Affichage des Logs (RichTextBox)
*   **Symptôme** : La fenêtre de logs reste parfois vide ou les logs ne défilent pas correctement malgré l'exécution du Job.
*   **Cause Suspectée** : 
    *   Conflit entre les flux de sortie (`Write-Output`, `Write-Verbose`, `Write-AppLog`).
    *   La méthode `AppendText` peut être bloquée si le thread UI est saturé (bien que le Timer soit censé régler ça).
    *   Le formatage des objets `AppLog` vs `String` dans le `Receive-Job`.
*   **État Actuel** : 
    *   Fix appliqué (13/02) : Passage en mode "Logs Manuels" (`VerbosePreference = SilentlyContinue`, formatage manuel via `AppendText`, redirection `4>&1`). 
    *   En attente de validation définitive.

### 2. Crash au Démarrage (Résolu)
*   **Symptôme** : "Fatal Error: You cannot call a method on a null-valued expression" lors du `ShowDialog`.
*   **Cause** : Le chargement du XAML (`Import-AppXamlTemplate`) échouait silencieusement ou retournait `$null`, provoquant un crash plus loin.
*   **Correctif** : Ajout d'une vérification stricte `if (-not $window) { throw ... }` immédiate.

## 🟠 Limitations Techniques

### 1. Performance du Deep Update
*   **Description** : Sur des dossiers contenant des milliers de fichiers, l'étape "Scan et réparation des liens" (`Repair-AppSPLinks`) peut être longue.
*   **Recommandation** : L'outil est conçu pour des dossiers de projet/chantier (taille modérée). Pour des migrations massives, préférer un script serveur dédié sans UI.

### 2. Verrouillage Fichier
*   **Description** : Si un fichier est ouvert par un utilisateur pendant le renommage, l'opération PnP peut échouer.
*   **Comportement** : Le script s'arrête et log une erreur. Pas de "Retry" automatique pour l'instant.

## 🧪 Tests à effectuer
1.  Lancer un renommage complet.
2.  Vérifier que les emojis (ℹ️, ✅, ⚠️) s'affichent bien dans la zone de texte.
3.  Vérifier que le bouton "Ouvrir destination" s'active à la fin exact du renommage (avant même la fin du Deep Update si possible, ou juste après).
