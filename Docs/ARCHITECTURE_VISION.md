# VISION ARCHITECTURALE : "BLUE SKY" V4
## Vers une Console d'Administration Unifiée

### 1. Le Constat de l'Expert
Nous sommes à la croisée des chemins.
*   **L'approche actuelle (V2/V3)** force PowerShell à agir comme un gestionnaire de fenêtres et un chef d'orchestre de processus. C'est contre-nature. PowerShell est un langage de *scripting* magnifique, mais un *runtime d'application* médiocre (lent au démarrage, gourmand en RAM, mono-threadé).
*   **La Roadmap V4 actuelle** propose de "mitiger" ces défauts (Named Pipes pour contourner les lenteurs, Process isolation pour contourner les crashs). C'est une solution d'ingénierie robuste, mais elle reste une "réparation" des limitations inhérentes au langage.

### 2. La Recommandation "Greenfield" (Page Blanche)
Si nous avons le choix des armes pour construire la **PowerShell Admin ToolBox ultime**, ma recommandation formelle est d'abandonner le "Tout-PowerShell" pour une **Architecture Hybride**.

**Le Concept :**
> *"Ne construisez pas votre maison en PowerShell. Construisez votre maison en béton (C#), et meublez-la avec du PowerShell."*

Nous devons inverser le paradigme :
*   **Avant** : Un script PowerShell lance une fenêtre qui lance d'autres scripts.
*   **Cible** : Une application .NET native (C#) qui héberge un moteur PowerShell interne.

### 3. L'Architecture Cible : "The .NET Host Application"

#### A. Le Conteneur (C# / .NET 8 / WPF ou WinUI)
C'est un exécutable compilé (`ToolBox.exe`).
*   **Rôle** : Gérer l'affichage, l'authentification (MSAL), les threads, et la mémoire.
*   **Avantages** :
    *   **Démarrage instantané** (< 500ms).
    *   **Multi-Threading Réel** : L'interface ne gèle *jamais*, car le thread UI est 100% découplé de l'exécution.
    *   **Sécurité** : Le code du cœur est compilé, signé et plus difficile à altérer.

#### B. Le Moteur Scripting (System.Management.Automation)
Au lieu de lancer des processus `pwsh.exe` lourds (50Mo+ RAM chacun), l'application C# instancie des **Runspaces PowerShell**.
*   **Légèreté** : Un Runspace coûte quelques Mo de RAM. On peut en avoir 50 ouverts en parallèle.
*   **Vitesse** : Pas de chargement de profil, pas de démarrage de process. L'exécution est immédiate.
*   **Contexte Partagé Contrôlé** : L'app C# peut "injecter" des variables prêtes à l'emploi dans le script (ex: `$Global:GraphClient` déjà authentifié).

#### C. Les Outils (Vos Scripts PowerShell)
C'est le point crucial : **La logique métier reste en PowerShell.**
Les administrateurs/contributeurs continuent d'écrire des fichiers `.ps1`. Ils n'ont pas besoin de connaître le C#.
*   L'application lit le `.ps1`.
*   Elle l'exécute dans un Runspace dédié.
*   Elle capture les sorties (Streams) pour afficher les logs et barres de progression nativement.

### 4. Comparatif Stratégique

| Critère              | Architecture V3/V4 (Pure PowerShell)      | Architecture "Blue Sky" (C# Host)         |
| :------------------- | :---------------------------------------- | :---------------------------------------- |
| **Performance UI**   | **Moyenne**. Risques de freeze élevés.    | **Excellente**. Fluidité native 60fps.    |
| **Consommation RAM** | **Lourde**. 1 Process par outil (~50Mo+). | **Optimisée**. 1 Thread par outil (~5Mo). |
| **Communication**    | **Complexe**. Pipes/Fichiers/Sockets.     | **Native**. Objets .NET en mémoire.       |
| **Dév. Core**        | Difficile (Hacks pour l'async).           | Standard (Task Parallel Library).         |
| **Dév. Outils**      | PowerShell (inchangé).                    | PowerShell (inchangé).                    |
| **Installation**     | Copie de fichiers.                        | Exécutable portable.                      |

### 5. Roadmap Technique "Revolution"

Si nous choisissons cette voie, le plan change radicalement :

1.  **Phase Core (C#)** : Développement de `ToolBox.exe` (WPF .NET 8).
    *   Implémentation du `PowerShellHost` (le gestionnaire de Runspaces).
    *   Intégration MSAL native (plus robuste qu'en script).
2.  **Phase Bridge** : Création du contrat d'interface.
    *   Comment un script.ps1 dit à l'app C# "Affiche une notification" ? (Via des cmdlets custom injectées par l'hôte, ex: `Show-AppNotification`).
3.  **Phase Migration** :
    *   Les scripts existants sont nettoyés de leur code GUI (plus de XAML dans le PS1).
    *   Ils deviennent des "Workers" purs qui renvoient des objets. L'app C# se charge de les afficher (Tableaux, Graphiques, Logs).

### 6. Conclusion
Pour une "Administration Avancée" et une expérience "Premium" (Wow effect), l'architecture **C# Host** est la seule voie professionnelle durable. Elle sépare proprement :
*   La **Plateforme** (Performance, Sécurité, UI) -> Domaine du Développeur (.NET).
*   Le **Métier** (Actions AD, Graph, Exchange) -> Domaine de l'Admin (PowerShell).

**C'est le meilleur des deux mondes.**
