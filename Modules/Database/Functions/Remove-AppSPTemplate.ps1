# Modules/Database/Functions/Remove-AppSPTemplate.ps1

function Remove-AppSPTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$TemplateId
    )

    try {
        # v3.1 Sanitization SQL
        $query = "DELETE FROM sp_templates WHERE TemplateId = @TemplateId"
        $sqlParams = @{ TemplateId = $TemplateId }
        
        Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $query -SqlParameters $sqlParams -ErrorAction Stop
        return $true
    }
    catch {
        throw "Erreur suppression template : $($_.Exception.Message)"
    }
}