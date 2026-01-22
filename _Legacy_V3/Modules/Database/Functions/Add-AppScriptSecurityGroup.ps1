# Modules/Database/Functions/Add-AppScriptSecurityGroup.ps1

<#
.SYNOPSIS
    Autorise un nouveau groupe AD pour un script donné.
#>
function Add-AppScriptSecurityGroup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$ScriptId,
        [Parameter(Mandatory)] [string]$ADGroup
    )

    # v3.1 Sanitization SQL
    try {
        # INSERT OR IGNORE évite les doublons si on clique deux fois
        $query = "INSERT OR IGNORE INTO script_security (ScriptId, ADGroup) VALUES (@ScriptId, @ADGroup);"
        $sqlParams = @{
            ScriptId = $ScriptId
            ADGroup  = $ADGroup.Trim()
        }
        
        Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $query -SqlParameters $sqlParams -ErrorAction Stop
        Write-Verbose "Groupe '$ADGroup' ajouté au script '$ScriptId'."
        return $true
    }
    catch {
        Write-Warning "Erreur ajout groupe : $($_.Exception.Message)"
        return $false
    }
}