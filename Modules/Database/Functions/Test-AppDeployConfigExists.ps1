# Modules/Database/Functions/Test-AppDeployConfigExists.ps1

function Test-AppDeployConfigExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConfigName
    )

    try {
        $safeName = $ConfigName.Replace("'", "''")
        $query = "SELECT COUNT(1) as Cnt FROM sp_deploy_configs WHERE ConfigName = '$safeName'"
        $res = Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $query -ErrorAction Stop
        
        return ($res.Cnt -gt 0)
    }
    catch {
        Write-Error "Erreur check config exists : $($_.Exception.Message)"
        return $false
    }
}
