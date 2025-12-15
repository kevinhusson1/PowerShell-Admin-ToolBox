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
        # Sécurisation SQL
        $safeId = $TemplateId.Replace("'", "''")
        $safeName = $DisplayName.Replace("'", "''")
        $safeDesc = $Description.Replace("'", "''")
        $safeCat = $Category.Replace("'", "''")
        $safeJson = $StructureJson.Replace("'", "''") # Le JSON contient souvent des quotes
        $date = (Get-Date -Format 'o')

        $query = @"
            INSERT OR REPLACE INTO sp_templates 
            (TemplateId, DisplayName, Description, Category, StructureJson, DateModified) 
            VALUES 
            ('$safeId', '$safeName', '$safeDesc', '$safeCat', '$safeJson', '$date');
"@
        
        Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $query -ErrorAction Stop
        return $true
    }
    catch {
        throw "Erreur sauvegarde template : $($_.Exception.Message)"
    }
}