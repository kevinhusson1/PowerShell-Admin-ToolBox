# Modules/Database/Functions/Set-AppSPTemplate.ps1

function Set-AppSPTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$TemplateId,
        [Parameter(Mandatory)] [string]$DisplayName,
        [string]$Description,
        [string]$Category = "Custom",
        [Parameter(Mandatory)] [string]$StructureJson
    )

    try {
        # Sécurisation SQL (v3.1)
        $date = (Get-Date -Format 'o')

        $query = @"
            INSERT OR REPLACE INTO sp_templates 
            (TemplateId, DisplayName, Description, Category, StructureJson, DateModified) 
            VALUES 
            (@TemplateId, @DisplayName, @Description, @Category, @StructureJson, @DateModified);
"@
        
        $sqlParams = @{
            TemplateId    = $TemplateId
            DisplayName   = $DisplayName
            Description   = $Description
            Category      = $Category
            StructureJson = $StructureJson
            DateModified  = $date
        }

        Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $query -SqlParameters $sqlParams -ErrorAction Stop
        return $true
    }
    catch {
        throw "Erreur sauvegarde template : $($_.Exception.Message)"
    }
}