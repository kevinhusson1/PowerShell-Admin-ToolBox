$ErrorActionPreference = "Stop"
try {
    $m = Get-Module Microsoft.Graph.Authentication -ListAvailable | Select-Object -First 1
    if (-not $m) { throw "Module introuvable" }
    
    $dll = Get-ChildItem -Path $m.ModuleBase -Recurse -Filter "Microsoft.Graph.Core.dll" | Select-Object -First 1
    if ($dll) {
        Write-Host "Chargement de $($dll.FullName)"
        Add-Type -Path $dll.FullName
        Write-Host "DLL Chargée !"
    }
    else {
        Write-Warning "DLL introuvable !"
    }

    Import-Module PnP.PowerShell
    Write-Host "PnP Chargé. Test Connect-MgGraph..."
    
    # Doit échouer avec une erreur d'auth, pas une erreur de chargement de type
    Connect-MgGraph -ClientId 'dummy' -TenantId 'dummy' -ErrorAction Stop
}
catch {
    Write-Error $_
}
