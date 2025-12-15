# Modules/Database/Functions/Get-AppSPTemplates.ps1

function Get-AppSPTemplates {
    [CmdletBinding()]
    param(
        [string]$TemplateId
    )

    try {
        $query = "SELECT * FROM sp_templates"
        if (-not [string]::IsNullOrWhiteSpace($TemplateId)) {
            $safeId = $TemplateId.Replace("'", "''")
            $query += " WHERE TemplateId = '$safeId'"
        }
        $query += " ORDER BY DisplayName"

        return Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $query -ErrorAction Stop
    }
    catch {
        Write-Warning "Erreur lecture templates : $($_.Exception.Message)"
        return @()
    }
}