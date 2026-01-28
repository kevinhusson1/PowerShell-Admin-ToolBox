# Modules/Database/Functions/Set-AppDeployConfig.ps1

<#
.SYNOPSIS
    Sauvegarde ou met à jour une configuration de déploiement dans la base de données.

.DESCRIPTION
    Cette fonction stocke l'état complet du formulaire de déploiement (Site, Lib, Template, Options) 
    dans la table 'sp_deploy_configs' de la base SQLite locale.
    Elle gère aussi les nouvelles propriétés v3.2 comme 'Options' (JSON) pour les toggles UI.

.PARAMETER ConfigName
    Le nom unique de la configuration (Clé Primaire).

.PARAMETER SiteUrl
    L'URL du site cible sélectionné.

.PARAMETER LibraryName
    Le nom de la bibliothèque documentaire cible.

.PARAMETER TargetFolder
    (Optionnel) L'ID de la règle de nommage pour le dossier racine (si création demandée).

.PARAMETER OverwritePermissions
    (Bool) Indique si la case "Écraser les permissions" était cochée.

.PARAMETER TemplateId
    L'ID du modèle d'arborescence sélectionné.

.PARAMETER TargetFolderPath
    (Optionnel) Le chemin relatif serveur du dossier cible (si déploiement dans un sous-dossier).

.PARAMETER AuthorizedRoles
    (Optionnel) Liste des rôles/groupes autorisés (séparés par virgule).

.PARAMETER Options
    (Optionnel) Objet JSON contenant les options UI additionnelles (ex: ApplyMetadata).

.OUTPUTS
    [bool] $true si succès.
#>
function Set-AppDeployConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$ConfigName,
        [string]$SiteUrl,
        [string]$LibraryName,
        [string]$TargetFolder,
        [bool]$OverwritePermissions,
        [string]$TemplateId,
        [string]$TargetFolderPath,
        [string]$AuthorizedRoles,
        [string]$Options # Ajout v3.2 Checkbox Meta
    )

    try {
        # Sécurisation SQL (v3.1)
        $safeOverride = if ($OverwritePermissions) { 1 } else { 0 }
        $safeFolderPath = if ($TargetFolderPath) { $TargetFolderPath } else { "" }
        $safeRoles = if ($AuthorizedRoles) { $AuthorizedRoles } else { "" }
        $safeOptions = if ($Options) { $Options } else { "{}" }
        $date = (Get-Date -Format 'o')

        $query = @"
            INSERT OR REPLACE INTO sp_deploy_configs 
            (ConfigName, SiteUrl, LibraryName, TargetFolder, OverwritePermissions, TemplateId, DateModified, TargetFolderPath, AuthorizedRoles, Options) 
            VALUES 
            (@ConfigName, @SiteUrl, @LibraryName, @TargetFolder, @OverwritePermissions, @TemplateId, @DateModified, @TargetFolderPath, @AuthorizedRoles, @Options);
"@
        
        $sqlParams = @{
            ConfigName           = $ConfigName
            SiteUrl              = $SiteUrl
            LibraryName          = $LibraryName
            TargetFolder         = $TargetFolder
            OverwritePermissions = $safeOverride
            TemplateId           = $TemplateId
            DateModified         = $date
            TargetFolderPath     = $safeFolderPath
            AuthorizedRoles      = $safeRoles
            Options              = $safeOptions
        }

        Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $query -SqlParameters $sqlParams -ErrorAction Stop
        return $true
    }
    catch {
        throw "Erreur sauvegarde config : $($_.Exception.Message)"
    }
}
