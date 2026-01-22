# Modules/Database/Functions/Get-AppDeployConfigs.ps1

function Get-AppDeployConfigs {
    [CmdletBinding()]
    param(
        [string]$ConfigName
    )

    try {
        # v3.1 Sanitization SQL
        $sqlParams = @{}
        
        if ([string]::IsNullOrWhiteSpace($ConfigName)) {
            $query = "SELECT * FROM sp_deploy_configs ORDER BY ConfigName"
        }
        else {
            $query = "SELECT * FROM sp_deploy_configs WHERE ConfigName = @ConfigName"
            $sqlParams.ConfigName = $ConfigName
        }
        
        return Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $query -SqlParameters $sqlParams -ErrorAction Stop
    }
    catch {
        Write-Error "Erreur lecture configs : $($_.Exception.Message)"
        return @()
    }
}
