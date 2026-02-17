# Modules/Toolbox.SharePoint/Functions/Rename-AppSPPublications.ps1

<#
.SYNOPSIS
    Renomme les dossiers de publication distants (Miroirs) suite au renommage du dossier racine.

.DESCRIPTION
    Parcourt la structure JSON pour identifier les noeuds de type 'Publication'.
    Si une publication utilise 'UseModelName', cela signifie qu'un dossier au nom du projet existe sur la cible.
    Cette fonction se connecte à la cible et renomme ce dossier pour refléter le nouveau nom de projet.

.PARAMETER StructureJson
    Le JSON de structure définissant les publications.

.PARAMETER OldRootName
    L'ancien nom du dossier racine (pour trouver les anciens dossiers de publication).

.PARAMETER NewRootName
    Le nouveau nom du dossier racine.

.PARAMETER ClientId
    ID Client pour l'authentification PnP sur les sites cibles.

.PARAMETER Thumbprint
    Thumbprint du certificat pour l'authentification PnP.

.PARAMETER TenantName
    Nom du tenant (pour construction URL auth).
    
.PARAMETER DefaultTargetSiteUrl
    URL du site courant (utilisé si TargetSiteMode = 'Auto').
#>
function Rename-AppSPPublications {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$StructureJson,
        [Parameter(Mandatory)] [string]$OldRootName,
        [Parameter(Mandatory)] [string]$NewRootName,
        [Parameter(Mandatory)] [string]$ClientId,
        [Parameter(Mandatory)] [string]$Thumbprint,
        [Parameter(Mandatory)] [string]$TenantName,
        [Parameter(Mandatory)] [string]$DefaultTargetSiteUrl
    )

    $result = @{ Success = $true; Logs = [System.Collections.Generic.List[string]]::new(); Errors = [System.Collections.Generic.List[string]]::new() }
    function Log { param($m, $l = "Info") Write-AppLog -Message $m -Level $l -Collection $result.Logs }
    function Err { param($m) $result.Success = $false; Write-AppLog -Message $m -Level Error -Collection $result.Errors; Log $m "Error" }

    try {
        if ($OldRootName -eq $NewRootName) {
            Log "Ancien et nouveau nom identiques. Pas de renommage de publication requis." "Info"
            return $result
        }

        $structure = $StructureJson | ConvertFrom-Json
        
        # Helper Recursif pour trouver les publications
        $pubs = [System.Collections.Generic.List[psobject]]::new()
        function Find-Pubs {
            param($Node)
            if ($Node.Type -eq "Publication") { $pubs.Add($Node) }
            if ($Node.Folders) { foreach ($f in $Node.Folders) { Find-Pubs -Node $f } }
        }
        
        if ($structure.Folders) { foreach ($f in $structure.Folders) { Find-Pubs -Node $f } }
        else { Find-Pubs -Node $structure }

        Log "Analyse de $($pubs.Count) publications potentiellement impactées..." "Info"

        foreach ($pub in $pubs) {
            # Condition : UseModelName DOIT être vrai pour qu'un dossier "Miroir" existe
            if ($pub.UseModelName) {
                $targetSite = $DefaultTargetSiteUrl
                if ($pub.TargetSiteMode -eq "Url" -and -not [string]::IsNullOrWhiteSpace($pub.TargetSiteUrl)) {
                    $targetSite = $pub.TargetSiteUrl
                }

                $basePath = $pub.TargetFolderPath
                $oldPath = "$basePath/$OldRootName"
                
                # Check 1: Est-ce qu'on a déjà traité ce site/path ? (Eviter doublons si structure multiple ?)
                # On assume que non pour l'instant.

                try {
                    Log "  Checking Publication: $($pub.Name) -> $targetSite ($oldPath)" "Debug"
                    
                    # AUTH CIBLE
                    $cleanTenant = $TenantName -replace "\.onmicrosoft\.com$", "" -replace "\.sharepoint\.com$", ""
                    $conn = Connect-PnPOnline -Url $targetSite -ClientId $ClientId -Thumbprint $Thumbprint -Tenant "$cleanTenant.onmicrosoft.com" -ReturnConnection -ErrorAction Stop
                    
                    # CHECK OLD FOLDER EXISTENCE
                    # Note: Resolve-PnPFolder est pratique mais peut thrower
                    $oldFolder = $null
                    try {
                        $oldFolder = Resolve-PnPFolder -SiteRelativePath $oldPath -Connection $conn -ErrorAction Stop
                    }
                    catch {
                        Log "    Dossier cible introuvable ($oldPath). Pas de renommage nécessaire." "Debug"
                        continue
                    }

                    if ($oldFolder) {
                        # RENAME
                        Log "    Dossier trouvé ! Renommage en '$NewRootName'..." "Info"
                        
                        # On récupère l'Item pour modifier FileLeafRef (Nom Dossier)
                        $item = Get-PnPFolder -Url $oldFolder.ServerRelativeUrl -Includes ListItemAllFields -Connection $conn | Select-Object -ExpandProperty ListItemAllFields
                        if ($item) {
                            Set-PnPListItem -List $item.ParentList -Identity $item.Id -Values @{ "FileLeafRef" = $NewRootName } -Connection $conn -ErrorAction Stop
                            Log "    ✅ Publication renommée avec succès." "Success"
                        }
                        else {
                            Log "    ⚠️ Impossible de récupérer l'objet ListItem du dossier. Renommage ignoré." "Warning"
                        }
                    }
                }
                catch {
                    Err "    ❌ Erreur traitement publication sur $targetSite : $($_.Exception.Message)"
                }
            }
        }
    }
    catch {
        Err "Erreur globale Rename-AppSPPublications : $($_.Exception.Message)"
    }

    return $result
}
