# Modules/Azure/Functions/Add-AppGraphPermission.ps1

<#
.SYNOPSIS
    Ajoute une permission déléguée (Scope) à l'application Azure AD.
.DESCRIPTION
    1. Recherche l'ID de l'API Microsoft Graph.
    2. Traduit le nom du scope (ex: "Mail.Read") en GUID.
    3. Met à jour l'objet Application dans Azure avec la nouvelle ressource requise.
.PARAMETER AppId
    L'ID Client de l'application à modifier.
.PARAMETER ScopeName
    Le nom de la permission à ajouter (ex: "Files.Read").
#>
function Add-AppGraphPermission {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$AppId,
        [Parameter(Mandatory)] [string]$ScopeName
    )

    if (-not $Global:AppAzureAuth.UserAuth.Connected) { throw "Non connecté." }

    try {
        Write-Verbose "Début de l'ajout de la permission '$ScopeName' pour l'AppId '$AppId'..."

        # 1. Récupérer l'objet Application cible
        $targetApp = Get-MgApplication -Filter "appId eq '$AppId'" -ErrorAction Stop | Select-Object -First 1
        if (-not $targetApp) { throw "Application cible introuvable." }

        # 2. Récupérer le ServicePrincipal de "Microsoft Graph" (L'API qui détient les permissions)
        # L'AppId de Microsoft Graph est toujours '00000003-0000-0000-c000-000000000000'
        $graphSP = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'" -ErrorAction Stop | Select-Object -First 1
        
        # 3. Trouver le GUID correspondant au nom du Scope (ex: Mail.Read -> 570282fd-fa5c-430d-a7fd-fc8dc98a9dca)
        $permissionRole = $graphSP.Oauth2PermissionScopes | Where-Object { $_.Value -eq $ScopeName }
        
        if (-not $permissionRole) {
            throw "La permission '$ScopeName' n'existe pas dans l'API Microsoft Graph. Vérifiez l'orthographe."
        }
        $scopeId = $permissionRole.Id
        Write-Verbose "GUID trouvé pour '$ScopeName' : $scopeId"

        # 4. Préparer la mise à jour du RequiredResourceAccess
        # On doit récupérer l'existant pour ne pas l'écraser
        $currentResourceAccess = @($targetApp.RequiredResourceAccess)
        
        # On cherche si on a déjà des droits sur Microsoft Graph dans l'app
        $graphResource = $currentResourceAccess | Where-Object { $_.ResourceAppId -eq $graphSP.AppId }

        if ($graphResource) {
            # On ajoute le nouveau scope à la liste existante
            $newAccessList = [System.Collections.Generic.List[Microsoft.Graph.PowerShell.Models.IMicrosoftGraphResourceAccess]]::new()
            foreach ($access in $graphResource.ResourceAccess) {
                $newAccessList.Add($access)
            }
            
            # Vérifier si déjà présent
            if (-not ($newAccessList | Where-Object { $_.Id -eq $scopeId })) {
                $newAccess = @{ Id = $scopeId; Type = "Scope" } # Type Scope = Délégué
                $newAccessList.Add($newAccess)
                $graphResource.ResourceAccess = $newAccessList
            } else {
                Write-Verbose "La permission est déjà présente."
                return $true
            }
        } else {
            # Création d'une nouvelle entrée pour Graph si elle n'existait pas (peu probable ici)
            $newResource = @{
                ResourceAppId = $graphSP.AppId
                ResourceAccess = @(@{ Id = $scopeId; Type = "Scope" })
            }
            $currentResourceAccess += $newResource
        }

        # 5. Appliquer la mise à jour
        Update-MgApplication -ApplicationId $targetApp.Id -RequiredResourceAccess $currentResourceAccess -ErrorAction Stop
        
        Write-Verbose "Application Azure mise à jour avec succès."
        return $true
    }
    catch {
        throw "Erreur lors de l'ajout de la permission : $($_.Exception.Message)"
    }
}