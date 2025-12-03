# Scripts/SharePoint/SharePointBuilder/Seed-SharePointData.ps1

# 1. Chargement du contexte (si lancé manuellement)
if (-not $Global:AppDatabasePath) {
    $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
    $projectRoot = (Get-Item $scriptRoot).Parent.Parent.Parent.FullName
    Import-Module "$projectRoot\Modules\Database" -Force
    Initialize-AppDatabase -ProjectRoot $projectRoot
}

Write-Host "Injection des données de test SharePoint..." -ForegroundColor Cyan

# --- A. Règle de Nommage (Formulaire Dynamique) ---
# Simule l'ancien FolderNameTemplates.ps1
$namingRule = @{
    Layout = @(
        @{ Type = "Label"; Content = "C-" },
        @{ Type = "TextBox"; Name = "CodeChantier"; DefaultValue = ""; Width = 60 },
        @{ Type = "Label"; Content = "_" },
        @{ Type = "TextBox"; Name = "NomChantier"; DefaultValue = "NomDuChantier"; Width = 150 },
        @{ Type = "Label"; Content = "_" },
        @{ Type = "ComboBox"; Name = "Annee"; Options = @("2024", "2025", "2026"); Width = 70 }
    )
    Description = "Format standard : C-000_Nom_Annee"
}
$jsonRule = $namingRule | ConvertTo-Json -Depth 10 -Compress

# Insertion Règle
$ruleId = "Rule-Chantier-v1"
$q1 = "INSERT OR REPLACE INTO sp_naming_rules (RuleId, DefinitionJson) VALUES ('$ruleId', '$($jsonRule.Replace("'", "''"))');"
Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $q1

# --- B. Modèle d'Arborescence (Template) ---
# Simule l'ancien XML
$structure = @{
    Folders = @(
        @{ 
            Name = "01_Administratif"
            Folders = @(
                @{ Name = "Contrats" },
                @{ Name = "Factures" }
            )
        },
        @{ 
            Name = "02_Technique"
            Folders = @(
                @{ Name = "Plans" },
                @{ Name = "Rapports" }
            )
        },
        @{
            Name = "03_Photos"
            # Exemple de permission spécifique (optionnel)
            Permissions = @(
                @{ Email = "G_Direction"; Level = "Read" }
            )
        }
    )
}
$jsonStructure = $structure | ConvertTo-Json -Depth 10 -Compress

# Insertion Template
$tplId = "Tpl-Chantier-Std"
$q2 = "INSERT OR REPLACE INTO sp_templates (TemplateId, DisplayName, Description, Category, StructureJson, NamingRuleId) 
       VALUES ('$tplId', 'Modèle Chantier Standard', 'Structure classique pour les nouveaux chantiers.', 'Opérations', '$($jsonStructure.Replace("'", "''"))', '$ruleId');"
Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $q2

Write-Host "✅ Données injectées avec succès." -ForegroundColor Green