function Set-AppSPPermission {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$List,      # Nom de la bibliothèque
        [Parameter(Mandatory)] [int]$ItemId,       # ID de l'item (Dossier/Fichier)
        [Parameter(Mandatory)] [string]$UserUpn,   # Email utilisateur ou Nom Groupe
        [Parameter(Mandatory)] [string]$Role,      # Read, Contribute, Full Control
        [switch]$ClearExisting,                    # Pour casser l'héritage
        [Parameter(Mandatory=$false)] $Connection
    )

    try {
        $params = @{ List = $List; Identity = $ItemId; ErrorAction = "Stop" }
        if ($Connection) { $params.Connection = $Connection }

        # 1. Casser l'héritage si demandé
        if ($ClearExisting) {
            Write-Verbose "Rupture d'héritage sur l'item $ItemId..."
            Set-PnPListItemPermission @params -BreakRoleInheritance -CopyRoleAssignments:$false | Out-Null
        }

        # 2. Ajouter la permission
        Write-Verbose "Ajout permission '$Role' pour '$UserUpn'..."
        Set-PnPListItemPermission @params -User $UserUpn -AddRole $Role | Out-Null
        
        return $true
    }
    catch {
        throw "Erreur permission ($UserUpn -> $Role) : $($_.Exception.Message)"
    }
}