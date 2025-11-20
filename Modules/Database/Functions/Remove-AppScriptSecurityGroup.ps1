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

    $safeId = $ScriptId.Replace("'", "''")
    $safeGroup = $ADGroup.Trim().Replace("'", "''")

    try {
        $query = "DELETE FROM script_security WHERE ScriptId = '$safeId' AND ADGroup = '$safeGroup';"
        Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $query -ErrorAction Stop
        Write-Verbose "Groupe '$ADGroup' retiré du script '$ScriptId'."
        return $true
    }
    catch {
        Write-Warning "Erreur suppression groupe : $($_.Exception.Message)"
        return $false
    }
}