# Plan d'Action : SharePoint Builder v3.0

**Date de révision :** 2025-11-28  
**Statut :** Phase 1 (Moteur de base) - TERMINÉE ✅  
**Prochaine étape :** Phase 2 (Validation & Migration)

---

## ✅ Phase 1 : Architecture & Moteur Core (TERMINÉ)

### 1.1 Architecture Validée
- [x] Schéma BDD (sp_templates, sp_naming_rules, sp_deploy_logs)
- [x] Module `Toolbox.SharePoint` avec fonctions dédiées
- [x] Pattern Dual-Auth (User Graph + App-Only PnP)
- [x] UI Non-Bloquante (Jobs PowerShell + DispatcherTimer)

### 1.2 Authentification
- [x] `Enable-ScriptIdentity.ps1` aligné sur DefaultUI
- [x] Restauration du contexte Launcher (Base64)
- [x] Macaron utilisateur fonctionnel

### 1.3 Moteur de Provisioning
- [x] `New-AppSPStructure.ps1` avec support :
  - Création récursive de dossiers
  - Application des permissions (Set-PnPListItemPermission)
  - Application des métadonnées/tags (Set-PnPListItem)
  - Création de liens .url (Add-PnPFile)
- [x] Connexion App-Only (Certificat) stricte
- [x] Logging détaillé dans le résultat

### 1.4 Interface Déploiement
- [x] Chargement automatique des sites (async, au démarrage, via Certificat)
- [x] Formulaire dynamique basé sur `sp_naming_rules`
- [x] Preview du nom de dossier en temps réel
- [x] Bouton Deploy câblé avec validation et feedback
- [x] Barre de progression + Logs temps réel

### 1.5 Données de Test
- [x] Script `Seed-SharePointData.ps1` avec exemple complet (Permissions, Tags, Links)
- [x] Template "Modèle Chantier v3.0" injecté en BDD

---

## 🔄 Phase 2 : Validation & Migration (EN COURS)

### 2.1 Tests de Bout-en-Bout
**Priorité : CRITIQUE**

#### Checklist Validation Manuelle
- [ ] **Test Auth** : Lancer via Launcher, vérifier la restauration du contexte
- [ ] **Test Autonome** : Lancer en mode standalone, vérifier la popup de connexion
- [ ] **Test Sites** : Vérifier que la liste des sites se charge automatiquement
- [ ] **Test Formulaire** : Sélectionner un template, vérifier la génération du formulaire
- [ ] **Test Déploiement** :
  - [ ] Créer un dossier simple (sans permissions/tags)
  - [ ] Créer un dossier avec permissions
  - [ ] Créer un dossier avec tags (métadonnées)
  - [ ] Créer un dossier avec lien .url
  - [ ] Vérifier la structure complète récursive

#### Actions si Échec
- Activer `$VerbosePreference = 'Continue'` dans le script principal
- Consulter les logs du RichTextBox
- Vérifier les permissions de l'App Registration (Sites.FullControl.All)

---

### 2.2 Migration des Données Legacy
**Priorité : HAUTE**

#### Objectif
Convertir vos anciens fichiers XML et `FolderNameTemplates.ps1` en données SQLite.

#### Script à Créer : `Migrate-LegacyToSQLite.ps1`

**Entrées :**
- Dossier contenant les XMLs (ex: `Legacy/XMLModels/`)
- Fichier `FolderNameTemplates.ps1`

**Sorties :**
- Insertion dans `sp_templates` (un par XML)
- Insertion dans `sp_naming_rules` (déduit des templates)

**Logique :**
```powershell
# Parser XML
$xmlDoc = [xml](Get-Content $xmlPath)
$root = $xmlDoc.DocumentElement

# Fonction récursive de conversion
function Convert-XmlNodeToJson {
    param($XmlNode)
    
    $result = @{
        Name = $XmlNode.GetAttribute("name")
    }
    
    # Permissions
    if ($XmlNode.SelectSingleNode("permissions")) {
        $result.Permissions = @()
        foreach ($user in $XmlNode.SelectNodes("permissions/user")) {
            $result.Permissions += @{
                Email = $user.GetAttribute("email")
                Level = $user.GetAttribute("level")
            }
        }
    }
    
    # Tags
    if ($XmlNode.SelectSingleNode("tags")) {
        $result.Tags = @()
        foreach ($tag in $XmlNode.SelectNodes("tags/tag")) {
            $result.Tags += @{
                Name = $tag.GetAttribute("name")
                Value = $tag.GetAttribute("value")
            }
        }
    }
    
    # Links
    if ($XmlNode.SelectSingleNode("link")) {
        $result.Links = @()
        foreach ($link in $XmlNode.SelectNodes("link")) {
            $result.Links += @{
                Name = $link.GetAttribute("name")
                Url = $link.GetAttribute("destination")
            }
        }
    }
    
    # Récursion (Sous-dossiers)
    $children = $XmlNode.SelectNodes("directory")
    if ($children.Count -gt 0) {
        $result.Folders = @()
        foreach ($child in $children) {
            $result.Folders += Convert-XmlNodeToJson -XmlNode $child
        }
    }
    
    return $result
}

# Génération JSON
$structure = @{ Root = Convert-XmlNodeToJson -XmlNode $root }
$json = $structure | ConvertTo-Json -Depth 20 -Compress

# Insertion BDD
$jsonSql = $json -replace "'", "''"
Invoke-SqliteQuery -DataSource $dbPath -Query "INSERT INTO sp_templates (...) VALUES (...)"
```

**TODO :** Créer ce script si vous voulez migrer les anciens modèles.

---

### 2.3 RBAC (Role-Based Access Control)
**Priorité : MOYENNE**

#### Objectif
Afficher l'onglet "Conception" uniquement pour les admins.

#### Modification dans `SharePointBuilder.ps1`
```powershell
# Après l'initialisation de la BDD et avant l'UI
$isAdmin = $false
if ($Global:AppAzureAuth.UserAuth.Connected) {
    $adminGroup = Get-AppSetting -Key 'security.adminGroup' # Ex: "SG_Toolbox_Admins"
    $userGroups = Get-AppUserAzureGroups -UserUPN $Global:AppAzureAuth.UserAuth.UserPrincipalName
    $isAdmin = $userGroups -contains $adminGroup
}

# Dans Initialize-BuilderLogic ou après le chargement XAML
if ($isAdmin) {
    $designerTab = $window.FindName("DesignerTabItem")
    if ($designerTab) { $designerTab.Visibility = "Visible" }
}
```

**TODO :** Implémenter si besoin de séparer les utilisateurs/admins.

---

## 🚀 Phase 3 : Fonctionnalités Avancées (FUTUR)

### 3.1 Onglet "Conception" (Designer)
**Priorité : BASSE (v3.1)**

#### Objectif
Interface WYSIWYG pour créer/modifier des templates sans éditer du JSON.

#### Fonctionnalités
- TreeView éditable (Drag & Drop pour réorganiser)
- Panneau de propriétés (Nom, Permissions, Tags, Links)
- Boutons "Nouveau Dossier", "Supprimer", "Sauvegarder"
- Export/Import XML pour compatibilité

#### Technologies
- `TreeView` WPF avec `HierarchicalDataTemplate`
- Binding bidirectionnel sur une collection ObservableCollection
- Sérialisation JSON pour sauvegarder en BDD

**TODO :** À développer dans une future version si le gain de temps justifie l'effort.

---

### 3.2 Dry Run (Simulation)
**Priorité : MOYENNE**

#### Objectif
Valider la structure avant déploiement réel.

#### Modification de `New-AppSPStructure`
Ajouter un paramètre `-WhatIf` qui :
- Ne crée rien sur SharePoint
- Simule toutes les opérations
- Retourne un rapport de ce qui serait fait

```powershell
if (-not $WhatIf) {
    Resolve-PnPFolder -SiteRelativePath $fullPath -Connection $conn
} else {
    Log "  [SIMULATION] Dossier qui serait créé : $fullPath"
}
```

---

### 3.3 Logs de Déploiement (Historique)
**Priorité : BASSE**

#### Objectif
Tracer qui a déployé quoi et quand.

#### Modification du bouton Deploy
Après un déploiement réussi :
```powershell
$logEntry = @{
    Date = Get-Date -Format "o"
    UserUPN = $Global:AppAzureAuth.UserAuth.UserPrincipalName
    TargetUrl = $targetSiteUrl
    TemplateId = $cbTpl.SelectedItem.TemplateId
    Status = "Success"
    Details = $result.Logs -join "`n"
}

Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query "INSERT INTO sp_deploy_logs (...) VALUES (...)"
```

Ajouter un onglet "Historique" dans l'UI pour consulter.

---

## 🔍 Phase 4 : Optimisations & Polish (FUTUR)

### 4.1 Performance
- Mettre en cache les résultats de `Get-AppSPSites` (éviter de recharger à chaque ouverture)
- Utiliser `Invoke-PnPBatch` pour les déploiements massifs

### 4.2 UX
- Ajouter des tooltips sur tous les contrôles
- Animations de transition entre les états
- Icônes personnalisées pour chaque type de dossier dans la preview

### 4.3 Internationalisation
- Ajouter des clés de traduction pour tous les textes
- Support multilingue (FR/EN)

---

## 📋 Prochaines Actions Immédiates

### Recommandation : Tester MAINTENANT
Avant d'aller plus loin, je recommande de :

1. **Vérifier la config Azure** :
   ```powershell
   Get-AppSetting -Key 'azure.authentication.userAuth.appId'
   Get-AppSetting -Key 'azure.certThumbprint'
   Get-AppSetting -Key 'azure.tenantName'
   ```

2. **Lancer SharePointBuilder en mode Debug** :
   ```powershell
   cd c:\CLOUD\Github\PowerShell-Admin-ToolBox
   .\Scripts\Sharepoint\SharePointBuilder\SharePointBuilder.ps1
   ```

3. **Valider le chargement des sites** (devrait se faire automatiquement via Certificat)

4. **Faire un déploiement de test** sur un site sandbox

### Si ça fonctionne ✅
- On peut passer à la migration Legacy (Phase 2.2)
- Ou directement attaquer le Designer (Phase 3.1)

### Si ça bloque ❌
- Me partager les logs/erreurs
- On débuggera ensemble

---

## ❓ Questions Pour Toi

1. **As-tu un certificat configuré** dans ta BDD ? (Thumbprint valide ?)
2. **L'App Registration a-t-elle les bons droits** ? (Sites.FullControl.All)
3. **Veux-tu migrer tes anciens XML** ou repartir de zéro avec des nouveaux modèles JSON ?
4. **Quelle est ta priorité** : Designer WYSIWYG ou Migration Legacy ?

---

**Note Finale :** La base technique est solide. On est à ~70% de la v3.0 fonctionnelle. Les 30% restants dépendent de tes besoins métier (migration vs nouvelles fonctionnalités).
