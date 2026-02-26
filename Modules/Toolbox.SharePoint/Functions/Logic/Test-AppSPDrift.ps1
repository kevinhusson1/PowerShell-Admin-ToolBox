function Test-AppSPDrift {
    param(
        [Parameter(Mandatory)] [PnP.PowerShell.Commands.Base.PnPConnection]$Connection,
        [Parameter(Mandatory)] [Microsoft.SharePoint.Client.ListItem]$FolderItem,
        [Parameter(Mandatory)] [string]$FormValuesJson,
        [string]$TemplateJson, # Optional for Structure Check
        [string]$DeploymentId,
        [string]$ClientId,
        [string]$Thumbprint,
        [string]$TenantName,
        [string]$ProjectModelName
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

            # [FIX] Root Folder Name Verification (Force Check even if not in keys)
            $expectedName = if ($ProjectModelName) { $ProjectModelName } elseif ($expected.ContainsKey("PreviewText")) { $expected["PreviewText"] } else { $null }
            if ($expectedName) {
                $actualName = $FolderItem["FileLeafRef"]
                if ($actualName -ne $expectedName) {
                    $driftList += "Nom du Dossier : Expected '$expectedName' but found '$actualName'"
                }
            }

            foreach ($key in $expected.Keys) {
                # Skip internal/special keys
                if ($key -match "^_") { continue }
                if ($ignoreKeys -contains $key) { continue }
                if ($key -eq "PreviewText") { continue }

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

            # [FIX] Build ID to Path Map for InternalLinks
            $IdToPathMap = @{}
            function Build-IdMap {
                param($SubStructure, $CurrentPath)
                if ($SubStructure -is [System.Array]) {
                    foreach ($item in $SubStructure) { Build-IdMap -SubStructure $item -CurrentPath $CurrentPath }
                    return
                }
                if ($SubStructure.Type -ne "Link" -and $SubStructure.Type -ne "InternalLink" -and $SubStructure.Type -ne "Publication" -and $SubStructure.Name) {
                    $myPath = "$CurrentPath/$($SubStructure.Name)"
                    if ($SubStructure.Id) { $IdToPathMap[$SubStructure.Id] = $myPath }
                    if ($SubStructure.Folders) { Build-IdMap -SubStructure $SubStructure.Folders -CurrentPath $myPath }
                }
            }
            if ($structure.Folders) { Build-IdMap -SubStructure $structure.Folders -CurrentPath "" }
            else { Build-IdMap -SubStructure $structure -CurrentPath "" }

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
                            if ($node.Type -eq "Link" -or $node.Type -eq "InternalLink") {
                                # For links, we expect a .url file
                                $linkName = $node.Name
                                if (-not $linkName.EndsWith(".url")) { $linkName += ".url" }
                                $expectedPath = "$($BaseUrl.TrimEnd('/'))/$linkName"
                                
                                # Use Get-PnPFile to check existence, it returns $null if not found
                                $checkFile = Get-PnPFile -Url $expectedPath -Connection $Connection -ErrorAction SilentlyContinue
                                if ($null -eq $checkFile) { throw "Raccourci introuvable" }
                                
                                # Load Item with all custom fields
                                $actualItem = Get-PnPFile -Url $expectedPath -AsListItem -Connection $Connection -ErrorAction SilentlyContinue

                                $itemFound = $true
                                Add-Audit "OK" "$typeLabel trouvé : $linkName"
                                
                                # --- VÉRIFICATION SPÉCIFIQUE POU INTERNAL LINK ---
                                if ($node.Type -eq "InternalLink" -and $actualItem) {
                                    $targetId = $node.TargetNodeId
                                    if ($IdToPathMap.ContainsKey($targetId)) {
                                        # Calculate expected Absolute URL
                                        $relPath = $IdToPathMap[$targetId]
                                        
                                        # Fix: Get Absolute URI Host from the connection
                                        $uri = New-Object Uri($Connection.Url) 
                                        $baseHost = "$($uri.Scheme)://$($uri.Host)"
                                        
                                        # [FIX] Use the FolderItem properties to get the original root project path
                                        $rootProjectRelPath = $FolderItem["FileRef"]
                                        if (-not $rootProjectRelPath) { 
                                            $rootProjectRelPath = $FolderItem["FileDirRef"] + "/" + $FolderItem["FileLeafRef"] 
                                        }
                                        $expectedTargetUrl = "$baseHost$rootProjectRelPath$relPath"
                                        
                                        # Read actual shortcut URL from ListItem
                                        $actualTargetUrl = $actualItem["_ShortcutUrl"]
                                        
                                        if ([string]::IsNullOrWhiteSpace($actualTargetUrl)) {
                                            # Try to get it from the file content if ListItem field is empty
                                            try {
                                                $fileContent = Get-PnPFile -Url $expectedPath -AsString -Connection $Connection -ErrorAction SilentlyContinue
                                                if ($fileContent -match "URL=(.+)") {
                                                    $actualTargetUrl = $Matches[1].Trim()
                                                }
                                            }
                                            catch {}
                                        }

                                        if ($actualTargetUrl) {
                                            # Normalize URLs for comparison (decode, lowercase)
                                            $normExpected = [System.Uri]::UnescapeDataString($expectedTargetUrl).ToLower().Trim('/')
                                            $normActual = [System.Uri]::UnescapeDataString($actualTargetUrl).ToLower().Trim('/')
                                            
                                            if ($normExpected -ne $normActual) {
                                                $warn = "La destination du lien interne '$linkName' n'est plus la bonne (Attendu: $expectedTargetUrl)."
                                                $misses.Add($warn)
                                                Add-Audit "DRIFT" "Le lien interne pointe vers une mauvaise adresse (probablement dû à un renommage parent)."
                                            }
                                            else {
                                                Add-Audit "OK" "  > Cible du lien interne vérifiée : $expectedTargetUrl"
                                            }
                                        }
                                        else {
                                            $warn = "La destination du lien interne '$linkName' est introuvable."
                                            $misses.Add($warn)
                                            Add-Audit "MISSING" $warn
                                        }
                                    }
                                }
                            }
                            elseif ($node.Type -eq "Publication") {
                                $linkName = $node.Name
                                if (-not $linkName.EndsWith(".url")) { $linkName += ".url" }
                                
                                $itemFound = $false # Les publications n'existent pas en local. (Vérification ignorée)

                                # --- VÉRIFICATION CIBLE DISTANTE POUR PUBLICATION ---
                                if ($DeploymentId) {
                                    $rawDestPath = $node.TargetFolderPath
                                    try {
                                        # Deduce project name from the TRUE origin model name
                                        $projName = if ($ProjectModelName) { $ProjectModelName } else { $FolderItem["FileLeafRef"] }
                                        if ($node.UseModelName -eq $true) {
                                            $rawDestPath = "$rawDestPath/$projName"
                                        }

                                        $targetCtx = $Connection
                                        
                                        if ($node.TargetSiteMode -eq "Url" -and -not [string]::IsNullOrWhiteSpace($node.TargetSiteUrl) -and $ClientId) {
                                            $cleanTenant = $TenantName -replace "\.onmicrosoft\.com$", "" -replace "\.sharepoint\.com$", ""
                                            $targetCtx = Connect-PnPOnline -Url $node.TargetSiteUrl -ClientId $ClientId -Thumbprint $Thumbprint -Tenant "$cleanTenant.onmicrosoft.com" -ReturnConnection -ErrorAction Stop
                                        }

                                        $resolvedDest = Get-PnPFolder -Url $rawDestPath -Connection $targetCtx -ErrorAction Stop
                                        
                                        $ctx = $resolvedDest.Context
                                        $ctx.Load($resolvedDest.Properties)
                                        $ctx.ExecuteQuery()
                                        
                                        $remoteDeployId = $resolvedDest.Properties["_AppDeploymentId"]
                                        if ($remoteDeployId -eq $DeploymentId) {
                                            # Validate that local and remote names are identical (Warn if Root Folder was renamed exclusively locally)
                                            $currName = $FolderItem["FileLeafRef"]
                                            if ($projName -ne $currName) {
                                                $warn = "⚠️ Le nom de la publication distante ($projName) n'est plus synchronisé avec le nom du dossier racine local ($currName)."
                                                $misses.Add($warn)
                                                Add-Audit "DRIFT" "Le nom du dossier racine ($currName) diffère de la publication distante ($projName). Un renommage via l'outil est requis."
                                            }
                                            else {
                                                Add-Audit "OK"  "  > Dossier Cible distant vérifié (ID de déploiement concordant : $DeploymentId) à $rawDestPath"
                                            }
                                        }
                                        else {
                                            $msg = "Le dossier de destination du lien de publication '$linkName' n'existe plus ou n'est plus lié."
                                            $misses.Add($msg)
                                            Add-Audit "DRIFT" $msg
                                        }
                                    }
                                    catch {
                                        $msg = "Le dossier de destination du lien de publication '$linkName' n'existe plus."
                                        $misses.Add($msg)
                                        Add-Audit "MISSING" $msg
                                    }
                                }
                            }
                            elseif ($node.Type -eq "File") {
                                # Generic File
                                $checkFile = Get-PnPFile -Url $expectedPath -Connection $Connection -ErrorAction SilentlyContinue
                                if ($null -eq $checkFile) { throw "Fichier introuvable" }
                                $actualItem = Get-PnPFile -Url $expectedPath -AsListItem -Connection $Connection -ErrorAction SilentlyContinue
                                $itemFound = $true
                                Add-Audit "OK" "Fichier trouvé : $($node.Name)"
                            }
                            else {
                                # Folder (Default)
                                $f = Get-PnPFolder -Url $expectedPath -Includes ListItemAllFields, Properties -Connection $Connection -ErrorAction SilentlyContinue
                                if ($null -eq $f -or $null -eq $f.Name) { throw "Dossier introuvable" }
                                $actualItem = $f.ListItemAllFields
                                $itemFound = $true
                                Add-Audit "OK" "Dossier trouvé : $($node.Name)"
                            }
                            
                            # [RECURSIVE META CHECK]
                            if ($itemFound -and $node.Tags) {
                                # Convert Node Tags to Hashtable of Arrays for comparison (Multi-Value tags)
                                $expectedTags = @{}
                                foreach ($t in $node.Tags) { 
                                    $val = $null
                                    # [FIX] Dynamic Tag Resolution
                                    if ($t.IsDynamic -eq $true -and $t.SourceVar -and $formValuesHash.ContainsKey($t.SourceVar)) {
                                        $val = $formValuesHash[$t.SourceVar]
                                    }
                                    elseif ($t.Value) { $val = $t.Value }
                                    elseif ($t.Term) { $val = $t.Term }

                                    if ($null -ne $val) {
                                        if (-not $expectedTags.ContainsKey($t.Name)) {
                                            $expectedTags[$t.Name] = [System.Collections.Generic.List[string]]::new()
                                        }
                                        $expectedTags[$t.Name].Add("$val")
                                    }
                                }

                                foreach ($tagName in $expectedTags.Keys) {
                                    $expVals = $expectedTags[$tagName]
                                    if ($tagName -eq "Ref" -or $tagName -eq "RefDate") { continue } # Skip dynamic technical tags if needed

                                    if ($null -eq $actualItem) {
                                        $expStr = $expVals -join ' | '
                                        $msg = "Métadonnées inaccessibles sur '$($node.Name)' (Attendu '$tagName': '$expStr')"
                                        $misses.Add($msg)
                                        Add-Audit "DRIFT" $msg
                                        continue
                                    }

                                    try {
                                        $actVal = $actualItem[$tagName]

                                        # Build an array of actual values to compare against
                                        $actStrArray = @()
                                        if ($actVal -is [System.Array] -or $actVal -is [System.Collections.IEnumerable] -and $actVal -isnot [string]) {
                                            foreach ($v in $actVal) {
                                                if ($v -is [Microsoft.SharePoint.Client.Taxonomy.TaxonomyFieldValue]) { $actStrArray += $v.Label }
                                                else { $actStrArray += "$v" }
                                            }
                                        }
                                        elseif ($actVal -is [Microsoft.SharePoint.Client.Taxonomy.TaxonomyFieldValue]) {
                                            $actStrArray += $actVal.Label
                                        }
                                        else {
                                            $actStrArray += "$actVal"
                                        }

                                        # Compare logic: check if all expected values are present in the actual item
                                        $missingTags = @()
                                        foreach ($ev in $expVals) {
                                            $foundMatch = $false
                                            foreach ($av in $actStrArray) {
                                                if ($av -eq $ev) { $foundMatch = $true; break }
                                            }
                                            if (-not $foundMatch) { $missingTags += $ev }
                                        }
                                        
                                        $expStr = $expVals -join ' | '
                                        $actStr = if ($actStrArray.Count -gt 0) { $actStrArray -join ' | ' } else { "<Vide>" }

                                        if ($missingTags.Count -gt 0) {
                                            $msg = "Métadonnée '$tagName' incorrecte sur '$($node.Name)' : attendu '$expStr' vs réel '$actStr'"
                                            $misses.Add($msg)
                                            Add-Audit "DRIFT" $msg
                                        }
                                        else {
                                            # Check for potential extra tags (for purely informational logging)
                                            $extraTags = @()
                                            foreach ($av in $actStrArray) {
                                                $foundMatch = $false
                                                foreach ($ev in $expVals) {
                                                    if ($av -eq $ev) { $foundMatch = $true; break }
                                                }
                                                if (-not $foundMatch) { $extraTags += $av }
                                            }

                                            if ($extraTags.Count -gt 0) {
                                                $extraStr = $extraTags -join ', '
                                                Add-Audit "INFO" "  > Tag '$tagName' conforme ($expStr) avec ajouts supplémentaires ($extraStr)"
                                            }
                                            else {
                                                Add-Audit "OK" "  > Tag '$tagName' conforme ($expStr)"
                                            }
                                        }
                                    }
                                    catch {
                                        # Field might be missing
                                        $expStr = $expVals -join ' | '
                                        $msg = "Champ de métadonnée '$tagName' introuvable sur '$($node.Name)' (Attendu: '$expStr')"
                                        $misses.Add($msg)
                                        Add-Audit "DRIFT" $msg
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
