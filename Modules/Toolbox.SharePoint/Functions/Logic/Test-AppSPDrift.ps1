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
    }

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
    # 2. STRUCTURE CHECK
    # =========================================================================
    try {
        if (-not [string]::IsNullOrWhiteSpace($TemplateJson)) {
            $structure = $TemplateJson | ConvertFrom-Json
            $misses = @()

            # Helper for Recursion
            function Test-FolderRecursively {
                param($BaseUrl, $Nodes)

                if (-not $Nodes) { return }

                # Normalize nodes (handle single object vs array)
                $nodeList = if ($Nodes -is [System.Array]) { $Nodes } else { @($Nodes) }

                foreach ($node in $nodeList) {
                    # We only check Folders and Publications (that are folders), ignoring Links/Files for structure drift for now
                    if ($node.Type -eq "Link" -or $node.Type -eq "InternalLink" -or $node.Type -eq "File") { continue }
                    
                    if (-not [string]::IsNullOrWhiteSpace($node.Name)) {
                        $expectedPath = "$BaseUrl/$($node.Name)"
                        
                        # Check Existence
                        # We use Get-PnPFolder to check existence. Resolve-PnPFolder can be tricky with permissions.
                        # Actually Resolve-PnPFolder is good for checking existence.
                        try {
                            $null = Resolve-PnPFolder -SiteRelativePath $expectedPath -Connection $Connection -ErrorAction Stop
                            
                            # Recurse
                            if ($node.Folders) {
                                Test-FolderRecursively -BaseUrl $expectedPath -Nodes $node.Folders
                            }
                        }
                        catch {
                            # Folder Missing
                            $misses += "Dossier manquant : $expectedPath"
                        }
                    }
                }
            }

            # Get Project Root URL
            # FolderItem is a ListItem, we need the Folder URL.
            # Usually FolderItem["FileRef"] gives the ServerRelativeUrl.
            $rootUrl = $FolderItem["FileRef"]
            
            # Start Recursion
            if ($structure.Folders) {
                Test-FolderRecursively -BaseUrl $rootUrl -Nodes $structure.Folders
            }
            # Handle case where structure is just a single object without "Folders" root array (unlikely but possible)
            elseif ($structure.Name) {
                Test-FolderRecursively -BaseUrl $rootUrl -Nodes $structure
            }

            if ($misses.Count -eq 0) {
                $result.StructureStatus = "OK"
            }
            else {
                $result.StructureStatus = "DRIFT"
                $result.StructureMisses = $misses
            }
        }
        else {
            $result.StructureStatus = "NO_REF"
        }
    }
    catch {
        Write-Warning "[Drift] Structure Check Failed: $_"
        $result.StructureStatus = "ERROR"
    }

    return $result
}
