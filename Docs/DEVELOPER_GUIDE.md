# Guide du Développeur - Création d'un nouveau Script

Ce guide explique comment ajouter une nouvelle fonctionnalité à la **Script Tools Box** en utilisant le "Golden Master" (Template v2.0).

## 1. Duplication du Template

Ne partez jamais d'une page blanche.
1.  Copiez le dossier `Scripts/Designer/DefaultUI`.
2.  Collez-le dans la catégorie appropriée (ex: `Scripts/UserManagement/MonNouveauScript`).
3.  Renommez le dossier avec le nom technique de votre script.

## 2. Configuration de l'Identité (Manifeste)

Ouvrez le fichier `manifest.json` dans votre nouveau dossier.
1.  **ID (Critique) :** Changez l'ID (ex: `My-Script-v1`). Il doit être UNIQUE dans toute l'application.
    *   *C'est cet ID qui servira de clé dans la base de données SQLite.*
2.  **ScriptFile :** Renommez le fichier `.ps1` (voir étape 3) et mettez le nom ici.
3.  **Textes :** Mettez à jour les clés de traduction (`name`, `description`).
4.  **Icone :** Choisissez une icône PNG dans `Templates/Resources/Icons/PNG` et référencez-la.

## 3. Renommage des Fichiers

Dans votre dossier :
1.  Renommez `DefaultUI.ps1` en `MonNouveauScript.ps1`.
2.  Renommez `DefaultUI.xaml` en `MonNouveauScript.xaml`.

## 4. Adaptation du Code (.ps1)

Ouvrez `MonNouveauScript.ps1`.
1.  **Ligne ~100 (Chargement XAML) :** Mettez à jour le nom du fichier XAML à charger :
    ```powershell
    $window = Import-AppXamlTemplate -XamlPath (Join-Path $scriptRoot "MonNouveauScript.xaml")
    ```
2.  **Logique Métier :**
    *   Utilisez le dossier `Functions/` pour créer vos fonctions spécifiques (ex: `Functions/Process-User.ps1`).
    *   Chargez-les via "Dot-Sourcing" dans le script principal.

## 5. Gestion de l'Identité (Authentification)

Depuis la version 3.0, l'authentification est gérée via un partage sécurisé du cache de token MSAL (SSO "Zero-Trust").

### A. Paramètres Requis
Votre script doit accepter les paramètres suivants pour recevoir l'identité depuis le Launcher :
```powershell
param(
    [string]$LauncherPID,
    [string]$AuthUPN,     # Requis pour le SSO
    [string]$TenantId,
    [string]$ClientId,
    # ... autres params ...
)
```

### B. Implémentation Standard (Logique)
Utilisez la fonction **`Connect-AppChildSession`** (Module Azure) pour restaurer la session sans manipuler de secrets :
```powershell
$userIdentity = Connect-AppChildSession -AuthUPN $AuthUPN -TenantId $TenantId -ClientId $ClientId
```

### C. Interface Utilisateur (UI)
Utilisez la fonction **`Set-AppWindowIdentity`** (Module UI) pour gérer le bouton d'identité (Initials, Nom, Déconnexion) :
```powershell
# Callbacks pour le mode autonome (Test/Dev)
$OnConnect = { ... }
$OnDisconnect = { ... }

Set-AppWindowIdentity -Window $window `
                      -UserSession $userIdentity `
                      -LauncherPID $LauncherPID `
                      -OnConnect $OnConnect `
                      -OnDisconnect $OnDisconnect
```
*(Voir le script `DefaultUI.ps1` pour l'implémentation complète des callbacks.)*

## 6. Traduction (Localization)

1.  Ouvrez `Localization/fr-FR.json` dans votre dossier de script.
2.  Changez la clé racine (ex: remplacez `default_ui` par `my_script`).
3.  Ajoutez vos textes.
4.  Dans le fichier XAML, utilisez les balises `##loc:my_script.ma_cle##`.

## 7. Activation & Test

1.  Lancez le **Launcher**.
2.  Connectez-vous en tant qu'Administrateur.
3.  Allez dans l'onglet **Gestion**.
4.  Vous devriez voir votre nouveau script dans la liste (avec une pastille grise).
5.  **Activez-le** (Switch vert) et donnez-vous les droits (Cochez votre groupe).
6.  Allez dans l'onglet **Scripts** : Votre tuile doit apparaître.