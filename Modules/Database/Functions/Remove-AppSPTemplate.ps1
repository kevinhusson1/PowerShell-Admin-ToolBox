# Modules/Database/Functions/Remove-AppSPTemplate.ps1

function Remove-AppSPTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$TemplateId
    )

    try {
        $safeId = $TemplateId.Replace("'", "''")
        $query = "DELETE FROM sp_templates WHERE TemplateId = '$safeId'"
        
        Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $query -ErrorAction Stop
        return $true
    }
    catch {
        throw "Erreur suppression template : $($_.Exception.Message)"
    }
}