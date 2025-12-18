# Modules/Database/Functions/Get-AppDeployConfigs.ps1

function Get-AppDeployConfigs {
    [CmdletBinding()]
    param(
        [string]$ConfigName
    )

    try {
        if ([string]::IsNullOrWhiteSpace($ConfigName)) {
            $query = "SELECT * FROM sp_deploy_configs ORDER BY ConfigName"
        }
        else {
            $safeName = $ConfigName.Replace("'", "''")
            $query = "SELECT * FROM sp_deploy_configs WHERE ConfigName = '$safeName'"
        }
        
        return Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $query -ErrorAction Stop
    }
    catch {
        Write-Error "Erreur lecture configs : $($_.Exception.Message)"
        return @()
    }
}
