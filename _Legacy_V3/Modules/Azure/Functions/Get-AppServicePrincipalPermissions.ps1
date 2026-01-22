# Modules/Azure/Functions/Get-AppServicePrincipalPermissions.ps1

<#
.SYNOPSIS
    Récupère la liste des permissions configurées et vérifie leur consentement réel (Admin Consent).
.DESCRIPTION
    1. Lit le manifeste de l'application pour voir ce qui est demandé (RequiredResourceAccess).
    2. Traduit les GUIDs demandés en noms lisibles (ex: Sites.Read.All) via le ServicePrincipal de MS Graph.
    3. Interroge les 'OAuth2PermissionGrants' pour voir ce qui a été *réellement* consenti par un admin.
#>
function Get-AppServicePrincipalPermissions {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string]$AppId)

    if (-not $Global:AppAzureAuth.UserAuth.Connected) { return @() }

    try {
        $app = Get-MgApplication -Filter "appId eq '$AppId'" -ErrorAction Stop | Select-Object -First 1
        if (-not $app) { return @() }

        $sp = Get-MgServicePrincipal -Filter "appId eq '$AppId'" -ErrorAction Stop | Select-Object -First 1
        if (-not $sp) { return @() }

        $graphApiSp = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'" -ErrorAction Stop | Select-Object -First 1
        
        $scopeInfo = @{}
        if ($graphApiSp.Oauth2PermissionScopes) {
            foreach ($s in $graphApiSp.Oauth2PermissionScopes) {
                $scopeInfo[$s.Id.ToString()] = @{ Name = $s.Value; Type = $s.Type; Desc = $s.AdminConsentDescription }
            }
        }

        $grants = Get-MgOauth2PermissionGrant -Filter "clientId eq '$($sp.Id)' and resourceId eq '$($graphApiSp.Id)'" -ErrorAction SilentlyContinue
        $grantedScopesList = @()
        if ($grants) {
            foreach ($grant in $grants) {
                $scopes = $grant.Scope -split " "
                foreach ($s in $scopes) { if (-not [string]::IsNullOrWhiteSpace($s)) { $grantedScopesList += $s.ToLower().Trim() } }
            }
        }

        $finalList = @()
        foreach ($req in $app.RequiredResourceAccess) {
            if ($req.ResourceAppId -eq $graphApiSp.AppId) {
                foreach ($access in $req.ResourceAccess) {
                    if ($access.Type -eq "Scope") {
                        $idStr = $access.Id.ToString()
                        $info = $scopeInfo[$idStr]
                        $name = if ($info) { $info.Name } else { $idStr }
                        $consentType = if ($info) { $info.Type } else { "Unknown" }
                        $desc = if ($info) { $info.Desc } else { "" }

                        $status = "Pending"
                        if ($grantedScopesList -contains $name.ToLower().Trim()) { $status = "Granted" }

                        $finalList += [PSCustomObject]@{ Name = $name; Status = $status; Id = $idStr; ConsentType = $consentType; Description = $desc }
                    }
                }
            }
        }
        return $finalList | Sort-Object Name
    }
    catch { return @() }
}