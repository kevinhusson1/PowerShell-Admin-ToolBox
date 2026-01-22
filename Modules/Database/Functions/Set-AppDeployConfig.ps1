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
        # Sécurisation SQL (v3.1)
        $safeOverride = if ($OverwritePermissions) { 1 } else { 0 }
        $safeFolderPath = if ($TargetFolderPath) { $TargetFolderPath } else { "" }
        $safeRoles = if ($AuthorizedRoles) { $AuthorizedRoles } else { "" }
        $date = (Get-Date -Format 'o')

        $query = @"
            INSERT OR REPLACE INTO sp_deploy_configs 
            (ConfigName, SiteUrl, LibraryName, TargetFolder, OverwritePermissions, TemplateId, DateModified, TargetFolderPath, AuthorizedRoles) 
            VALUES 
            (@ConfigName, @SiteUrl, @LibraryName, @TargetFolder, @OverwritePermissions, @TemplateId, @DateModified, @TargetFolderPath, @AuthorizedRoles);
"@
        
        $sqlParams = @{
            ConfigName           = $ConfigName
            SiteUrl              = $SiteUrl
            LibraryName          = $LibraryName
            TargetFolder         = $TargetFolder
            OverwritePermissions = $safeOverride
            TemplateId           = $TemplateId
            DateModified         = $date
            TargetFolderPath     = $safeFolderPath
            AuthorizedRoles      = $safeRoles
        }

        Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $query -SqlParameters $sqlParams -ErrorAction Stop
        return $true
    }
    catch {
        throw "Erreur sauvegarde config : $($_.Exception.Message)"
    }
}
