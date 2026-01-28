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
        [Parameter(Mandatory = $false)] [object]$Connection,
        [Parameter(Mandatory = $false)] [string]$TargetLibraryName
    )

    $results = [System.Collections.Generic.List[psobject]]::new()

    # Liste caractères interdits SharePoint (Folders)
    # ~ " # % & * : < > ? / \ { | }
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

    # ... (Connexion Logic preserved) ...
    # --- LEVEL 2 : Validation Connectée ---
    if ($Connection) {
        # ... (Library check preserved) ...
        if (-not [string]::IsNullOrWhiteSpace($TargetLibraryName)) {
            try { $lib = Get-PnPList -Identity $TargetLibraryName -Connection $Connection -ErrorAction Stop }
            catch {
                $results.Add([PSCustomObject]@{ Id = "ROOT"; NodeName = "Racine"; Path = "/"; Status = "Error"; Message = (Loc "validation_err_lib_not_found" $TargetLibraryName); Level = "Connected" })
            }
        }
    }

    # ... (Metadata Cache Logic preserved) ...
    # --- LEVEL 3 : Validation Métadonnées (Cache) ---
    $knownFields = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    if ($Connection -and -not [string]::IsNullOrWhiteSpace($TargetLibraryName)) {
        try {
            $fields = Get-PnPField -List $TargetLibraryName -Connection $Connection -ErrorAction Stop
            if ($fields) { foreach ($f in $fields) { $knownFields.Add($f.InternalName) | Out-Null; $knownFields.Add($f.Title) | Out-Null; $knownFields.Add($f.StaticName) | Out-Null } }
        }
        catch {}
    }

    function Validate-Node {
        param($node, $path)

        # 1. Validation Nom Dossier / Publication / Lien
        if (-not [string]::IsNullOrWhiteSpace($node.Name)) {
            if ($node.Name -match $forbiddenChars) {
                $results.Add([PSCustomObject]@{ Id = $node.Id; NodeName = $node.Name; Path = $path; Status = "Error"; Message = (Loc "validation_err_forbidden_chars" $null); Level = "Static" })
            }
            if ($node.Name.Length -gt 128) {
                $results.Add([PSCustomObject]@{ Id = $node.Id; NodeName = $node.Name; Path = $path; Status = "Warning"; Message = (Loc "validation_err_name_length" $null); Level = "Static" })
            }
        }
        else {
            $results.Add([PSCustomObject]@{ Id = $node.Id; NodeName = "???"; Path = $path; Status = "Error"; Message = (Loc "validation_err_empty_name" $null); Level = "Static" })
        }

        # 2. Validation Types Spécifiques
        
        # A. PUBLICATION
        if ($node.Type -eq "Publication") {
            if ($node.TargetSiteMode -eq "Url") {
                if (-not ([Uri]::IsWellFormedUriString($node.TargetSiteUrl, [UriKind]::Absolute))) {
                    $results.Add([PSCustomObject]@{ Id = $node.Id; NodeName = $node.Name; Path = $path; Status = "Error"; Message = (Loc "validation_err_invalid_url" $null); Level = "Static" })
                }
            }
        }
        
        # B. LIEN (Link)
        if ($node.Type -eq "Link") {
            if (-not ([Uri]::IsWellFormedUriString($node.Url, [UriKind]::Absolute))) {
                $results.Add([PSCustomObject]@{ Id = $node.Id; NodeName = $node.Name; Path = $path; Status = "Error"; Message = "URL invalide pour le lien"; Level = "Static" })
            }
        }
        
        # C. LIEN INTERNE (InternalLink)
        if ($node.Type -eq "InternalLink") {
            if ([string]::IsNullOrWhiteSpace($node.TargetNodeId)) {
                $results.Add([PSCustomObject]@{ Id = $node.Id; NodeName = $node.Name; Path = $path; Status = "Error"; Message = "Cible du lien interne manquante"; Level = "Static" })
            }
        }    # 3. Validation Permissions
        if ($node.Permissions) {
            foreach ($perm in $node.Permissions) {
                if ([string]::IsNullOrWhiteSpace($perm.Email)) {
                    $results.Add([PSCustomObject]@{
                            Id       = $node.Id
                            NodeName = $node.Name
                            Path     = $path
                            Status   = "Error"
                            Message  = (Loc "validation_err_perm_no_email" $null)
                            Level    = "Static"
                        })
                }
                elseif ($Connection) {
                    # Validation User Permission (Connected)
                    # On utilise New-PnPUser pour valider que le login est résolvable
                    try {
                        $u = New-PnPUser -LoginName $perm.Email -Connection $Connection -ErrorAction Stop
                    }
                    catch {
                        $results.Add([PSCustomObject]@{
                                Id       = $node.Id
                                NodeName = $node.Name
                                Path     = $path
                                Status   = "Error"
                                Message  = (Loc "validation_err_perm_user_not_found" $perm.Email)
                                Level    = "Connected"
                            })
                    }
                }
            }
        }
        
        # 4. Validation Métadonnées (LEVEL 3)
        if ($node.Tags) {
            foreach ($tag in $node.Tags) {
                # Check Static
                if ([string]::IsNullOrWhiteSpace($tag.Name)) {
                    $results.Add([PSCustomObject]@{
                            Id       = $node.Id
                            NodeName = $node.Name
                            Path     = $path
                            Status   = "Error"
                            Message  = (Loc "validation_err_tag_no_name" $null)
                            Level    = "Static"
                        })
                    continue
                }

                # Check Connected
                if ($Connection -and $knownFields.Count -gt 0) {
                    if (-not $knownFields.Contains($tag.Name)) {
                        $results.Add([PSCustomObject]@{
                                Id       = $node.Id
                                NodeName = $node.Name
                                Path     = $path
                                Status   = "Error"
                                Message  = (Loc "validation_err_col_not_found" $tag.Name)
                                Level    = "Metadata"
                            })
                    }
                }
            }
        }

        # Récursion
        if ($node.Folders) {
            foreach ($sub in $node.Folders) {
                Validate-Node -node $sub -path "$path/$($sub.Name)"
            }
        }
        
    }

    # Lancement Recursion
    if ($StructureData.Folders) {
        foreach ($rootFolder in $StructureData.Folders) {
            Validate-Node -node $rootFolder -path "/$($rootFolder.Name)"
        }
    }
    else {
        # Cas structure simple ou objet folder unique
        Validate-Node -node $StructureData -path "/$($StructureData.Name)"
    }

    return $results
}
