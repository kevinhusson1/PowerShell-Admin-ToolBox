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

    $LogsList = [System.Collections.Generic.List[string]]::new()
    $Errors = @()

    $TargetUrl = [uri]::UnescapeDataString($TargetUrl)

    function Log { 
        param($m, $l = "Info") 
        $LogsList.Add("AppLog: [$l] $m")
        # On utilise Write-Output avec un préfixe pour le flux standard (Receive-Job)
        Write-Output "[LOG] AppLog: [$l] $m"
        Write-Verbose "[$l] $m" 
    }

    try {
        Log "Début de la réparation sur : $TargetUrl"
        
        # Pré-chargement des listes pour correspondre aux URLs (Evite l'erreur System.Object[])
        $allLists = Get-PnPList -Connection $Connection -Includes RootFolder.ServerRelativeUrl, Title
        
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
            try {
                $list = $allLists | Where-Object { $TargetUrl.StartsWith($_.RootFolder.ServerRelativeUrl, [System.StringComparison]::InvariantCultureIgnoreCase) } | Sort-Object { $_.RootFolder.ServerRelativeUrl.Length } -Descending | Select-Object -First 1

                $folder = Get-PnPFolder -Url $TargetUrl -Connection $Connection -Includes ListItemAllFields -ErrorAction Stop
                $listItem = $folder.ListItemAllFields

                if ($listItem -and $listItem.Id -and $list) {
                    Set-AppSPMetadata -List $list.Title -ItemId $listItem.Id -Values $hash -Connection $Connection
                    Log "Métadonnées appliquées avec succès." "Success"
                }
                else {
                    Log "Impossible de récupérer le ListItem du dossier ou la liste parente." "Error"
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
                        New-AppSPFolder -SiteRelativePath $newPath -Connection $Connection | Out-Null
                        Log "   OK." "Success"
                    }
                    catch {
                        Log "   Echec création : $($_.Exception.Message)" "Error"
                    }
                }
                elseif ($txt -match "Métadonnée '(.+?)' incorrecte sur '(.+?)' : '(.+?)' vs '(.+?)'") {
                    $keyName = $Matches[1]
                    $itemName = $Matches[2]
                    $expectedValue = $Matches[3]
                    
                    $newPath = "$TargetUrl/$itemName"
                    Log " > Correction métadonnée $keyName = '$expectedValue' sur : $newPath"
                    try {
                        $list = $allLists | Where-Object { $newPath.StartsWith($_.RootFolder.ServerRelativeUrl, [System.StringComparison]::InvariantCultureIgnoreCase) } | Sort-Object { $_.RootFolder.ServerRelativeUrl.Length } -Descending | Select-Object -First 1

                        if (-not $list) { throw "Impossible de déterminer la bibliothèque." }

                        $listItem = $null
                        try {
                            $f = Get-PnPFolder -Url $newPath -Connection $Connection -Includes ListItemAllFields -ErrorAction Stop
                            $listItem = $f.ListItemAllFields
                        }
                        catch {
                            # Fallback : Recherche via requête list PnP robuste (contourne les erreurs Get-File sur les .url)
                            $safeName1 = $itemName.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;")
                            $safeName2 = "$safeName1.url"
                            
                            $caml = "<View Scope='RecursiveAll'><Query><Where><Or><Eq><FieldRef Name='FileLeafRef'/><Value Type='Text'>$safeName1</Value></Eq><Eq><FieldRef Name='FileLeafRef'/><Value Type='Text'>$safeName2</Value></Eq></Or></Where></Query></View>"
                            
                            $items = Get-PnPListItem -List $list.Title -Query $caml -Connection $Connection -ErrorAction SilentlyContinue
                            
                            if ($items) {
                                # S'il y a plusieurs éléments du même nom dans la liste, on filtre sur celui du bon projet
                                $listItem = $items | Where-Object { 
                                    ($_["FileRef"] -as [string]).StartsWith($TargetUrl, [System.StringComparison]::InvariantCultureIgnoreCase) 
                                } | Select-Object -First 1
                            }
                        }

                        if ($listItem -and $listItem.Id) {
                            Set-AppSPMetadata -List $list.Title -ItemId $listItem.Id -Values @{ $keyName = $expectedValue } -Connection $Connection
                            Log "   Appliqué avec succès." "Success"
                        }
                        else {
                            Log "   Impossible de récupérer le ListItem de l'élément. La requête n'a trouvé aucun identifiant valide." "Error"
                        }
                    }
                    catch {
                        Log "   Echec correction métadonnée : $($_.Exception.Message)" "Error"
                    }
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
        Logs    = $LogsList.ToArray()
        Errors  = $Errors
    }
}
