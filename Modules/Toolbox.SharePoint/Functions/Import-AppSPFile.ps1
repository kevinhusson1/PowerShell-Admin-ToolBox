<#
.SYNOPSIS
    Importe un fichier depuis une URL (SharePoint ou Web) vers une bibliothèque SharePoint cible.

.DESCRIPTION
    Cette fonction gère intelligemment le téléchargement de la source :
    1. Si l'URL est une URL SharePoint du même tenant, elle tente de se connecter (Auth Certificat) pour télécharger le fichier via PnP.
    2. Sinon, elle utilise une requête Web standard.
    
    Ensuite, elle upload le fichier vers la cible définie par la connexion PnP fournie.

.PARAMETER SourceUrl
    L'URL du fichier source.
    
.PARAMETER TargetConnection
    La connexion PnP vers le site CIBLE où le fichier doit être déposé.

.PARAMETER TargetFolderServerRelativeUrl
    L'URL relative du dossier de destination (ex: /sites/MonSite/MaLib/MonDossier).

.PARAMETER TargetFileName
    Le nom final du fichier.

.PARAMETER ClientId
    (Optionnel) ID Client pour l'authentification sur le site SOURCE (si SharePoint).

.PARAMETER Thumbprint
    (Optionnel) Thumbprint pour l'authentification sur le site SOURCE (si SharePoint).

.PARAMETER TenantName
    (Optionnel) Nom du tenant (ex: contoso.onmicrosoft.com).

.OUTPUTS
    [PnP.PowerShell.Commands.Model.SharePoint.File] Le fichier créé sur la cible.
#>
function Import-AppSPFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$SourceUrl,
        [Parameter(Mandatory)] [PnP.PowerShell.Commands.Base.PnPConnection]$TargetConnection,
        [Parameter(Mandatory)] [string]$TargetFolderServerRelativeUrl,
        [Parameter(Mandatory)] [string]$TargetFileName,
        [Parameter(Mandatory = $false)] [string]$ClientId,
        [Parameter(Mandatory = $false)] [string]$Thumbprint,
        [Parameter(Mandatory = $false)] [string]$TenantName
    )

    function Log-Msg {
        param($Msg, $Level = "Info")
        if (Get-Command "Write-AppLog" -ErrorAction SilentlyContinue) {
            Write-AppLog -Message $Msg -Level $Level
        }
        else {
            $color = switch ($Level) { "Error" { "Red" } "Warning" { "Yellow" } "Debug" { "Gray" } Default { "Cyan" } }
            Write-Host "[$Level] $Msg" -ForegroundColor $color
        }
    }

    $tempPath = [System.IO.Path]::GetTempFileName()
    $downloaded = $false

    try {
        Log-Msg -Msg "Import-AppSPFile : Début traitement pour '$TargetFileName'" -Level Info

        # 1. ANALYSE SOURCE : EST-CE DU SHAREPOINT INTERNE ?
        $isSharePoint = $false
        if ($TenantName -and $SourceUrl -match $TenantName.Split('.')[0]) {
            $isSharePoint = $true
        }
        # Ou détection générique sur 'sharepoint.com'
        if ($SourceUrl -match "sharepoint\.com") {
            $isSharePoint = $true
        }

        # 2. STRATÉGIE DE TÉLÉCHARGEMENT
        if ($isSharePoint -and $ClientId -and $Thumbprint -and $TenantName) {
            Log-Msg -Msg "  Detected SharePoint URL internally. Attempting Authenticated Download..." -Level Debug
            
            try {
                # A. Extraction du Site Source
                # Format: https://tenant.sharepoint.com/sites/SiteName/...
                # Regex un peu loose pour capturer /sites/XXXX
                if ($SourceUrl -match "/sites/([^/]+)") {
                    $siteName = $Matches[1]
                    $origin = [System.Uri]$SourceUrl
                    # Reconstitution URL site source
                    # Attention aux managed paths, mais /sites/ est le standard 99%
                    $sourceSiteUrl = "$($origin.Scheme)://$($origin.Host)/sites/$siteName"
                    $cleanTenant = $TenantName -replace "\.onmicrosoft\.com$", "" -replace "\.sharepoint\.com$", ""

                    Log-Msg -Msg "  Source Site identified: $sourceSiteUrl" -Level Debug
                    
                    # B. Connexion Source
                    $sourceConn = Connect-PnPOnline -Url $sourceSiteUrl -ClientId $ClientId -Thumbprint $Thumbprint -Tenant "$cleanTenant.onmicrosoft.com" -ReturnConnection -ErrorAction Stop
                    
                    # C. Nettoyage URL pour Get-PnPFile
                    # Les liens de partage du type /:w:/r/ cassent Get-PnPFile qui attend un ServerRelativeUrl ou un path propre.
                    # On va essayer de transformer l'URL.
                    # Ex: https://.../:w:/r/sites/TEST_PNP/Shared%20Documents/Item.docx?d=...
                    # On veut : /sites/TEST_PNP/Shared Documents/Item.docx
                    
                    $cleanUrl = $SourceUrl
                    # 1. Retirer Query Params
                    if ($cleanUrl.Contains("?")) { $cleanUrl = $cleanUrl.Split('?')[0] }
                    
                    # 2. Retirer les segments "magiques" de sharing (:w:, :x:, :r:)
                    # On assume que le path réel commence après /sites/ dans la plupart des cas
                    # Mais l'URL absolue contient /sites/.
                    
                    # On va extraire le path via URI
                    $uriObj = [System.Uri]$cleanUrl
                    $pathAndQuery = $uriObj.AbsolutePath # /:w:/r/sites/TEST_PNP/...
                    
                    # Nettoyage barbare mais efficace pour les liens générés par O365
                    $pathAndQuery = $pathAndQuery -replace "/:[a-z]:/r", "" 
                    $pathAndQuery = $pathAndQuery -replace "/:[a-z]:", ""
                    
                    # Decode URL (pour les %20)
                    $serverRelUrl = [System.Web.HttpUtility]::UrlDecode($pathAndQuery)
                    
                    Log-Msg -Msg "  Attempting PnP Download from: $serverRelUrl" -Level Debug
                    
                    # RECTIFICATION : Get-PnPFile -AsFile ...
                    # -Path : Local folder where the file is to be saved
                    # -Filename : Name of the file locally
                    
                    # Donc on supprime le temp file placeholder
                    Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
                    $tempDir = [System.IO.Path]::GetTempPath()
                    # On utilise un GUID pour éviter les collisions
                    $guidName = [Guid]::NewGuid().ToString() + "_" + $TargetFileName
                    
                    Get-PnPFile -Url $serverRelUrl -AsFile -Path $tempDir -Filename $guidName -Connection $sourceConn -ErrorAction Stop | Out-Null
                    
                    $downloadedPath = Join-Path $tempDir $guidName
                    if (Test-Path $downloadedPath) {
                        # On déplace vers le tempPath original pour garder la logique du script
                        Move-Item -Path $downloadedPath -Destination $tempPath -Force
                        $downloaded = $true
                        Log-Msg -Msg "  Authenticated download successful." -Level Debug
                    }
                }
            }
            catch {
                Log-Msg -Msg "  Authenticated download failed: $($_.Exception.Message). Falling back to WebRequest." -Level Warning
            }
        }

        # 3. FALLBACK : WEB REQUEST
        if (-not $downloaded) {
            Log-Msg -Msg "  Downloading via Invoke-WebRequest..." -Level Debug
            # UserAgent pour éviter certains blocages basiques
            Invoke-WebRequest -Uri $SourceUrl -OutFile $tempPath -UserAgent "PowerShell/SharePointBuilder" -ErrorAction Stop
            $downloaded = $true
        }

        # 4. UPLOAD CIBLE
        if ($downloaded -and (Test-Path $tempPath)) {
            Log-Msg -Msg "  Uploading to Target ($TargetFolderServerRelativeUrl)..." -Level Debug
            
            $fs = [System.IO.File]::OpenRead($tempPath)
            try {
                $uploadedFile = Add-PnPFile -FileName $TargetFileName -Folder $TargetFolderServerRelativeUrl -Stream $fs -Connection $TargetConnection -ErrorAction Stop
                Log-Msg -Msg "  Upload successful." -Level Info
                return $uploadedFile
            }
            finally {
                $fs.Close()
                $fs.Dispose()
            }
        }
        else {
            throw "File could not be downloaded."
        }
    }
    catch {
        Log-Msg -Msg "  ❌ ERROR Import-AppSPFile: $($_.Exception.Message)" -Level Error
        throw $_
    }
    finally {
        if (Test-Path $tempPath) { Remove-Item $tempPath -Force -ErrorAction SilentlyContinue }
    }
}
