# Modules/Azure/Functions/Get-AppServicePrincipalPermissions.ps1
<#
.SYNOPSIS
    Récupère la liste des permissions configurées (RequiredResourceAccess) et leur statut.
.DESCRIPTION
    1. Lit le manifeste de l'application pour voir ce qui est demandé.
    2. Lit les "Grants" pour voir ce qui est déjà accordé.
    3. Compare les deux pour déterminer le statut.
#>
function Get-AppServicePrincipalPermissions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$AppId
    )

    if (-not $Global:AppAzureAuth.UserAuth.Connected) { return @() }

    try {
        # 1. Récupérer l'objet Application (Manifeste)
        $app = Get-MgApplication -Filter "appId eq '$AppId'" -ErrorAction Stop | Select-Object -First 1
        if (-not $app) { return @() }

        # 2. Récupérer les permissions effectivement accordées (Grants)
        $sp = Get-MgServicePrincipal -Filter "appId eq '$AppId'" -ErrorAction Stop | Select-Object -First 1
        $grantedScopes = @()
        if ($sp) {
            $grants = Get-MgOauth2PermissionGrant -Filter "clientId eq '$($sp.Id)'" -ErrorAction SilentlyContinue
            if ($grants) {
                $grantedScopes = ($grants.Scope -split ' ') | ForEach-Object { $_.Trim() }
            }
        }

        # 3. Récupérer le ServicePrincipal de Microsoft Graph pour la traduction GUID -> Nom
        # ID fixe de l'API Graph : 00000003-0000-0000-c000-000000000000
        $graphApi = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'" -ErrorAction Stop | Select-Object -First 1
        
        # Créer une hashtable pour la traduction rapide : ID -> Value (Nom)
        $scopeMap = @{}
        if ($graphApi.Oauth2PermissionScopes) {
            foreach ($s in $graphApi.Oauth2PermissionScopes) {
                $scopeMap[$s.Id.ToString()] = $s.Value
            }
        }

        $finalList = @()

        # 4. Parcourir les permissions requises (Manifeste)
        foreach ($req in $app.RequiredResourceAccess) {
            # On ne traite que l'API Microsoft Graph pour l'instant
            if ($req.ResourceAppId -eq '00000003-0000-0000-c000-000000000000') {
                foreach ($access in $req.ResourceAccess) {
                    if ($access.Type -eq "Scope") { # Scope = Délégué
                        $idStr = $access.Id.ToString()
                        $name = if ($scopeMap.ContainsKey($idStr)) { $scopeMap[$idStr] } else { $idStr }
                        
                        # Déterminer le statut
                        $status = "Pending" # Par défaut
                        if ($grantedScopes -contains $name) {
                            $status = "Granted"
                        }

                        $finalList += [PSCustomObject]@{
                            Name = $name
                            Status = $status
                        }
                    }
                }
            }
        }

        return $finalList | Sort-Object Name
    }
    catch {
        Write-Warning "Erreur lecture permissions : $($_.Exception.Message)"
        return @()
    }
}