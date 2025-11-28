# Seed-SharePointData.ps1
# Script temporaire pour peupler la base avec un exemple

Import-Module ".\Modules\Database" -Force
Import-Module ".\Vendor\PSSQLite" -Force

$dbPath = ".\Config\database.sqlite"
$Global:AppDatabasePath = $dbPath

# 1. Règle de Nommage (JSON)
# Correspond à votre ancien FolderNameTemplates.ps1
$namingRule = @{
    Layout = @(
        @{ Type = "Label"; Content = "Année :" },
        @{ Type = "TextBox"; Name = "Year"; DefaultValue = "$(Get-Date -Format yyyy)" },
        @{ Type = "Label"; Content = "_" },
        @{ Type = "ComboBox"; Name = "Type"; Options = @("PROJET", "CHANTIER", "APPEL_OFFRE") },
        @{ Type = "Label"; Content = "_" },
        @{ Type = "TextBox"; Name = "Client"; DefaultValue = "" }
    )
    Description = "Format : ANNEE_TYPE_CLIENT"
} | ConvertTo-Json -Depth 5

$q1 = "INSERT OR REPLACE INTO sp_naming_rules (RuleId, DefinitionJson) VALUES ('RULE_PROJET_V1', '$namingRule');"
Invoke-SqliteQuery -DataSource $dbPath -Query $q1

# 2. Modèle d'arborescence (Structure JSON simplifiée pour le test)
# Correspond à la structure de vos anciens XML
$structure = @{
    Root = @{
        Folders = @(
            @{ Name = "01_Administratif"; Folders = @() },
            @{ Name = "02_Technique"; Folders = @(
                @{ Name = "Plans" }
                @{ Name = "Rapports" }
            )},
            @{ Name = "03_Financier"; Security = @{ Inherit = $false; Readers = @("Direction") } }
        )
    }
} | ConvertTo-Json -Depth 10

$q2 = "INSERT OR REPLACE INTO sp_templates (TemplateId, DisplayName, Description, Category, StructureJson, NamingRuleId, DateModified) 
       VALUES ('TPL_CHANTIER', 'Modèle Chantier Standard', 'Structure classique pour les chantiers de réhabilitation.', 'Chantier', '$structure', 'RULE_PROJET_V1', '$(Get-Date)');"
Invoke-SqliteQuery -DataSource $dbPath -Query $q2

Write-Host "Données injectées avec succès." -ForegroundColor Green