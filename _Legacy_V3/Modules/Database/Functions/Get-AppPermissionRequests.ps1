# Modules/Database/Functions/Get-AppPermissionRequests.ps1

<#
.SYNOPSIS
    Récupère les demandes de permissions depuis la base de données.
.DESCRIPTION
    Interroge la table 'permission_requests'. Par défaut, retourne les demandes 'Pending'.
.PARAMETER Status
    Le statut des demandes à récupérer ('Pending', 'Approved', 'Rejected' ou 'All').
#>
function Get-AppPermissionRequests {
    [CmdletBinding()]
    param(
        [ValidateSet('Pending', 'Approved', 'Rejected', 'All')]
        [string]$Status = 'Pending'
    )

    try {
        $query = "SELECT * FROM permission_requests"
        if ($Status -ne 'All') {
            $query += " WHERE Status = '$Status'"
        }
        $query += " ORDER BY RequestID DESC;"

        return Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $query -ErrorAction Stop
    }
    catch {
        Write-Warning "Impossible de récupérer les demandes de permissions : $($_.Exception.Message)"
        return @()
    }
}