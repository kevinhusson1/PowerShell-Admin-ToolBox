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
    # + Leading/Trailing dots or spaces (géré souvent par PnP mais à éviter)
    $forbiddenChars = '[~"#%&*:<>?/\\{|}]'
    
    # --- LEVEL 2 : Validation Connectée ---
    if ($Connection) {
        Write-Verbose "Mode Connecté activé"
        
        # 1. Vérification Bibliothèque
        if (-not [string]::IsNullOrWhiteSpace($TargetLibraryName)) {
            try {
                $lib = Get-PnPList -Identity $TargetLibraryName -Connection $Connection -ErrorAction Stop
            }
            catch {
                $results.Add([PSCustomObject]@{
                        Id       = "ROOT"
                        NodeName = "Racine"
                        Path     = "/"
                        Status   = "Error"
                        Message  = "La bibliothèque cible '$TargetLibraryName' est introuvable sur le site."
                        Level    = "Connected"
                    })
            }
        }
    }

    function Validate-Node {
        param($node, $path)

        # 1. Validation Nom Dossier / Publication
        if (-not [string]::IsNullOrWhiteSpace($node.Name)) {
            if ($node.Name -match $forbiddenChars) {
                $results.Add([PSCustomObject]@{
                        Id       = $node.Id
                        NodeName = $node.Name
                        Path     = $path
                        Status   = "Error"
                        Message  = "Le nom contient des caractères interdits par SharePoint (~ # % & * : < > ? / \ { | })."
                        Level    = "Static"
                    })
            }
            if ($node.Name.Length -gt 128) {
                $results.Add([PSCustomObject]@{
                        Id       = $node.Id
                        NodeName = $node.Name
                        Path     = $path
                        Status   = "Warning"
                        Message  = "Le nom est très long (>128 chars), risque de dépassement de limite URL."
                        Level    = "Static"
                    })
            }
        }
        else {
            $results.Add([PSCustomObject]@{
                    Id       = $node.Id
                    NodeName = "???"
                    Path     = $path
                    Status   = "Error"
                    Message  = "Le nom du dossier est vide."
                    Level    = "Static"
                })
        }

        # 2. Validation Publication
        if ($node.Type -eq "Publication") {
            if ($node.TargetSiteMode -eq "Url") {
                if (-not ([Uri]::IsWellFormedUriString($node.TargetSiteUrl, [UriKind]::Absolute))) {
                    $results.Add([PSCustomObject]@{
                            Id       = $node.Id
                            NodeName = $node.Name
                            Path     = $path
                            Status   = "Error"
                            Message  = "L'URL du site cible est invalide."
                            Level    = "Static"
                        })
                }
            }
            if ([string]::IsNullOrWhiteSpace($node.GrantUser)) {
                $results.Add([PSCustomObject]@{
                        Id       = $node.Id
                        NodeName = $node.Name
                        Path     = $path
                        Status   = "Warning"
                        Message  = "Aucun utilisateur défini pour les droits source."
                        Level    = "Static"
                    })
            }
            # Validation User Publication (Connected)
            if ($Connection -and $node.GrantUser) {
                try {
                    $u = New-PnPUser -LoginName $node.GrantUser -Connection $Connection -ErrorAction Stop
                }
                catch {
                    $results.Add([PSCustomObject]@{
                            Id       = $node.Id
                            NodeName = $node.Name
                            Path     = $path
                            Status   = "Error"
                            Message  = "Utilisateur source '$($node.GrantUser)' introuvable dans l'annuaire."
                            Level    = "Connected"
                        })
                }
            }
        }

        # 3. Validation Permissions
        if ($node.Permissions) {
            foreach ($perm in $node.Permissions) {
                if ([string]::IsNullOrWhiteSpace($perm.Email)) {
                    $results.Add([PSCustomObject]@{
                            Id       = $node.Id
                            NodeName = $node.Name
                            Path     = $path
                            Status   = "Error"
                            Message  = "Permission sans email configurée."
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
                                Message  = "Utilisateur/Groupe '$($perm.Email)' introuvable ou invalide."
                                Level    = "Connected"
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
