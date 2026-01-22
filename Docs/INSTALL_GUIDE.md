# Guide d'Installation - Script Tools Box v3.0

Ce guide détaille les étapes pour déployer l'application **Script Tools Box** dans un nouvel environnement.
Cette version utilise une **architecture de sécurité hybride** :
1.  **Authentification Utilisateur (Graph API)** : Pour l'accès à l'interface, la gestion des droits et l'annuaire (Mode Délégué).
2.  **Authentification Application (Certificat)** : Pour les opérations lourdes d'automatisation comme SharePoint (Mode App-Only).

## 1. Prérequis Techniques

*   **Système d'exploitation :** Windows 10/11 ou Windows Server 2019+.
*   **PowerShell :** Version 7.4 ou supérieure (Core).
*   **Modules PowerShell requis :**
    *   `Microsoft.Graph`
    *   `PnP.PowerShell`
*   **Composants Windows :**
    *   Outils RSAT (Active Directory) installés pour les scripts de gestion On-Premise.
*   **Droits :** Être Administrateur Global du tenant Azure AD (pour l'initialisation).

---

## 2. Configuration Azure AD (Entra ID)

### A. Création de l'application
1.  Allez sur le [Portail Azure > App registrations](https://portal.azure.com/#view/Microsoft_AAD_IAM/ActiveDirectoryMenuBlade/~/RegisteredApps).
2.  Cliquez sur **New registration**.
3.  **Nom :** `Script Tools Box` (ou le nom de votre choix).
4.  **Supported account types :** *Accounts in this organizational directory only (Single tenant)*.
5.  **Redirect URI (Platform configuration) :**
    *   Sélectionnez **Public client/native (mobile & desktop)**.
    *   URI : `http://localhost` (Nécessaire pour l'authentification interactive MSAL).
6.  Cliquez sur **Register**.

### B. Récupération des IDs
Notez les informations suivantes (disponibles dans l'onglet *Overview*) :
*   **Application (client) ID**
*   **Directory (tenant) ID**

### C. Permissions API (Scopes)
L'application a besoin de droits mixtes (Délégués pour l'humain, Application pour le robot).

1.  Allez dans **API permissions** > **Add a permission**.

#### Permissions Déléguées (Graph API)
*Sélectionnez Microsoft Graph > Delegated permissions :*
*   `User.Read` (Connexion de base)
*   `GroupMember.Read.All` (Vérification des groupes pour le Launcher)
*   `Application.ReadWrite.All` (Auto-gouvernance)
*   `Directory.Read.All` (Lecture de l'annuaire)

#### Permissions Application (SharePoint)
*Sélectionnez SharePoint > Application permissions :*
*   `Sites.FullControl.All` (Pour le module SharePoint Builder : création de sites, dossiers, permissions)

> **IMPORTANT :** Une fois les permissions ajoutées, cliquez sur le bouton **"Grant admin consent for [VotreEntreprise]"** en haut de la page.

### D. Génération et Installation du Certificat
L'application nécessite un certificat pour les opérations automatisées.

**1. Générer le certificat (Sur votre poste)**
Ouvrez une console PowerShell et exécutez ce script pour créer un certificat auto-signé valide 5 ans :

```powershell
$certName = "Toolbox-AppOnly-Cert"
$exportPath = "$HOME\Desktop\ToolboxCert"
New-Item -ItemType Directory -Force -Path $exportPath | Out-Null

# Création dans le magasin Personnel Utilisateur
$cert = New-SelfSignedCertificate `
    -Subject "CN=$certName" `
    -KeySpec KeyExchange `
    -Provider "Microsoft RSA SChannel Cryptographic Provider" `
    -KeyExportPolicy NonExportable `
    -HashAlgorithm SHA256 `
    -KeyLength 2048 `
    -NotAfter (Get-Date).AddYears(5) `
    -CertStoreLocation "Cert:\CurrentUser\My"

# Export Clé Publique (.cer) pour Azure
Export-Certificate -Cert $cert -FilePath (Join-Path $exportPath "$certName.cer") | Out-Null

# Affichage de l'empreinte (Thumbprint) à copier
Write-Host "Empreinte à copier dans l'application : $($cert.Thumbprint)" -ForegroundColor Yellow
Set-Clipboard -Value $cert.Thumbprint
Write-Host "(Copié dans le presse-papier)" -ForegroundColor Gray
```

**2. Uploader la clé publique sur Azure**
1.  Dans votre App Registration sur le portail Azure, allez dans **Certificates & secrets**.
2.  Onglet **Certificates** > Cliquez sur **Upload certificate**.
3.  Sélectionnez le fichier `.cer` généré sur votre bureau à l'étape précédente.
4.  Cliquez sur **Add**.

---

## 3. Initialisation de l'Application (Bootstrap)

Lors du tout premier lancement, configurez l'application pour la lier à Azure.

1.  Lancez `Launcher.ps1` avec PowerShell 7.
2.  L'application s'ouvre. Allez dans l'onglet **Paramètres**.
3.  Remplissez la section **Configuration Azure & Sécurité** :

    *   **Référentiel Global :**
        *   **Nom du Tenant :** Le nom technique (ex: `vosgelis365` sans le .onmicrosoft.com).
        *   **Tenant ID :** L'ID récupéré à l'étape 2B.
        *   **Application (Client) ID :** L'ID récupéré à l'étape 2B.

    *   **Identité Utilisateur :**
        *   **Groupe Admin :** Nom du groupe Azure AD des administrateurs (ex: `M365_APPS_SCRIPTS_ADMIN`).

    *   **Moteur d'Automatisation (Certificat) :**
        *   **Empreinte (Thumbprint) :** Collez l'empreinte générée par le script PowerShell (ex: `A1B2C3D4...`).
        *   Cliquez sur le bouton **"Tester la connexion App-Only"** pour valider que le certificat est bien reconnu et que les droits sont actifs.
    
    > [!NOTE]
    > **Sécurité Active Directory** : Pour des raisons de sécurité, le mot de passe du compte de service AD n'est **jamais sauvegardé** sur le disque. Il vous sera demandé de le saisir (si nécessaire) lors des opérations sensibles nécessitant une élévation de privilèges On-Premise, ou il devra être re-saisi dans l'onglet Paramètres à chaque redémarrage de l'application si vous souhaitez utiliser les fonctions de test.

4.  Cliquez sur **Enregistrer les modifications** en bas de page.
5.  Redémarrez l'application.

## 4. Validation Finale

1.  Relancez `Launcher.ps1`.
2.  Cliquez sur le bouton **"Se connecter"** (en haut à droite).
    *   L'authentification Graph doit être fluide (SSO).
3.  Si vous êtes membre du groupe Admin, les onglets **Gouvernance** et **Gestion** apparaissent.
4.  Lancez le module **SharePoint Builder**.
    *   Vérifiez que le statut "SharePoint (PnP)" passe au vert ("PRÊT") automatiquement grâce au certificat.