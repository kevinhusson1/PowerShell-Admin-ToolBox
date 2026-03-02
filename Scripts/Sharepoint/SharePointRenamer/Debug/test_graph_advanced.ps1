$ErrorActionPreference = "Stop"

try {
    $mgAuthModule = Get-Module Microsoft.Graph.Authentication -ListAvailable | Select-Object -First 1
    if (-not $mgAuthModule) { throw "Module Microsoft.Graph.Authentication introuvable" }

    # On charge *toutes* les bibliothèques lourdes liées à l'authentification dans le bon ordre de dépendance
    $dllsToLoad = @(
        "Azure.Core.dll",
        "Microsoft.Identity.Client.dll",
        "Microsoft.Identity.Client.Extensions.Msal.dll",
        "Azure.Identity.dll",
        "Microsoft.Kiota.Authentication.Azure.dll",
        "Microsoft.Graph.Core.dll",
        "Microsoft.Graph.Authentication.dll"
    )

    foreach ($dllName in $dllsToLoad) {
        $dllPath = Get-ChildItem -Path $mgAuthModule.ModuleBase -Recurse -Filter $dllName | Select-Object -First 1
        if ($dllPath) {
            Write-Host "Forçage de $($dllPath.Name)..."
            try {
                Add-Type -Path $dllPath.FullName -ErrorAction Stop
                Write-Host " -> Succès!"
            }
            catch {
                Write-Host " -> ERREUR: $($_.Exception.Message)"
                Write-Host " -> Inner: $($_.Exception.InnerException.Message)"
                Write-Host " -> LoaderExceptions:"
                if ($_.Exception.InnerException.LoaderExceptions) {
                    $_.Exception.InnerException.LoaderExceptions | ForEach-Object { Write-Host "    - $($_.Message)" }
                }
            }
        }
        else {
            Write-Host "Introuvable : $dllName"
        }
    }

    Write-Host "Chargement PnP..."
    Import-Module PnP.PowerShell

    Write-Host "Test de connexion MSAL simulée..."
    # Devrait retourner l'invite Microsoft, ou planter parce qu'on ne fournit pas de Tenant correct. 
    # Mieux vaut fournir un TenantId volontairement faux pour valider QUE c'est bien l'erreur MSAL "normale" qui s'affiche, et pas l'erreur de Type non trouvé
    Connect-MgGraph -ClientId 'dummy' -TenantId 'dummy' -ErrorAction Stop
}
catch {
    Write-Error $_
}
