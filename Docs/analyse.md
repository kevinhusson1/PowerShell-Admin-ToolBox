# Rapport d'Expertise Technique et Doctrine d'Ingénierie pour Script Tools Box V3.0

## 1. Analyse Architecturale Stratégique et Alignement des Objectifs

Le projet "Script Tools Box V3.0" représente une évolution sophistiquée de l'automatisation d'entreprise basée sur PowerShell, transcendant le simple scripting pour entrer dans le domaine du développement d'applications modulaires de classe "desktop". L'architecture centrale—un modèle Hub & Spoke (Moyeu et Rayons) gouverné par un `Launcher.ps1` central (le Noyau) et des Child Scripts satellites (les Rayons)—impose des contraintes physiques et logiques uniques qui définissent le paysage de l'optimisation.

Ce rapport fournit une analyse exhaustive des modèles architecturaux requis pour maximiser la performance, la sécurité et la maintenabilité au sein de cet écosystème complexe. Il synthétise la documentation développeur fournie avec les meilleures pratiques industrielles avancées pour PowerShell 7+, WPF (Windows Presentation Foundation), la concurrence SQLite et l'intégration de la Microsoft Authentication Library (MSAL).

L'analyse révèle que les défis d'ingénierie primaires pour la V3.0 résident dans trois domaines critiques :

1. La latence de la Communication Inter-Processus (IPC)
2. La Concurrence de Base de Données (verrouillage SQLite)
3. La Réactivité du Thread UI

Pour adresser ces défis, un ensemble rigide de "Règles Développeur" et de "Compétences Techniques" (Skills) nécessaires doit être établi. Celles-ci ne sont pas de simples suggestions mais des impératifs architecturaux pour assurer que le système passe à l'échelle sans succomber aux phénomènes d'épuisement de processus ou de gel de l'interface utilisateur, communs dans les interfaces graphiques PowerShell complexes.

### 1.1 Le Paradigme Hub & Spoke : Isolation des Processus vs Surcharge des Ressources

La décision d'utiliser une architecture "Hub & Spoke" dicte la physique fondamentale de l'application. En générant des processus indépendants pour chaque module (par exemple, gestion Active Directory, outils SharePoint), le système atteint un haut degré d'isolation des fautes. Un crash dans un module enfant ne compromet pas le Launcher, garantissant ainsi la stabilité du tableau de bord principal. Cependant, cette conception introduit une surcharge significative qui ne peut être ignorée.

Chaque "Spoke" est un processus hôte PowerShell complet (`pwsh.exe` ou `powershell.exe`). Contrairement à un thread léger au sein d'une application .NET compilée, chaque instance de script enfant nécessite sa propre empreinte mémoire (souvent 30 à 50 Mo par instance au démarrage, pouvant monter à plusieurs centaines de Mo selon les modules chargés) et un temps de démarrage non négligeable pour charger le CLR .NET et les assemblages nécessaires.

> **Implication Stratégique :**
> Cette architecture impose que les règles dérivées pour ce projet priorisent la Gestion du Cycle de Vie des Processus. Les développeurs ne peuvent pas traiter l'exécution d'un script comme une opération triviale ; ils doivent la traiter comme une allocation de ressource coûteuse. Les compétences requises impliquent de comprendre la différence fondamentale entre un Process, un Thread, et un Runspace. Il est impératif de savoir quand dévier du modèle standard `Start-Process` vers des alternatives plus légères comme les RunspacePools lorsque l'isolation totale n'est pas strictement nécessaire pour la stabilité.

De plus, la multiplication des processus crée un défi de synchronisation. Le Launcher doit savoir si un processus enfant est vivant, mort, ou "zombie" (mort mais toujours présent dans la table des sessions actives). Cela nécessite une logique de surveillance robuste qui dépasse la simple commande `Get-Process`.

### 1.2 Le Sémaphore Global : SQLite comme Moteur d'État

Le projet utilise SQLite non seulement pour le stockage de données mais aussi comme un contrôleur de concurrence (un sémaphore global) via la table `active_sessions`. C'est une décision architecturale à haut risque si elle n'est pas gérée avec une précision chirurgicale. SQLite est fondamentalement une base de données basée sur des fichiers. Bien que robuste, ses mécanismes de verrouillage (particulièrement en mode "Rollback Journal" par défaut) peuvent conduire à des erreurs `SQL_BUSY` si plusieurs processus enfants tentent d'écrire simultanément.

Dans un scénario où dix outils sont lancés simultanément par différents utilisateurs (ou même le même utilisateur sur plusieurs instances), la contention sur le fichier `.db` unique peut devenir un goulot d'étranglement majeur. Si le Launcher tente de lire la table des sessions pour vérifier les quotas (`MaxConcurrentRuns`) au moment précis où un script enfant tente de mettre à jour son statut, l'un des deux sera bloqué.

> **Implication Stratégique :**
> Les règles développeur doivent imposer une Discipline Transactionnelle stricte. Les écritures doivent être groupées, et le mode de la base de données doit impérativement basculer vers WAL (Write-Ahead Logging) pour permettre aux lecteurs et aux écrivains de coexister sans blocage mutuel. Les compétences requises impliquent une connaissance approfondie des transactions SQL, des niveaux d'isolation, et des modèles de logique de réessai ("retry logic") spécifiques aux bases de données verrouillées par fichier.

### 1.3 Le Tissu Identitaire : MSAL et Cache de Token Partagé

La sécurité dans la V3.0 repose sur un "Cache de Token Partagé". Le Launcher authentifie l'utilisateur (Interactif/SSO) et écrit le token (jeton) dans un cache sécurisé ; les processus enfants "réhydratent" ce token sans interaction utilisateur. Cela nécessite une compréhension nuancée de la Sérialisation de Token et de la Gestion des Scopes (Portées).

Le défi technique réside dans la granularité des permissions. Si un processus enfant demande une portée (permission) qui n'a pas été accordée au token initial du Launcher, la réhydratation silencieuse échouera, provoquant une erreur `MsalUiRequiredException`. De plus, la protection de ce cache sur le disque est critique pour prévenir le vol de session.

> **Implication Stratégique :**
> Les règles doivent mandater un Minimalisme des Scopes et une Récupération Défensive des Tokens. Les développeurs doivent implémenter une logique capable de gérer les signaux d'erreur d'authentification et de se replier gracieusement vers le Launcher si un token ne peut pas être acquis silencieusement. La sécurité ne doit pas être une réflexion après coup mais intégrée dans la signature de chaque fonction d'appel API.

## 2. Analyse Approfondie des Contraintes Techniques et Optimisations

Cette section détaille les mécanismes internes nécessaires pour soutenir les règles et compétences qui seront définies plus loin. Elle explore les "pourquoi" techniques qui justifient les exigences de performance.

### 2.1 Modèle de Concurrence SQLite : Résoudre le Goulot d'Étranglement

L'utilisation de SQLite comme mécanisme de verrouillage central dans une architecture multi-processus est viable mais périlleuse. Dans le mode par défaut de SQLite (Delete Journal), une opération d'écriture verrouille l'entièreté du fichier de base de données. Si le Launcher interroge la base toutes les secondes pour nettoyer les processus morts, et que trois scripts tentent d'écrire des logs ou des mises à jour de statut, la probabilité de collision (race condition) est élevée.

#### 2.1.1 Le Problème du Verrouillage Exclusif

Lorsqu'un script enfant initie une transaction d'écriture, il acquiert un verrou EXCLUSIF. Aucun autre processus ne peut lire ou écrire tant que ce verrou est maintenu. Dans un environnement PowerShell, où le garbage collection .NET peut introduire des pauses imprévisibles, une transaction qui devrait durer 1ms peut s'étendre, bloquant tous les autres outils.

#### 2.1.2 La Solution WAL (Write-Ahead Logging)

Pour la V3.0, l'activation du mode WAL est non négociable. En mode WAL, les modifications ne sont pas écrites directement dans le fichier B-Tree principal, mais annexées à un fichier journal séparé (`.wal`).

* **Concurrence Accrue** : Les lecteurs ne bloquent pas les écrivains, et les écrivains ne bloquent pas les lecteurs. Le Launcher peut lire la table `active_sessions` pendant qu'un script enfant met à jour son statut.
* **Performance** : Les écritures sont séquentielles dans le fichier WAL, ce qui est beaucoup plus rapide sur disque que les écritures aléatoires dans le fichier DB principal.
* **Compromis** : Il faut gérer les "Checkpoints" (le moment où le fichier WAL est réintégré dans la DB principale). Si le fichier WAL devient trop gros, les lectures ralentissent. Le module "Database" devra inclure une maintenance automatique de ce checkpoint.

### 2.2 L'Interface Utilisateur : WPF dans un Monde Single-Thread

PowerShell, comme la plupart des environnements de scripting, opère par défaut sur un modèle Single Thread Apartment (STA). Cela signifie que le thread qui dessine la fenêtre (le Thread UI) est le même que celui qui exécute les commandes du script.

#### 2.2.1 Le Phénomène de Gel (Freezing)

Les snippets de recherche soulignent un point de douleur majeur : *"Everything is done on a single thread with the UI"*. Si un développeur écrit un script qui exécute `Get-ADUser -Filter *` directement dans le bloc d'événement d'un clic de bouton, l'interface graphique gèle complètement. Windows marquera l'application comme "Ne répond pas" (ghosting de la fenêtre), détruisant l'expérience utilisateur.

#### 2.2.2 Le Modèle Dispatcher et l'Asynchronisme

Pour contrer cela, la V3.0 doit adopter un modèle asynchrone strict. Cependant, PowerShell ne possède pas les mots-clés `async` et `await` de C#. Les développeurs doivent simuler ce comportement en utilisant des Runspaces ou des Jobs pour le travail lourd, et utiliser l'objet `Dispatcher` WPF pour ramener les résultats vers le thread UI.

> **Règle Technique :** Seul le thread qui a créé les objets UI (le thread principal) a le droit de les modifier. Tenter de mettre à jour une barre de progression depuis un thread secondaire (Runspace) sans passer par le Dispatcher provoquera une `InvalidOperationException` immédiate.

### 2.3 Sécurité Identitaire : Protection Contre le Vol de Token

Le fichier `DEVELOPER_GUIDE.md` interdit le stockage de secrets en clair. Mais stocker un token d'accès OAuth (Bearer Token) sur le disque présente des risques similaires. Si un acteur malveillant copie le fichier de cache, il peut potentiellement usurper l'identité de l'utilisateur.

#### 2.3.1 Cryptographie DPAPI

L'analyse des meilleures pratiques MSAL indique que le cache de token doit être protégé par la Data Protection API (DPAPI) de Windows. Cette API crypte les données en utilisant une clé dérivée des secrets de logon de l'utilisateur.

* **Avantage** : Le fichier crypté ne peut être décrypté que sur la même machine et par le même utilisateur Windows. Même si un administrateur copie le fichier, il est inutilisable.
* **Implémentation** : Les scripts ne doivent pas manipuler le JSON du token directement mais utiliser les méthodes de sérialisation sécurisées de MSAL (`StorageCreationPropertiesBuilder` avec `WithUnprotectFileOnWindows`).

#### 2.3.2 Vérification du Processus Parent (Anti-Spoofing)

Puisque les scripts enfants héritent de l'identité sans prompt, il existe un risque qu'un utilisateur lance un script manuellement (hors Launcher) pour contourner les contrôles de gouvernance. Pour mitiger cela, les scripts doivent vérifier leur Processus Parent. Le script doit s'assurer que son PPID (Parent Process ID) correspond à une instance légitime du Launcher signée numériquement.

## 3. Communication Inter-Processus (IPC) : Optimisation des Échanges

Dans l'architecture actuelle, le Launcher et les scripts semblent communiquer principalement via la base de données ou des paramètres de démarrage. Pour une application "desktop-class" réactive, cela est insuffisant pour le monitoring temps réel (logs, barres de progression).

### 3.1 Comparaison des Méthodes IPC

| Méthode                         | Latence            | Complexité | Pertinence V3.0                                             |
| :------------------------------ | :----------------- | :--------- | :---------------------------------------------------------- |
| **Fichier / Base de Données**   | Haute (>10-100ms)  | Faible     | Déconseillé pour le temps réel. Bon pour l'état persistant. |
| **Named Pipes (Tuyaux Nommés)** | Très Faible (<1ms) | Moyenne    | **Recommandé**. Permet le streaming de logs instantané.     |
| **TCP / HTTP Localhost**        | Moyenne            | Haute      | Exagéré. Problèmes de pare-feu et de ports.                 |
| **Paramètres CLI**              | N/A (One-way)      | Faible     | Uniquement pour l'initialisation.                           |

### 3.2 Recommandation : Named Pipes pour la Télémétrie

L'analyse suggère l'adoption des **Named Pipes** pour le canal de retour (feedback channel). Le Launcher devrait ouvrir un serveur de pipe nommé (ex: `\\.\pipe\STBox_Log_`). Chaque script enfant se connecte à ce pipe pour envoyer ses logs et mises à jour de progression.

* **Avantage Performance** : Contrairement à l'écriture dans un fichier texte que le Launcher doit surveiller (`FileWatcher`), le pipe notifie le Launcher immédiatement à l'arrivée des données. Cela réduit l'utilisation CPU du Launcher (pas de polling) et assure que l'interface utilisateur est fluide.

## 4. Règles de Développement Haute Performance (Les Mandats)

Sur la base de l'analyse ci-dessus, voici les règles impératives déduites pour tout développeur travaillant sur le projet Script Tools Box V3.0.

### Règle 1 : Le Mandat "Zéro-Gel" (Zero-Freeze UI Mandate)

* **Contexte** : L'expérience utilisateur est primordiale. Une application qui gèle est perçue comme défectueuse.
* **La Règle** : Aucune opération bloquante (I/O, Réseau, Calcul lourd) n'est permise sur le thread de l'interface utilisateur. Toutes les opérations métier doivent être déléguées à des tâches d'arrière-plan.
* **Directive d'Implémentation** :
  * **Pattern Dispatcher** : L'utilisation du Dispatcher est obligatoire pour toute mise à jour de l'UI depuis un thread secondaire. Les développeurs doivent encapsuler les mises à jour visuelles dans des blocs Dispatcher.
  * **Invoke.Runspace Offloading** : Au lieu de `Start-Job` (qui crée un processus lourd), privilégier `::Create()` ou `RunspaceFactory` pour exécuter des tâches en arrière-plan au sein du même processus lorsque l'isolation totale n'est pas requise.
  * **Feedback Visuel** : Chaque action asynchrone doit immédiatement déclencher un indicateur visuel (spinner, barre de progression indéterminée) avant même que le travail ne commence.

### Règle 2 : Encapsulation Stricte de la Couche de Données (DAL)

* **Contexte** : La concurrence SQLite est le point critique de fragilité.
* **La Règle** : L'invocation directe des binaires SQLite ou de requêtes SQL brutes dans les modules fonctionnels est interdite. Toute interaction doit passer par les fonctions mandataires `Set-App...` et `Get-App...`.
* **Directive d'Implémentation** :
  * **Abstraction** : Les scripts ne doivent jamais charger `System.Data.SQLite` directement. Ils doivent importer le module `Database`.
  * **Logique de Réessai (Retry Logic)** : Les fonctions DAL doivent implémenter une logique de réessai intelligente pour les exceptions `SQL_BUSY`. Un algorithme de "backoff exponentiel" (attendre 10ms, puis 20ms, puis 40ms) est requis pour absorber les pics de charge.
  * **Mode WAL** : Le développeur responsable du module Core doit s'assurer que la base est initialisée avec `PRAGMA journal_mode=WAL`.

### Règle 3 : Le Pattern d'Identité "Stateless Spoke"

* **Contexte** : Les scripts enfants sont éphémères et ne doivent pas gérer le cycle de vie de l'identité.
* **La Règle** : Les scripts enfants ne doivent jamais initier d'authentification interactive. Ils doivent accepter les paramètres `$AuthUPN`, `$TenantId`, et `$ClientId` et utiliser `Connect-AppChildSession` pour réhydrater la session silencieusement.
* **Directive d'Implémentation** :
  * **Réhydratation de Token** : Les scripts doivent s'appuyer sur le cache MSAL situé dans `Cert:\CurrentUser` ou le système de fichiers sécurisé DPAPI. Ils ne doivent jamais demander de mot de passe.
  * **Vérification des Scopes** : Avant d'exécuter un appel Graph API, le script doit vérifier que le token réhydraté contient les scopes nécessaires (ex: `User.ReadWrite`). Si ce n'est pas le cas, le script doit se terminer avec un code d'erreur spécifique instruisant le Launcher de demander un consentement élevé.

### Règle 4 : IPC Haute Performance via Named Pipes

* **Contexte** : Le monitoring via base de données est trop lent et coûteux en I/O.
* **La Règle** : Minimiser le transfert d'objets sérialisés via fichiers. Pour la télémétrie temps réel (logs), utiliser des Named Pipes.
* **Directive d'Implémentation** :
  * **Sélection du Protocole** : Pour les statuts simples ("Job Started"), la base de données suffit. Pour le streaming de logs, un `System.IO.Pipes.NamedPipeClientStream` doit être utilisé pour envoyer les données au Launcher.
  * **Sérialisation** : Utiliser `ConvertTo-Json -Compress` pour passer des objets légers dans le pipe. Éviter de passer des tableaux massifs d'objets complexes (comme des utilisateurs AD complets) ; passer plutôt des IDs.

### Règle 5 : Isolation Modulaire et Injection de Dépendances

* **Contexte** : L'architecture modulaire décrite dans le guide doit être préservée.
* **La Règle** : Aucune dépendance croisée entre modules fonctionnels pairs (Peer Modules). Un module "SharePoint" peut dépendre de "Core" ou "Database", mais pas de "Exchange".
* **Directive d'Implémentation** :
  * **Manifeste** : Chaque module doit avoir un manifeste `.psd1` déclarant ses dépendances précises.
  * **Chargement Dynamique** : Le Launcher doit charger les modules dynamiquement basé sur la configuration, et non via des chemins codés en dur. Cela réduit l'empreinte mémoire.

## 5. Compétences Requises (Le Toolkit Technique)

Pour adhérer aux règles ci-dessus, les développeurs doivent posséder des compétences techniques spécifiques et avancées, dépassant le scripting standard.

### Compétence 1 : Interopérabilité .NET Avancée & Réflexion

* **Définition** : La capacité d'utiliser les classes du framework .NET directement dans PowerShell, contournant les limitations des cmdlets.
* **Application dans le Projet** :
  * **WPF/XAML** : Utilisation de `::Load()` et manipulation programmatique des objets WPF (`Window`, `Button`, `Grid`).
  * **Threading** : Création manuelle d'objets ou pour gérer la concurrence interne.
  * **P/Invoke** : Appel aux APIs Win32 (ex: `user32.dll` pour la gestion des fenêtres) pour gérer la parenté des fenêtres (faire apparaître la fenêtre d'un script enfant "dans" le tableau de bord du Launcher).

### Compétence 2 : Gestion Asynchrone des Événements

* **Définition** : Programmation réactive qui ne suit pas un flux linéaire haut-bas mais répond aux événements.
* **Application dans le Projet** :
  * **Abonnement aux Événements** : Utilisation de `Register-ObjectEvent` pour les interactions UI.
  * **Dispatcher** : Comprendre la différence cruciale entre `Dispatcher.Invoke` (synchrone/bloquant) et `Dispatcher.BeginInvoke` (asynchrone) pour mettre à jour l'interface sans crash.
  * **Timers** : Implémentation de `System.Windows.Threading.DispatcherTimer` pour les vérifications de nettoyage "Self-Healing" mentionnées dans l'architecture.

### Compétence 3 : Optimisation SQLite & Tuning

* **Définition** : Expertise dans la configuration de SQLite pour les environnements à haute concurrence.
* **Application dans le Projet** :
  * **Mode WAL** : Configuration de `PRAGMA journal_mode=WAL` pour permettre lecteurs et écrivains simultanés.
  * **Busy Timeout** : Configuration de `PRAGMA busy_timeout=3000` pour laisser le moteur gérer les réessais automatiquement.
  * **Indexation** : Création d'index efficaces sur la table `active_sessions` (RunID, PID) pour assurer que les vérifications fréquentes du Launcher sont en O(1) ou O(log n).

### Compétence 4 : Gestion Identitaire Sécurisée (MSAL/OAuth)

* **Définition** : Compréhension profonde des flux d'authentification modernes (OAuth 2.0, OpenID Connect).
* **Application dans le Projet** :
  * **Protection de Token** : Savoir stocker les tokens de manière sécurisée avec DPAPI.
  * **Manipulation de Claims** : Parser les JWTs (JSON Web Tokens) pour extraire les temps d'expiration et les UPNs sans appeler le serveur.
  * **Négociation de Scope** : Gérer le "consentement incrémentiel" où un script peut avoir besoin de demander plus de permissions dynamiquement.

### Compétence 5 : Logging Structuré & Télémétrie

* **Définition** : Passer de `Write-Host` à des formats de données structurés.
* **Application dans le Projet** :
  * **NDJSON/CLIXML** : Écrire les logs dans un format analysable par machine (NDJSON) pour que le Launcher puisse agréger les logs de tous les processus enfants dans une vue unifiée.
  * **Sérialisation d'Erreurs** : Sérialiser correctement les objets `ErrorRecord` pour préserver les traces de pile (stack traces) à travers les frontières de processus.

## 6. Détails Techniques d'Implémentation et Spécifications

Cette section fournit des spécifications détaillées pour les composants clés, servant de référence pour l'implémentation.

### 6.1 La Couche d'Abstraction SQLite (DAO)

Le module "Database" mentionné est critique. Il doit fonctionner comme un ORM (Object-Relational Mapper) léger.

| Fonctionnalité          | Spécification Technique                                                                  |
| :---------------------- | :--------------------------------------------------------------------------------------- |
| **Input**               | Hashtable ou Classe Personnalisée PowerShell.                                            |
| **Processus**           | Conversion des types PowerShell vers types SQL (DateTime -> ISO8601 String, $true -> 1). |
| **Output**              | Objets PowerShell personnalisés (`PSCustomObject`) et non des DataRow bruts.             |
| **Gestion Concurrence** | Implémentation implicite du `busy_timeout` sur chaque ouverture de connexion.            |
| **Mode Journal**        | `PRAGMA journal_mode=WAL;` exécuté à l'initialisation de la session.                     |

### 6.2 Le Système de Logging Centralisé

Le logging centralisé est vital pour déboguer le système distribué.

* **Format** : NDJSON (Newline Delimited JSON) est supérieur au CSV pour les données hiérarchiques (comme les exceptions) et supérieur au JSON standard pour la performance d'ajout (pas besoin de parser/réécrire tout le fichier pour ajouter une ligne).
* **Transport** : Les processus enfants doivent écrire soit vers un Named Pipe géré par le thread de logging du Launcher, soit vers un fichier de log séparé par ID de processus pour éviter la contention de verrouillage de fichier.

### 6.3 Standardisation des Modèles de Scripts

L'utilisation de Plaster est recommandée pour créer le "Golden Master".

* **Template Plaster** : Créer un modèle qui génère automatiquement la structure de dossier, le fichier `manifest.json`, les dossiers `Localization`, et le squelette du script `.ps1` avec les blocs `Try/Catch` et l'initialisation du Dispatcher pré-remplis.

## 7. Conclusion : Vers la V4 et au-delà

L'architecture "Script Tools Box V3.0" est une conception robuste qui privilégie la sécurité et l'isolation, mais elle place une charge lourde sur la gestion des ressources système. La dépendance à `Start-Process` crée une contention inévitable. Cependant, en adhérant strictement à la règle du Zéro-Gel UI, en employant SQLite en mode WAL, et en maîtrisant les flux MSAL Asynchrones, les développeurs peuvent extraire une performance maximale de cette architecture.

Les "Compétences" identifiées—particulièrement en réflexion .NET et en programmation asynchrone—sont les gardiens du succès. Sans elles, l'application se dégradera en une collection de scripts disjoints et figés. L'adoption de Plaster pour le templating et de `PSScriptAnalyzer` pour la gouvernance stricte assurera que, même avec la croissance de la base de code, le système restera maintenable, sécurisé et performant.

Pour l'avenir (V4), une transition vers une architecture purement basée sur des RunspacePools au sein d'un processus unique devrait être envisagée pour éliminer totalement la surcharge des processus multiples, bien que cela demande une rigueur encore plus grande dans la gestion des erreurs pour éviter qu'un module ne crashe l'application entière.
