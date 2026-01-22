# Modules/Database/Functions/Remove-AppDeployConfig.ps1

function Remove-AppDeployConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$ConfigName
    )

    try {
        # v3.1 Sanitization SQL
        $query = "DELETE FROM sp_deploy_configs WHERE ConfigName = @ConfigName"
        $sqlParams = @{ ConfigName = $ConfigName }
        
        Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $query -SqlParameters $sqlParams -ErrorAction Stop
        return $true
    }
    catch {
        throw "Erreur suppression config : $($_.Exception.Message)"
    }
}
