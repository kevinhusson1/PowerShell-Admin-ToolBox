# Modules/Database/Functions/Set-AppDeployConfig.ps1

function Set-AppDeployConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$ConfigName,
        [string]$SiteUrl,
        [string]$LibraryName,
        [string]$TargetFolder,
        [bool]$OverwritePermissions,
        [string]$TemplateId,
        [string]$TargetFolderPath
    )

    try {
        # Sécurisation SQL
        $safeName = $ConfigName.Replace("'", "''")
        $safeUrl = $SiteUrl.Replace("'", "''")
        $safeLib = $LibraryName.Replace("'", "''")
        $safeFolder = $TargetFolder.Replace("'", "''")
        $safeOverride = if ($OverwritePermissions) { 1 } else { 0 }
        $safeTpl = $TemplateId.Replace("'", "''")
        $safeFolderPath = if ($TargetFolderPath) { $TargetFolderPath.Replace("'", "''") } else { "" }
        $date = (Get-Date -Format 'o')

        $query = @"
            INSERT OR REPLACE INTO sp_deploy_configs 
            (ConfigName, SiteUrl, LibraryName, TargetFolder, OverwritePermissions, TemplateId, DateModified, TargetFolderPath) 
            VALUES 
            ('$safeName', '$safeUrl', '$safeLib', '$safeFolder', $safeOverride, '$safeTpl', '$date', '$safeFolderPath');
"@
        
        Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $query -ErrorAction Stop
        return $true
    }
    catch {
        throw "Erreur sauvegarde config : $($_.Exception.Message)"
    }
}
