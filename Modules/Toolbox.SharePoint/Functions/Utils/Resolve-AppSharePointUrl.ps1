function Resolve-AppSharePointUrl {
    <#
    .SYNOPSIS
        Analyse une URL SharePoint (Lien navigateur, Lien partage, etc.) pour extraire le Site et le Chemin relatif.

    .DESCRIPTION
        Gère les cas :
        - Lien direct : https://contoso.sharepoint.com/sites/Demo/Docs/Folder
        - Lien vue avec ID : https://.../Forms/AllItems.aspx?id=%2Fsites%2F...
        - Lien de partage : https://.../:f:/r/sites/...

    .PARAMETER Url
        L'URL brute fournie par l'utilisateur.

    .OUTPUTS
        [PSCustomObject] @{ SiteUrl, ServerRelativeUrl, IsValid, Error }
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Url
    )

    $result = [PSCustomObject]@{
        IsValid           = $false
        SiteUrl           = $null
        ServerRelativeUrl = $null
        WebUrl            = $null
        Error             = $null
    }

    if ([string]::IsNullOrWhiteSpace($Url)) {
        $result.Error = "URL vide."
        return $result
    }

    try {
        $uri = [Uri]$Url
        $authority = $uri.Authority # tenant.sharepoint.com
        $scheme = $uri.Scheme
        $path = $uri.AbsolutePath
        $query = $uri.Query

        # 1. CAS: QUERY PARAM ID (Vue classique)
        # Ex: .../Forms/test.aspx?id=%2Fsites%2FTEST_PNP%2FDocs%2FTOTO
        if ($query -match "id=([^&]+)") {
            $decodedId = [System.Web.HttpUtility]::UrlDecode($matches[1])
            $result.ServerRelativeUrl = $decodedId
            
            # Reconstruction SiteUrl (Approximation: on prend le segment /sites/NomSite)
            if ($decodedId -match "^/sites/([^/]+)") {
                $siteName = $matches[1]
                $result.SiteUrl = "${scheme}://${authority}/sites/$siteName"
            }
            else {
                # Cas racine ou incertain, on tente de garder la base
                $result.SiteUrl = "${scheme}://${authority}"
            }
            $result.IsValid = $true
            return $result
        }

        # 2. CAS: SHARING LINK (:f:/r/ ou :f:/s/)
        # Ex: /:f:/r/sites/TEST_PNP/Docs/Folder
        if ($path -match "/:[fx]:/[rs]/(.+)") {
            $realPath = "/" + $matches[1]
            $result.ServerRelativeUrl = $realPath
             
            if ($realPath -match "^/sites/([^/]+)") {
                $siteName = $matches[1]
                $result.SiteUrl = "${scheme}://${authority}/sites/$siteName"
            }
            $result.IsValid = $true
            return $result
        }

        # 3. CAS: LIEN DIRECT (Standard)
        # Ex: /sites/TEST_PNP/Docs/Folder
        # On doit distinguer si c'est une Page (.aspx) ou un Dossier
        if ($path.EndsWith(".aspx")) {
            # C'est probablement la vue racine d'une librairie
            # On recule d'un niveau
            $parentPath = [System.IO.Path]::GetDirectoryName($path).Replace("\", "/")
            # Souvent AllItems.aspx est dans /Forms/, donc on remonte encore
            if ($parentPath.EndsWith("/Forms")) {
                $parentPath = [System.IO.Path]::GetDirectoryName($parentPath).Replace("\", "/")
            }
            $result.ServerRelativeUrl = $parentPath
        }
        else {
            $result.ServerRelativeUrl = $path
        }

        # Extraction SiteUrl
        if ($result.ServerRelativeUrl -match "^/sites/([^/]+)") {
            $siteName = $matches[1]
            $result.SiteUrl = "${scheme}://${authority}/sites/$siteName"
        }
        else {
            $result.SiteUrl = "${scheme}://${authority}"
        }

        $result.IsValid = $true

    }
    catch {
        $result.Error = "Erreur parsing: $($_.Exception.Message)"
    }

    return $result
}
