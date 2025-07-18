# PowerShell Admin ToolBox

![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)
![PowerShell: 7.5+](https://img.shields.io/badge/PowerShell-5.1%20%7C%207%2B-blue.svg)

Une suite d'outils d'administration modernes et graphiques, construite avec PowerShell et WPF, conçue pour simplifier et automatiser les tâches courantes des administrateurs système et des ingénieurs DevOps.

![Screenshot de la ToolBox](docs/images/toolbox_screenshot.png) <!-- Vous ajouterez un screenshot ici plus tard -->

---

## À Propos du Projet

La PowerShell Admin ToolBox est née de la nécessité de combiner la puissance de l'automatisation de PowerShell avec la convivialité d'interfaces graphiques modernes. Au lieu de jongler avec des dizaines de scripts en ligne de commande, cette application fournit un catalogue centralisé d'outils, chacun avec sa propre interface intuitive.

Le projet est entièrement open-source, avec pour objectifs :
*   **Centraliser** les scripts d'administration dans une interface unique.
*   **Simplifier** des tâches complexes grâce à des formulaires et des assistants graphiques.
*   **Partager** un ensemble d'outils robustes et maintenables avec la communauté.
*   **Démontrer** la puissance de PowerShell au-delà de la simple ligne de commande.

## Fonctionnalités Principales

*   **Catalogue d'Outils Dynamique :** Ajoutez de nouveaux outils simplement en créant un script et un fichier de configuration JSON, sans modifier le lanceur principal.
*   **Gestion des Utilisateurs Active Directory & Azure AD :** Outils graphiques pour la création, la désactivation et la réactivation d'utilisateurs.
*   **Gestion des Groupes :** Assistants visuels pour gérer l'appartenance aux groupes AD et Azure.
*   **Annuaire d'Entreprise :** Une interface de recherche et de filtrage puissante pour consulter les détails des utilisateurs via Microsoft Graph.
*   **Gestion de Processus Distants :** Un gestionnaire de tâches réseau pour visualiser et terminer les processus sur les serveurs distants (idéal pour les environnements RDS).
*   **SharePoint Provisioning :** Déployez des arborescences de dossiers et de permissions complexes sur des sites SharePoint à partir de modèles XML.
*   **Emailer Avancé :** Envoyez des e-mails via Microsoft Graph en utilisant des templates HTML personnalisables.
*   **Éditeur XML Structuré :** Un éditeur graphique pour construire des fichiers de configuration complexes en respectant un schéma prédéfini.

## Pour Commencer

Pour faire fonctionner ce projet sur votre machine, suivez ces étapes.

### Prérequis

1.  **PowerShell :** Version 5.1 ou, de préférence, PowerShell 7+.
2.  **Modules PowerShell :** Assurez-vous que les modules suivants sont installés. Vous pouvez utiliser l'outil `Check-Module` inclus pour vous aider.
    *   `Microsoft.Graph` (Authentication, Users, Mail, PersonalContacts, Groups)
    *   `ActiveDirectory` (disponible via les outils RSAT)
    *   `PnP.PowerShell`
3.  **Permissions API :** Une application Azure AD doit être enregistrée avec les permissions nécessaires (ex: `User.Read.All`, `GroupMember.ReadWrite.All`, `Contacts.ReadWrite`, `Mail.Send`).

### Installation

1.  **Clonez le dépôt :**
    ```sh
    git clone https://github.com/kevinhusson1/PowerShell-Admin-ToolBox.git
    ```
2.  **Naviguez dans le dossier du projet :**
    ```sh
    cd PowerShell-Admin-ToolBox
    ```
3.  **Configurez l'application :**
    *   À la racine, trouvez le fichier `config.template.json`.
    *   Copiez-le et renommez la copie en `config.json`.
    *   Ouvrez `config.json` et remplissez les valeurs (ID Client, Tenant, etc.) avec vos propres informations. **Ce fichier est ignoré par Git et ne doit jamais être publié.**

## Utilisation

Pour lancer l'application, exécutez le lanceur principal depuis une console PowerShell :

```powershell
./src/Launcher.ps1
