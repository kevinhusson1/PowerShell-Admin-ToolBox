# Guide du Développeur - Script Tools Box v3.0

Ce guide est destiné aux développeurs souhaitant contribuer au projet ou créer de nouveaux scripts.

---

## 1. Architecture Logicielle
L'application est découpée en modules indépendants situés dans `/Modules`.

### Les Modules Clés
*   **Core** : Configuration globale, chargement des paramètres.
*   **Database** : Abstraction de la couche SQLite. **Ne jamais attaquer SQLite directement**, utilisez toujours les fonctions `Set-App...` ou `Get-App...`.
*   **Azure** : Gestion de l'identité (MSAL/Graph) et du cache de token partagé.
*   **UI** : Composants graphiques et moteur de chargement XAML.
*   **LauncherUI** : Logique spécifique au lanceur (Dashboard, Gouvernance).
*   **Logging** : Gestion centralisée des logs.

---

## 2. Création d'un Nouveau Script

### A. Le "Golden Master"
Tout nouveau script doit être créé à partir du modèle : `Scripts/Designer/DefaultUI`.
1.  **Copier** le dossier `DefaultUI`.
2.  **Renommer** le dossier et les fichiers (`.ps1`, `.xaml`).
3.  **Modifier** le `manifest.json` (Nouvel ID unique requis).

### B. Standards de Code (2025+)
L'audit de sécurité V3 impose de nouvelles règles stricts.

> [!IMPORTANT]
> **Règle n°1 : Pas de Secrets en Clair**
> Ne stockez JAMAIS de mots de passe, clés d'API ou secrets dans le code ou les fichiers JSON.
> Utilisez `Get-ADServiceCredential` ou l'authentification déléguée Azure.

> [!TIP]
> **Adoptez les Classes PowerShell**
> Préférez les `class` aux `PSCustomObject` pour vos modèles de données internes.
>
> ```powershell
> class UserReport {
>     [string]$UPN
>     [datetime]$LastLogin
>     
>     UserReport([string]$u) { $this.UPN = $u }
> }
> ```

### C. Gestion de l'Identité
Le script ne doit pas gérer l'authentification lui-même. Il reçoit sa session du Launcher.

```powershell
# Dans le bloc param() de votre script
param(
    [string]$AuthUPN,
    [string]$TenantId,
    [string]$ClientId,
    [string]$LauncherPID
)

# Récupération de la session (Single Sign-On)
$userIdentity = Connect-AppChildSession -AuthUPN $AuthUPN -TenantId $TenantId -ClientId $ClientId
```

---

## 3. Traduction (i18n)
L'application est multilingue (FR/EN).
*   Chaque dossier de script contient un sous-dossier `Localization`.
*   Les fichiers JSON (`fr-FR.json`) contiennent les clés de texte.
*   Dans le XAML, utilisez les ancres : `##loc:monscript.ma_cle##`.

---

## 4. Tests
Avant de soumettre votre script :
1.  Validez le code avec **PSScriptAnalyzer**.
2.  Testez le redimensionnement de la fenêtre WPF.
3.  Vérifiez que le script se ferme proprement (libération du verrou BDD).