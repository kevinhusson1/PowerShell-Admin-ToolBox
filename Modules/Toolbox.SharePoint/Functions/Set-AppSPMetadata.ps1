function Set-AppSPMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$List,
        [Parameter(Mandatory)] [int]$ItemId,
        [Parameter(Mandatory)] [hashtable]$Values, # @{ "Client"="Total"; "Annee"="2024" }
        [Parameter(Mandatory=$false)] $Connection
    )

    try {
        Write-Verbose "Mise à jour métadonnées item $ItemId..."
        
        $params = @{ List = $List; Identity = $ItemId; Values = $Values; ErrorAction = "Stop" }
        if ($Connection) { $params.Connection = $Connection }

        Set-PnPListItem @params | Out-Null
        return $true
    }
    catch {
        throw "Erreur métadonnées : $($_.Exception.Message)"
    }
}