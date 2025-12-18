# Modules/Database/Functions/Initialize-AppDatabase.ps1

<#
.SYNOPSIS
    Initialise la base de données SQLite de l'application.
.DESCRIPTION
    Cette fonction vérifie l'existence de la base de données et de son schéma.
    Si le fichier de base de données n'existe pas, elle le crée et initialise
    toutes les tables nécessaires.
    Si le fichier existe, elle vérifie que toutes les tables attendues sont présentes
    et crée celles qui seraient manquantes (migration de schéma simple).
.PARAMETER ProjectRoot
    Le chemin racine du projet où le dossier /Config se trouve.
.EXAMPLE
    Initialize-AppDatabase -ProjectRoot "C:\Projet\Toolbox"
.OUTPUTS
    Aucune. Définit la variable $Global:AppDatabasePath.
#>

function Initialize-AppDatabase {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot
    )

    $dbPath = Join-Path -Path $ProjectRoot -ChildPath "Config\database.sqlite"
    $Global:AppDatabasePath = $dbPath
    $dbExists = Test-Path $dbPath

    try {
        # --- DÉFINITION DU SCHÉMA ATTENDU ---
        $schema = @{
            'active_sessions'     = @"
                CREATE TABLE active_sessions (
                    RunID       INTEGER PRIMARY KEY AUTOINCREMENT,
                    ScriptName  TEXT NOT NULL,
                    OwnerPID    INTEGER NOT NULL,
                    OwnerHost   TEXT,
                    StartTime   TEXT
                );
"@
            'settings'            = @"
                CREATE TABLE settings (
                    Key     TEXT PRIMARY KEY NOT NULL,
                    Value   TEXT,
                    Type    TEXT NOT NULL CHECK(Type IN ('string', 'integer', 'boolean'))
                );
"@
            'script_progress'     = @"
                CREATE TABLE script_progress (
                    OwnerPID            INTEGER PRIMARY KEY NOT NULL,
                    ProgressPercentage  INTEGER,
                    StatusMessage       TEXT
                );
"@
            # --- NOUVELLE TABLE : Gestion des demandes de permissions ---
            'permission_requests' = @"
                CREATE TABLE permission_requests (
                    RequestID       INTEGER PRIMARY KEY AUTOINCREMENT,
                    RequesterUPN    TEXT NOT NULL,
                    RequestedScope  TEXT NOT NULL,
                    Reason          TEXT,
                    Status          TEXT DEFAULT 'Pending', -- Pending, Approved, Rejected
                    RequestDate     TEXT,
                    ResolutionDate  TEXT,
                    ResolverUPN     TEXT
                );
"@
            # --- Table des paramètres propres aux scripts ---
            'script_settings'     = @"
                CREATE TABLE script_settings (
                    ScriptId            TEXT PRIMARY KEY NOT NULL,
                    IsEnabled           INTEGER DEFAULT 1, -- 1 = True, 0 = False
                    MaxConcurrentRuns   INTEGER DEFAULT 1
                );
"@
            # Table de liaison Script <-> Groupes AD
            'script_security'     = @"
                CREATE TABLE script_security (
                    ScriptId    TEXT NOT NULL,
                    ADGroup     TEXT NOT NULL,
                    PRIMARY KEY (ScriptId, ADGroup)
                );
"@
            # --- Table des groupes connus (Bibliothèque) ---
            'known_groups'        = @"
                CREATE TABLE known_groups (
                    GroupName TEXT PRIMARY KEY NOT NULL,
                    Description TEXT
                );
"@
            # --- Table des Modèles d'arborescence (JSON) ---
            'sp_templates'        = @"
                CREATE TABLE sp_templates (
                    TemplateId      TEXT PRIMARY KEY,
                    DisplayName     TEXT NOT NULL,
                    Description     TEXT,
                    Category        TEXT,
                    StructureJson   TEXT NOT NULL, -- L'arbre complet
                    NamingRuleId    TEXT,
                    AutoSelectGroup TEXT,
                    DateModified    TEXT
                );
"@
            # --- Table des Règles de Nommage (Formulaire Dynamique) ---
            'sp_naming_rules'     = @"
                CREATE TABLE sp_naming_rules (
                    RuleId          TEXT PRIMARY KEY,
                    DefinitionJson  TEXT NOT NULL  -- La structure du formulaire (Labels, Inputs)
                );
"@
            # --- Table des Logs de Déploiement ---
            'sp_deploy_logs'      = @"
                CREATE TABLE sp_deploy_logs (
                    LogId           INTEGER PRIMARY KEY AUTOINCREMENT,
                    Date            TEXT,
                    UserUPN         TEXT,
                    TargetUrl       TEXT,
                    TemplateId      TEXT,
                    Status          TEXT,
                    Details         TEXT
                );
"@
            # --- Table des Configurations de Déploiement ---
            'sp_deploy_configs'   = @"
                CREATE TABLE sp_deploy_configs (
                    ConfigName          TEXT PRIMARY KEY,
                    SiteUrl             TEXT,
                    LibraryName         TEXT,
                    TargetFolder        TEXT,
                    OverwritePermissions INTEGER, -- 0 or 1
                    TemplateId          TEXT,
                    DateModified        TEXT
                );
"@
        }
        # ------------------------------------

        # Si la DB n'existe pas, on la crée et on quitte, pas besoin de vérifier les tables.
        if (-not $dbExists) {
            $logMsg = "{0} '$dbPath'. {1}" -f (Get-AppText 'modules.database.db_not_found'), (Get-AppText 'modules.database.db_creating')
            Write-Verbose $logMsg
            
            $schema.Values | ForEach-Object {
                Invoke-SqliteQuery -DataSource $dbPath -Query $_ -ErrorAction Stop
            }
            Write-Verbose (Get-AppText 'modules.database.schema_init_success')
            return
        }

        # Si la DB existe, on doit vérifier chaque table.
        Write-Verbose (Get-AppText 'modules.database.schema_checking')
        
        # On récupère la liste de TOUTES les tables existantes dans la base.
        $queryTables = "SELECT name FROM sqlite_master WHERE type='table';"
        $existingTables = (Invoke-SqliteQuery -DataSource $dbPath -Query $queryTables).name

        # On boucle sur notre schéma attendu.
        foreach ($table in $schema.GetEnumerator()) {
            $tableName = $table.Name
            $createQuery = $table.Value

            if ($tableName -notin $existingTables) {
                $warningMsg = "{0} '$tableName'. {1}" -f (Get-AppText 'modules.database.table_missing_1'), (Get-AppText 'modules.database.table_missing_2')
                Write-Warning $warningMsg
                
                Invoke-SqliteQuery -DataSource $dbPath -Query $createQuery -ErrorAction Stop
                
                $logMsg = "{0} '$tableName' {1}" -f (Get-AppText 'modules.database.table_created_1'), (Get-AppText 'modules.database.table_created_2')
                Write-Verbose $logMsg
            }
        }
        Write-Verbose (Get-AppText 'modules.database.schema_check_done')

    }
    catch {
        $errorMsg = Get-AppText -Key 'modules.database.schema_error'
        throw "$errorMsg : $($_.Exception.Message)"
    }
}