# Modules/Database/Functions/Get-AppSPTemplates.ps1

function Get-AppSPTemplates {
    [CmdletBinding()]
    param(
        [string]$TemplateId
    )

    try {
        # v3.1 Sanitization SQL
        $query = "SELECT * FROM sp_templates"
        $sqlParams = @{}
        
        if (-not [string]::IsNullOrWhiteSpace($TemplateId)) {
            $query += " WHERE TemplateId = @TemplateId"
            $sqlParams.TemplateId = $TemplateId
        }
        $query += " ORDER BY DisplayName"

        return Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $query -SqlParameters $sqlParams -ErrorAction Stop
    }
    catch {
        Write-Warning "Erreur lecture templates : $($_.Exception.Message)"
        return @()
    }
}