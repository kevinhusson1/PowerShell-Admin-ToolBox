function Repair-AppProject {
    <#
    .SYNOPSIS
        Répare les éléments divergents d'un projet SharePoint (Métadonnées et Structure).
    
    .PARAMETER TargetUrl
        URL relative du site ou dossier racine du projet.
    
    .PARAMETER RepairItems
        Liste d'objets @{ Type="Meta"|"Structure"; Key=...; Value=...; Raw=... }
        
    .PARAMETER Connection
        Connexion PnP PowerShell active.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetUrl,

        [Parameter(Mandatory = $true)]
        [array]$RepairItems,

        [Parameter(Mandatory = $true)]
        [PnP.PowerShell.Commands.Base.PnPConnection]$Connection
    )

    $Logs = @()
    $Errors = @()

    function Log { param($m, $l = "Info") $script:Logs += "AppLog: [$l] $m"; Write-Verbose "[$l] $m" }

    try {
        Log "Début de la réparation sur : $TargetUrl"
        
        # 1. Repair Metadata
        $metaItems = $RepairItems | Where-Object { $_.Type -eq "Meta" }
        if ($metaItems) {
            Log "Correction de $($metaItems.Count) métadonnées..."
            $hash = @{}
            foreach ($m in $metaItems) {
                $hash[$m.Key] = $m.Value
                Log " > Set $($m.Key) = '$($m.Value)'"
            }
            
            # Apply to Folder
            # Note: We assume TargetUrl is a Folder. Set-PnPListItem works on the item associated with the folder.
            try {
                $folder = Get-PnPFolder -Url $TargetUrl -Connection $Connection -Includes ListItemAllFields, ServerRelativeUrl -ErrorAction Stop
                if ($folder.ListItemAllFields) {
                    Set-PnPListItem -List $folder.ListItemAllFields.ParentList.Title -Identity $folder.ListItemAllFields.Id -Values $hash -Connection $Connection -ErrorAction Stop
                    Log "Métadonnées appliquées avec succès." "Success"
                }
                else {
                    Log "Impossible de récupérer le ListItem du dossier." "Error"
                }
            }
            catch {
                Log "Erreur lors de la mise à jour des métadonnées : $($_.Exception.Message)" "Error"
            }
        }

        # 2. Repair Structure
        $structItems = $RepairItems | Where-Object { $_.Type -eq "Structure" }
        if ($structItems) {
            Log "Correction de $($structItems.Count) éléments de structure..."
            
            foreach ($s in $structItems) {
                # Logic depends on what "Raw" contains. 
                # Example: "Manquant : 'REALISATION' (Dossier)"
                # Example: "Métadonnée 'Services' incorrecte sur 'CONCEPTION' ..."
                
                $txt = $s.Raw
                
                if ($txt -match "Manquant : '(.+?)' \(Dossier\)") {
                    $folderName = $Matches[1]
                    # We need to reconstruct full path? 
                    # Actually Test-Drift usually reports missing items relative to root or deeply?
                    # If it's just "Manquant : 'REALISATION'", it's likely a direct child of some scanned folder.
                    # LIMITATION: The current drift report might not contain the FULL relative path of the missing item if strictly text.
                    # BUT: In Register-RenamerDashboard, "StructureMisses" comes from Test-AppSPDrift. 
                    
                    # For V1, we act on Direct Children of Root if name matches, OR we try to resolve.
                    # Simplest approach for "REALISATION": Try to create it at Root/$folderName
                    
                    $newPath = "$TargetUrl/$folderName"
                    Log " > Création dossier : $newPath"
                    try {
                        Resolve-PnPFolder -SiteRelativePath $newPath -Connection $Connection | Out-Null
                        Log "   OK." "Success"
                    }
                    catch {
                        Log "   Echec création : $($_.Exception.Message)" "Error"
                    }
                }
                elseif ($txt -match "Métadonnée '(.+?)' incorrecte sur '(.+?)'") {
                    # Complex case: Metadata on logic sub-folder.
                    # Implementation to follow if needed.
                    Log " > Correction métadonnée sous-dossier non implémentée (TODO): $txt" "Warning"
                }
                else {
                    Log " > Type de réparation inconnu pour : $txt" "Warning"
                }
            }
        }

    }
    catch {
        $Errors += $_.Exception.Message
        Log "Erreur globale réparation : $($_.Exception.Message)" "Error"
    }

    return [PSCustomObject]@{
        Success = ($Errors.Count -eq 0)
        Logs    = $Logs
        Errors  = $Errors
    }
}
