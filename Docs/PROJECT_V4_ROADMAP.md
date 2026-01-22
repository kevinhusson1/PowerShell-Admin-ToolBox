# ROADMAP D'EXÉCUTION : MIGRATION V4 HYBRIDE (C# HOST) (Projet Phoenix)

**Responsable** : Antigravity
**Durée Estimée** : 14 Semaines
**Approche** : Greenfield (Nouveau projet C# à côté du code legacy)

---

## PHASETTE 0 : INITIALISATION DE L'ENVIRONNEMENT (Semaine 1)
*   [ ] **Setup .NET** : Initialisation de la solution `ScriptToolBox.sln` (.NET 8 WPF).
*   [ ] **Structure** :
    ```
    /Src
      /STB.Host (WPF App)
      /STB.Core (Library Logic)
      /STB.Interop (PowerShell Bridge)
    /Scripts (Legacy & V4)
    ```
*   [ ] **Dépendances** : Nuget Restore (`Microsoft.PowerShell.SDK`, `Microsoft.Identity.Client`, `EntityFrameworkCore`).

## PHASE 1 : LE MOTEUR (ENGINE) (Semaines 2-5)
*   **Objectif** : Un exécutable capable de lancer un script PowerShell sans fenêtre visible.
*   **S2 - PowerShell Service** :
    *   Implémentation `PowerShellEngine` : Classe C# qui instancie `RunspacePool`.
    *   Gestion des Streams (Error, Warning, Information) -> Redirection vers Events C#.
*   **S3 - Authentication Service** :
    *   Intégration MSAL.NET.
    *   Implémentation du "Silent Token Acquisition" au démarrage de l'app.
*   **S4 - Data Service** :
    *   Setup EF Core SQLite.
    *   Migration des données `database.sqlite` vers le nouveau modèle.
*   **S5 - The Bridge** :
    *   Création de l'objet `$HostContext` à injecter dans PowerShell.
    *   Exposition de méthodes : `Log()`, `SetProgress()`, `GetConfig()`.

## PHASE 2 : L'INTERFACE (SHELL) (Semaines 6-8)
*   **S6 - Main Window** :
    *   Layout "ModernWPF" (Hamburger Menu, TitleBar).
    *   Navigation Service.
*   **S7 - Features UI** :
    *   Console Output Viewer (Log stream temps réel).
    *   Settings Page (Configuration de l'app).
*   **S8 - Dashboard** :
    *   Affichage des "Tuiles" (Outils disponibles) depuis le JSON/DB.

## PHASE 3 : MIGRATION DES SCRIPTS (Semaines 9-11)
*   **S9 - Création du Template V4** :
    *   Définition de la structure standard d'un script "Headless".
*   **S10 - Pilote 1 (ReadOnly)** : Migration `Get-ADUserReport`.
    *   Suppression GUI XAML.
    *   Remplacement `Write-Host` par `$HostContext.Log()`.
*   **S11 - Pilote 2 (Interactive)** : Migration `SharePointBuilder`.
    *   Le script renvoie une définition de formulaire JSON.
    *   Le Host génère le formulaire WPF à la volée.

## PHASE 4 : INDUSTRIALISATION (Semaines 12-14)
*   [ ] **Packaging** : Création de l'installeur MSIX ou Setup.exe.
*   [ ] **Auto-Update** : Implémentation via GitHub Releases ou Azure Blob.
*   [ ] **Documentation** : Guide développeur "Comment créer un plugin V4".

---

## RISQUES SPÉCIFIQUES HYBRIDE

1.  **Compatibilité Modules** : Certains modules PS (ex: SharePointPnPPowerShell) ont des dépendances .NET qui peuvent entrer en conflit avec celles du Host (.NET 6 vs .NET Framework, ou versions de DLLs).
    *   *Mitigation* : Tester le chargement des modules clés dans un process isolé (ALC - AssemblyLoadContext) si nécessaire.
2.  **Courbe d'apprentissage** : Nécessite des compétences C#/WPF pour maintenir le Host.
    *   *Mitigation* : Le Host doit être très stable ("Code it once") pour que les équipes Ops n'aient jamais à le toucher.
