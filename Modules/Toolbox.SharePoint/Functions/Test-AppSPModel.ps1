<#
.SYNOPSIS
    Valide l'intégrité d'un modèle de structure SharePoint avant déploiement.

.DESCRIPTION
    Effectue une validation à 3 niveaux :
    1. Statique : Syntaxe, caractères interdits, longueurs.
    2. Connectée : Existence de la bibliothèque cible et des utilisateurs (Permissions).
    3. Métadonnées : Existence des colonnes (Tags) sur la cible.

.PARAMETER StructureData
    L'objet ou tableau représentant la structure à valider.

.PARAMETER Connection
    (Optionnel) La connexion PnP active pour les vérifications connectées.

.PARAMETER TargetLibraryName
    (Optionnel) Le nom de la bibliothèque cible.

.OUTPUTS
    [List[PSCustomObject]] Une liste d'erreurs/warnings.
#>
function Test-AppSPModel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object]$StructureData,
        [Parameter(Mandatory = $false)] [string]$TargetLibraryName,
        [Parameter(Mandatory = $false)] [string]$SiteId,
        [Parameter(Mandatory = $false)] [string]$DriveId
    )

    $results = [System.Collections.Generic.List[psobject]]::new()

    # Liste caractères interdits SharePoint (Folders)
    $forbiddenChars = '[~"#%&*:<>?/\\{|}]'
    
    # Helper Localisation Safe
    function Loc($key, $fArgs) {
        if (Get-Command "Get-AppLocalizedString" -ErrorAction SilentlyContinue) {
            $s = Get-AppLocalizedString -Key ("sp_builder." + $key)
            if ($s.StartsWith("MISSING:")) { return $key }
            if ($null -ne $fArgs) { return $s -f $fArgs }
            return $s
        }
        return $key 
    }

    # --- LEVEL 2 : Validation Connectée (Graph) ---
    $knownFields = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    
    if ($SiteId -and $DriveId) {
        # B. Validation des colonnes (Tags) via Graph
        try {
            # On récupère la liste liée au drive pour avoir les colonnes
            $listReq = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$SiteId/drives/$DriveId/list?`$select=id" -ErrorAction Stop
            $listId = $listReq.id
            
            $fieldsReq = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$SiteId/lists/$listId/columns?`$select=name,displayName" -ErrorAction Stop
            if ($fieldsReq.value) {
                foreach ($f in $fieldsReq.value) {
                    $knownFields.Add($f.name) | Out-Null
                    $knownFields.Add($f.displayName) | Out-Null
                }
            }
        }
        catch {
            Write-Verbose "[Test-AppSPModel] Impossible de récupérer les colonnes pour validation : $($_.Exception.Message)"
        }
    }

    function Test-Url($u) {
        if ([string]::IsNullOrWhiteSpace($u)) { return $false }
        try { [void][System.Uri]::new($u); return $true } catch { return $false }
    }

    function Test-UrlReachability($u) {
        if ([string]::IsNullOrWhiteSpace($u)) { return $true }
        try {
            $req = Invoke-WebRequest -Uri $u -Method Head -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
            return @{ K = $true; C = $req.StatusCode }
        }
        catch {
            try {
                $req = Invoke-WebRequest -Uri $u -Method Get -UseBasicParsing -TimeoutSec 5 -Range 0-10 -ErrorAction Stop
                return @{ K = $true; C = $req.StatusCode }
            }
            catch {
                return @{ K = $false; E = $_.Exception.Message }
            }
        }
    }

    function Validate-Node {
        param($node, $path)

        # 1. Validation Nom
        if (-not [string]::IsNullOrWhiteSpace($node.Name)) {
            if ($node.Name -match $forbiddenChars) {
                $results.Add([PSCustomObject]@{ Id = $node.Id; NodeName = $node.Name; Path = $path; Status = "Error"; Message = (Loc "validation_err_forbidden_chars" $null); Level = "Static" })
            }
            if ($node.Name.Length -gt 128) {
                $results.Add([PSCustomObject]@{ Id = $node.Id; NodeName = $node.Name; Path = $path; Status = "Warning"; Message = (Loc "validation_err_name_length" $null); Level = "Static" })
            }
        }
        else {
            $results.Add([PSCustomObject]@{ Id = $node.Id; NodeName = "???"; Path = $path; Status = "Error"; Message = ((Loc "validation_err_empty_name" $null) + " (Type: $($node.Type), Path: $path)"); Level = "Static" })
        }

        # 2. Validation Types Spécifiques
        if ($node.Type -eq "Publication" -and $node.TargetSiteMode -eq "Url") {
            if (-not (Test-Url $node.TargetSiteUrl)) {
                $results.Add([PSCustomObject]@{ Id = $node.Id; NodeName = $node.Name; Path = $path; Status = "Error"; Message = (Loc "validation_err_invalid_url" $null); Level = "Static" })
            }
            elseif ($SiteId) {
                $st = Test-UrlReachability $node.TargetSiteUrl
                if (-not $st.K) {
                    $results.Add([PSCustomObject]@{ Id = $node.Id; NodeName = $node.Name; Path = $path; Status = "Error"; Message = (Loc "validation_err_url_unreachable" $st.E); Level = "Connected" })
                }
            }
        }
        
        if ($node.Type -eq "Link") {
            if (-not (Test-Url $node.Url)) {
                $results.Add([PSCustomObject]@{ Id = $node.Id; NodeName = $node.Name; Path = $path; Status = "Error"; Message = "URL invalide pour le lien"; Level = "Static" })
            }
            elseif ($SiteId) {
                $st = Test-UrlReachability $node.Url
                if (-not $st.K) {
                    $results.Add([PSCustomObject]@{ Id = $node.Id; NodeName = $node.Name; Path = $path; Status = "Warning"; Message = (Loc "validation_err_url_unreachable" $st.E); Level = "Connected" })
                }
            }
        }
        
        if ($node.Type -eq "File") {
            if ([string]::IsNullOrWhiteSpace($node.SourceUrl)) {
                $results.Add([PSCustomObject]@{ Id = $node.Id; NodeName = $node.Name; Path = $path; Status = "Error"; Message = (Loc "validation_err_file_no_sourceurl" $null); Level = "Static" })
            }
            elseif (-not (Test-Url $node.SourceUrl)) {
                $results.Add([PSCustomObject]@{ Id = $node.Id; NodeName = $node.Name; Path = $path; Status = "Error"; Message = (Loc "validation_err_invalid_source_url" $null); Level = "Static" })
            }
            elseif ($SiteId) {
                $st = Test-UrlReachability $node.SourceUrl
                if (-not $st.K) {
                    $results.Add([PSCustomObject]@{ Id = $node.Id; NodeName = $node.Name; Path = $path; Status = "Error"; Message = (Loc "validation_err_url_unreachable" $st.E); Level = "Connected" })
                }
            }
        }
        
        # 3. Validation Permissions (Graph)
        if ($node.Permissions) {
            foreach ($perm in $node.Permissions) {
                if ([string]::IsNullOrWhiteSpace($perm.Email)) {
                    $results.Add([PSCustomObject]@{ Id = $node.Id; NodeName = $node.Name; Path = $path; Status = "Error"; Message = (Loc "validation_err_perm_no_email" $null); Level = "Static" })
                }
                elseif ($SiteId) {
                    try {
                        $uReq = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$($perm.Email)?`$select=id" -ErrorAction Stop
                    }
                    catch {
                        $results.Add([PSCustomObject]@{ Id = $node.Id; NodeName = $node.Name; Path = $path; Status = "Error"; Message = (Loc "validation_err_perm_user_not_found" $perm.Email); Level = "Connected" })
                    }
                }
            }
        }
        
        # 4. Validation Métadonnées
        if ($node.Tags) {
            foreach ($tag in $node.Tags) {
                if ([string]::IsNullOrWhiteSpace($tag.Name)) {
                    $results.Add([PSCustomObject]@{ Id = $node.Id; NodeName = $node.Name; Path = $path; Status = "Error"; Message = (Loc "validation_err_tag_no_name" $null); Level = "Static" })
                    continue
                }

                if ($SiteId -and $knownFields.Count -gt 0) {
                    if (-not $knownFields.Contains($tag.Name)) {
                        $results.Add([PSCustomObject]@{ Id = $node.Id; NodeName = $node.Name; Path = $path; Status = "Error"; Message = (Loc "validation_err_col_not_found" $tag.Name); Level = "Metadata" })
                    }
                }
            }
        }

        # Récursion
        $children = if ($node.Children) { $node.Children } else { $node.Folders }
        if ($children) {
            foreach ($sub in $children) {
                Validate-Node -node $sub -path "$path/$($sub.Name)"
            }
        }
    }

    # Lancement
    $roots = if ($StructureData.PSObject.Properties.Match('Children')) { $StructureData.Children } else { $StructureData.Folders }
    if ($null -eq $roots -and $StructureData -is [array]) { $roots = $StructureData }

    if ($null -ne $roots) {
        foreach ($rootNode in $roots) {
            Validate-Node -node $rootNode -path "/$($rootNode.Name)"
        }
    }
    elseif ($StructureData.Name) {
        Validate-Node -node $StructureData -path "/$($StructureData.Name)"
    }

    return $results
}
