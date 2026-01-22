# Modules/Database/Functions/Remove-AppScriptSecurityGroup.ps1

<#
.SYNOPSIS
    Retire l'autorisation d'un groupe AD pour un script donné.
#>
function Remove-AppScriptSecurityGroup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$ScriptId,
        [Parameter(Mandatory)] [string]$ADGroup
    )

    # v3.1 Sanitization SQL
    try {
        $query = "DELETE FROM script_security WHERE ScriptId = @ScriptId AND ADGroup = @ADGroup;"
        $sqlParams = @{
            ScriptId = $ScriptId
            ADGroup  = $ADGroup.Trim()
        }
        
        Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $query -SqlParameters $sqlParams -ErrorAction Stop
        Write-Verbose "Groupe '$ADGroup' retiré du script '$ScriptId'."
        return $true
    }
    catch {
        Write-Warning "Erreur suppression groupe : $($_.Exception.Message)"
        return $false
    }
}