# Modules/Database/Functions/Remove-AppDeployConfig.ps1

function Remove-AppDeployConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$ConfigName
    )

    try {
        $safeName = $ConfigName.Replace("'", "''")
        $query = "DELETE FROM sp_deploy_configs WHERE ConfigName = '$safeName'"
        
        Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $query -ErrorAction Stop
        return $true
    }
    catch {
        throw "Erreur suppression config : $($_.Exception.Message)"
    }
}
