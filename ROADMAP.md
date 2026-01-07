# 🗺️ Roadmap du Projet PowerShell Admin ToolBox

Ce document recense les évolutions majeures planifiées et les idées d'amélioration pour l'architecture de la solution. Il sert de guide pour les développements futurs.

---

## 🔒 Sécurité & Architecture

### 🚀 Chantier : Intégration Azure Key Vault (Architecture V4)
**Objectif :** Atteindre le niveau de sécurité "Zero Local Secret".
Actuellement, le certificat d'administration (App-Only) est stocké localement sur la machine de l'administrateur (`Cert:\CurrentUser\My`). Si la machine est compromise, le certificat l'est aussi.

**La Solution Cible :** 
Stocker le certificat (fichier `.pfx`) en tant que secret dans un **Azure Key Vault (AKV)** et ne le récupérer qu'au moment de l'exécution, **uniquement en mémoire RAM**.

#### Workflow Technique
1.  **Authentification Initiale** : L'utilisateur (l'admin) s'authentifie sur le Launcher via Azure AD (SSO).
2.  **Autorisation RBAC** : Le script vérifie si l'utilisateur a le droit de lire les secrets du Key Vault cible.
3.  **Récupération Sécurisée** : 
    *   Téléchargement du secret (le certificat encodé en Base64) depuis Azure Key Vault via Microsoft Graph ou le module Az.
4.  **Reconstruction In-Memory** : 
    *   Création d'un objet `.NET X509Certificate2` directement en mémoire.
    *   **Aucune écriture sur le disque dur** (pas de fichier temporaire).
5.  **Connexion PnP** :
    *   Utilisation de la surcharge de `Connect-PnPOnline` qui accepte un objet certificat ou une connexion PEM/Base64, au lieu d'un Thumbprint local.

#### Avantages
*   **Sécurité Maximale** : Aucun fichier sensible ne réside sur les postes de travail.
*   **Révocation Immédiate** : Il suffit de retirer les droits d'accès au Key Vault à un utilisateur pour qu'il ne puisse plus utiliser l'outil (même s'il a copié le script).
*   **Audit Centralisé** : Les logs d'accès du Key Vault permettent de savoir exactement **qui** a utilisé le certificat et **quand**.

#### Pré-requis
*   Une ressource Azure Key Vault déployée.
*   Le certificat PnP uploadé dans les "Secrets" ou "Certificats" du KV.
*   Configuration des rôles IAM (RBAC) pour le groupe des administrateurs ToolBox.

---

## 🛠️ Expérience Utilisateur (UI/UX)

*   *(À venir : Dashboard de santé, Notifications toast, Thèmes personnalisés...)*

## 📦 Fonctionnalités SharePoint

*   *(À venir : Gestion des Sites Hub, Templates de Site Design avancés...)*
