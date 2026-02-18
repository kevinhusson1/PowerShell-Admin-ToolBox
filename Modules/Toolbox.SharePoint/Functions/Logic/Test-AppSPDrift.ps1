function Test-AppSPDrift {
    param(
        [Parameter(Mandatory)] [PnP.PowerShell.Commands.Base.PnPConnection]$Connection,
        [Parameter(Mandatory)] [Microsoft.SharePoint.Client.ListItem]$FolderItem,
        [Parameter(Mandatory)] [string]$FormValuesJson,
        [string]$TemplateJson # Optional for Structure Check
    )

    $result = [PSCustomObject]@{
        MetaStatus      = "Unknown" # OK, DRIFT
        StructureStatus = "Unknown" # OK, DRIFT, IGNORED
        MetaDrifts      = @()
        StructureMisses = @()
        DebugTrace      = @()
        AuditLog        = [System.Collections.Generic.List[string]]::new()
    }

    # Helper to add audit check
    function Add-Audit { param($Status, $Msg) $result.AuditLog.Add("[$Status] $Msg") }

    # =========================================================================
    # 1. METADATA CHECK
    # =========================================================================
    try {
        if (-not [string]::IsNullOrWhiteSpace($FormValuesJson)) {
            $expected = $FormValuesJson | ConvertFrom-Json -AsHashtable
            $driftList = @()
            $ignoreKeys = @("TemplateVersion", "ConfigName") # Fields present in JSON but not necessarily in SharePoint Columns

            foreach ($key in $expected.Keys) {
                # Skip internal/special keys
                if ($key -match "^_") { continue }
                if ($ignoreKeys -contains $key) { continue }

                # [FIX] Special Handling for Folder Name (PreviewText)
                if ($key -eq "PreviewText") {
                    $expectedName = $expected[$key]
                    $actualName = $FolderItem["FileLeafRef"] # FileLeafRef = Name/LeafName in SharePoint

                    if ($actualName -ne $expectedName) {
                        $driftList += "Nom du Dossier (PreviewText) : Expected '$expectedName' but found '$actualName'"
                    }
                    continue
                }

                $pnpKey = $key # Assuming internal names match
                
                # Handling tricky field types (Taxonomy, User) could be complex
                # For V1, we check text/choice values.
                
                $actualVal = $null
                try { $actualVal = $FolderItem[$pnpKey] } catch {}

                # Simple string comparison for now
                if ("$actualVal" -ne "$($expected[$key])") {
                    # Special Case: Taxonomy format mismatch "Label|Guid" vs "Label"
                    if ($actualVal -is [Microsoft.SharePoint.Client.Taxonomy.TaxonomyFieldValue]) {
                        if ($actualVal.Label -ne $expected[$key]) {
                            $driftList += "$key : Expected '$($expected[$key])' but found '$($actualVal.Label)'"
                        }
                    }
                    elseif ($actualVal -is [Microsoft.SharePoint.Client.FieldUserValue]) {
                        if ($actualVal.LookupValue -ne $expected[$key]) {
                            $driftList += "$key : Expected '$($expected[$key])' but found '$($actualVal.LookupValue)'"
                        }
                    }
                    else {
                        $driftList += "$key : Expected '$($expected[$key])' but found '$actualVal'"
                    }
                }
            }

            if ($driftList.Count -eq 0) {
                $result.MetaStatus = "OK"
            }
            else {
                $result.MetaStatus = "DRIFT"
                $result.MetaDrifts = $driftList
            }
        }
        else {
            $result.MetaStatus = "NO_REF" # No reference data
        }
    }
    catch {
        Write-Warning "[Drift] Meta Check Failed: $_"
        $result.MetaStatus = "ERROR"
    }

    # =========================================================================
    # 2. STRUCTURE CHECK (Verbose)
    # =========================================================================
    try {
        if (-not [string]::IsNullOrWhiteSpace($TemplateJson)) {
            $structure = $TemplateJson | ConvertFrom-Json
            
            # [FIX] Prepare Form Values for Dynamic Tag Resolution
            $formValuesHash = @{}
            if (-not [string]::IsNullOrWhiteSpace($FormValuesJson)) {
                $formValuesHash = $FormValuesJson | ConvertFrom-Json -AsHashtable
            }

            # [FIX] Use List for Reference-based modification across function scope
            $misses = [System.Collections.Generic.List[string]]::new()

            # Helper for Recursion
            function Test-FolderRecursively {
                param($BaseUrl, $Nodes)

                if (-not $Nodes) { return }

                # Normalize nodes (handle single object vs array)
                $nodeList = if ($Nodes -is [System.Array]) { $Nodes } else { @($Nodes) }

                foreach ($node in $nodeList) {
                    # [Enable] Check everything (Folders, Links, Files)
                    
                    if (-not [string]::IsNullOrWhiteSpace($node.Name)) {
                        # Ensure correct path formation
                        $expectedPath = "$($BaseUrl.TrimEnd('/'))/$($node.Name)"
                        
                        $itemFound = $false
                        $actualItem = $null
                        $typeLabel = $node.Type; if (-not $typeLabel) { $typeLabel = "Dossier" }

                        try {
                            # Check Existence check based on Type
                            if ($node.Type -eq "Link" -or $node.Type -eq "InternalLink" -or $node.Type -eq "Publication") {
                                # For links & publications, we expect a .url file
                                $linkName = $node.Name
                                if (-not $linkName.EndsWith(".url")) { $linkName += ".url" }
                                $expectedPath = "$($BaseUrl.TrimEnd('/'))/$linkName"
                                
                                # [FIX] Explicit Connection
                                $actualItem = Get-PnPFile -Url $expectedPath -AsListItem -Connection $Connection -ErrorAction Stop
                                $itemFound = $true
                                Add-Audit "OK" "$typeLabel trouvé : $linkName"
                            }
                            elseif ($node.Type -eq "File") {
                                # Generic File
                                $actualItem = Get-PnPFile -Url $expectedPath -AsListItem -Connection $Connection -ErrorAction Stop
                                $itemFound = $true
                                Add-Audit "OK" "Fichier trouvé : $($node.Name)"
                            }
                            else {
                                # Folder (Default)
                                # [FIX] Explicit Connection
                                $f = Get-PnPFolder -Url $expectedPath -Includes ListItemAllFields, Properties -Connection $Connection -ErrorAction Stop
                                $actualItem = $f.ListItemAllFields
                                $itemFound = $true
                                Add-Audit "OK" "Dossier trouvé : $($node.Name)"
                            }
                            
                            # [RECURSIVE META CHECK]
                            if ($itemFound -and $node.Tags) {
                                # Convert Node Tags to Hashtable for comparison
                                $expectedTags = @{}
                                foreach ($t in $node.Tags) { 
                                    # [FIX] Dynamic Tag Resolution
                                    if ($t.IsDynamic -eq $true -and $t.SourceVar -and $formValuesHash.ContainsKey($t.SourceVar)) {
                                        $expectedTags[$t.Name] = $formValuesHash[$t.SourceVar]
                                    }
                                    elseif ($t.Value) { $expectedTags[$t.Name] = $t.Value }
                                    elseif ($t.Term) { $expectedTags[$t.Name] = $t.Term }
                                }

                                foreach ($tagName in $expectedTags.Keys) {
                                    $expVal = $expectedTags[$tagName]
                                    if ($tagName -eq "Ref" -or $tagName -eq "RefDate") { continue } # Skip dynamic technical tags if needed

                                    try {
                                        $actVal = $actualItem[$tagName]
                                        # Simple check (Stringify)
                                        $actStr = if ($actVal -is [Microsoft.SharePoint.Client.Taxonomy.TaxonomyFieldValue]) { $actVal.Label } else { "$actVal" }
                                        
                                        if ($actStr -ne $expVal) {
                                            $msg = "Métadonnée '$tagName' incorrecte sur '$($node.Name)' : '$expVal' vs '$actStr'"
                                            $misses.Add($msg)
                                            Add-Audit "DRIFT" $msg
                                        }
                                        else {
                                            Add-Audit "OK" "  > Tag '$tagName' conforme ($actStr)"
                                        }
                                    }
                                    catch {
                                        # Field might be missing
                                    }
                                }
                            }

                            # Recurse (Folders only)
                            if ($node.Folders) {
                                Test-FolderRecursively -BaseUrl $expectedPath -Nodes $node.Folders
                            }
                        }
                        catch {
                            # Missing
                            $msg = "Manquant : '$($node.Name)' ($typeLabel)" # Simplified message for UI
                            $misses.Add($msg)
                            Add-Audit "MISSING" "$msg at $expectedPath ($($_.Exception.Message))"
                        }
                    }
                }
            }

            # Get Project Root URL (ServerRelative)
            $rootUrl = $FolderItem["FileRef"]
            Add-Audit "INFO" "Début analyse structure depuis : $rootUrl"
            
            # Start Recursion
            if ($structure.Folders) {
                Test-FolderRecursively -BaseUrl $rootUrl -Nodes $structure.Folders
            }
            elseif ($structure.Name) {
                Test-FolderRecursively -BaseUrl $rootUrl -Nodes $structure
            }

            if ($misses.Count -eq 0) {
                $result.StructureStatus = "OK"
                Add-Audit "SUCCESS" "Structure entièrement conforme."
            }
            else {
                $result.StructureStatus = "DRIFT"
                $result.StructureMisses = $misses
                Add-Audit "WARNING" "Structure non-conforme ($($misses.Count) erreurs)."
            }
        }
        else {
            $result.StructureStatus = "NO_REF"
            Add-Audit "WARNING" "Pas de TemplateJson disponible pour l'analyse structurelle."
        }
    }
    catch {
        Write-Warning "[Drift] Structure Check Failed: $_"
        $result.StructureStatus = "ERROR"
        Add-Audit "ERROR" "Crash analyse structure : $_"
    }

    return $result
}
