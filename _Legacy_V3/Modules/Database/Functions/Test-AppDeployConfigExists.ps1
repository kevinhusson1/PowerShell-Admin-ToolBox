# Modules/Database/Functions/Test-AppDeployConfigExists.ps1

function Test-AppDeployConfigExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConfigName
    )

    try {
        # v3.1 Sanitization SQL
        $query = "SELECT COUNT(1) as Cnt FROM sp_deploy_configs WHERE ConfigName = @ConfigName"
        $sqlParams = @{ ConfigName = $ConfigName }
        
        $res = Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $query -SqlParameters $sqlParams -ErrorAction Stop
        
        return ($res.Cnt -gt 0)
    }
    catch {
        Write-Error "Erreur check config exists : $($_.Exception.Message)"
        return $false
    }
}
