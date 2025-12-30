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
        [string]$TargetFolderPath,
        [string]$AuthorizedRoles
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
        $safeRoles = if ($AuthorizedRoles) { $AuthorizedRoles.Replace("'", "''") } else { "" }
        $date = (Get-Date -Format 'o')

        $query = @"
            INSERT OR REPLACE INTO sp_deploy_configs 
            (ConfigName, SiteUrl, LibraryName, TargetFolder, OverwritePermissions, TemplateId, DateModified, TargetFolderPath, AuthorizedRoles) 
            VALUES 
            ('$safeName', '$safeUrl', '$safeLib', '$safeFolder', $safeOverride, '$safeTpl', '$date', '$safeFolderPath', '$safeRoles');
"@
        
        Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $query -ErrorAction Stop
        return $true
    }
    catch {
        throw "Erreur sauvegarde config : $($_.Exception.Message)"
    }
}
