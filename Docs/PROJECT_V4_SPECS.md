# CAHIER DES CHARGES TECHNIQUE : V4 HYBRIDE (ENTERPRISE HOST)

**Version** : 2.0 (Hybrid Vision)
**Architecture** : .NET 8 Host + PowerShell 7.4 Runspaces
**Branch** : `develop-v4`

---

## 1. VISION TECHNIQUE
L'application **Script Tools Box V4** n'est plus un script PowerShell. C'est une application native Windows (.NET 8) qui *héberge* un moteur d'automatisation PowerShell.

### 1.1 Composants Majeurs
1.  **Le Host (ToolBox.exe)** : Application C# WPF (Modern UI). Responsable de l'affichage, des threads, de l'authentification et de la sécurité.
2.  **Le Bridge (STB.Interop)** : Couche de communication qui permet aux scripts PowerShell d'envoyer des commandes au Host (ex: `Show-Notification`, `Update-Progress`).
3.  **Les Workers (Scripts .ps1)** : Fichiers PowerShell contenant uniquement la logique métier, exécutés dans des Runspaces isolés gérés par le Host.

---

## 2. STACK TECHNOLOGIQUE

| Composant     | Technologie              | Justification                                                           |
| :------------ | :----------------------- | :---------------------------------------------------------------------- |
| **GUI Shell** | **C# / WPF (.NET 8)**    | Performance native, multithreading réel, accès API Win32.               |
| **Style**     | **ModernWPF UI Library** | Look & Feel Windows 11 natif (Dark/Light mode).                         |
| **Moteur PS** | **PowerShell SDK 7.4**   | `System.Management.Automation` pour exécuter les scripts.               |
| **Database**  | **SQLite (EF Core)**     | Accès typé et performant via Entity Framework Core.                     |
| **Auth**      | **MSAL.NET**             | Bibliothèque native Microsoft Identity (plus robuste que le module PS). |
| **Injection** | **Dependency Injection** | Architecture propre testable (MVVM).                                    |

---

## 3. SPÉCIFICATIONS FONCTIONNELLES DU HOST

### 3.1 Gestion des Runspaces (Le "Pool")
*   Le Host maintient un pool de Runspaces PowerShell chauds.
*   **Isolation** : Chaque script tourne dans son propre Runspace (pas de pollution de variables).
*   ** Shared State** : Le Host injecte des objets "Singleton" dans chaque Runspace au démarrage :
    *   `$HostContext` : API de contrôle de l'application.
    *   `$AuthToken` : Token Graph valide (rafraîchi par le Host).

### 3.2 Interface Utilisateur (Shell)
*   **Navigation** : Menu latéral pliable (Hamburger menu).
*   **Onglets** : Possibilité d'ouvrir plusieurs outils en parallèle (Tabbed Interface).
*   **Terminal Intégré** : Une vue console pour voir les sorties `Write-Host` / `Write-Error` du script en temps réel.

### 3.3 Système de Configuration
*   **Settings Provider** : Le Host lit `appsettings.json` et `database.sqlite` au démarrage.
*   **Config Injection** : Si un script a besoin de config, il appelle `$HostContext.GetSetting("Key")`. Fini les lectures XML/JSON dans le script.

---

## 4. CONTRAINTES DE MIGRATION

### 4.1 "De-UI-fication" des Scripts
Les scripts existants contiennent 50% de code UI (XAML, événements).
*   **Règle** : UN SCRIPT V4 NE DOIT PAS AVOIR D'UI.
*   **Transformation** :
    *   Les paramètres d'entrée deviennent des paramètres de script (`param(...)`).
    *   Les sorties deviennent des objets (`Write-Output`).
    *   Les interactions (Confirmation, Choix) passent par le Bridge (`$HostContext.PromptUser(...)`).

### 4.2 Compatibilité
*   Le Host doit être capable de charger les Modules PowerShell existants du dossier `Modules/`.
*   Les scripts doivent être adaptés pour ne plus gérer l'authentification eux-mêmes.
