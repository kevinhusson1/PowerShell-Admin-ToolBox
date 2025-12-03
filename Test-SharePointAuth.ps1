# Test-Module-SharePoint.ps1
# À exécuter pour valider les briques élémentaires

$Global:AppConfig = @{
    azure = @{
        tenantName = "vosgelis365.onmicrosoft.com" # Remplacer ici pour le test
        certThumbprint = "d25a39acc63bc2f3f1b6389568e9b5aa3726969d"
        authentication = @{ userAuth = @{ appId = "0107cfb1-a2e6-4394-b363-d25930adf7e4" } }
    }
}

Import-Module ".\Modules\Toolbox.SharePoint" -Force

try {
    Write-Host "1. Test Connexion..." -ForegroundColor Cyan
    $conn = Connect-AppSharePoint -ClientId $Global:AppConfig.azure.authentication.userAuth.appId `
                                  -Thumbprint $Global:AppConfig.azure.certThumbprint `
                                  -TenantName $Global:AppConfig.azure.tenantName
    Write-Host "   OK." -ForegroundColor Green

    Write-Host "2. Recherche Sites ('test')..." -ForegroundColor Cyan
    $sites = Get-AppSPSites -Filter "TEST_PNP" -Connection $conn
    Write-Host "   Trouvé : $($sites.Count) sites." -ForegroundColor Green

    if ($sites.Count -gt 0) {
        $targetSite = $sites[0]
        Write-Host "   Cible pour test : $($targetSite.Url)" -ForegroundColor Yellow
        
        # Reconnexion sur le site spécifique
        $siteConn = Connect-AppSharePoint -ClientId $Global:AppConfig.azure.authentication.userAuth.appId `
                                          -Thumbprint $Global:AppConfig.azure.certThumbprint `
                                          -TenantName $Global:AppConfig.azure.tenantName `
                                          -SiteUrl $targetSite.Url

        Write-Host "3. Création Dossier..." -ForegroundColor Cyan
        # On récupère l'objet dossier créé
        $folderObj = New-AppSPFolder -SiteRelativePath "/Shared Documents/Test_Toolbox" -Connection $siteConn
        Write-Host "   OK : $($folderObj.ServerRelativeUrl)" -ForegroundColor Green

        Write-Host "4. Upload Fichier..." -ForegroundColor Cyan
        $testFile = "$env:TEMP\test_upload.txt"
        "Hello SharePoint" | Set-Content $testFile
        
        # Ma nouvelle fonction Add-AppSPFile gère maintenant le chemin relatif "/Shared Documents..."
        # Mais on pourrait aussi passer directement $folderObj.ServerRelativeUrl
        Add-AppSPFile -LocalPath $testFile -Folder "/Shared Documents/Test_Toolbox" -Connection $siteConn
        
        Write-Host "   OK." -ForegroundColor Green
    }

} catch {
    Write-Host "ERREUR : $_" -ForegroundColor Red
}