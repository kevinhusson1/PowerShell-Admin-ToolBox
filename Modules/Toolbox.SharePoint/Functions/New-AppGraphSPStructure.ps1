# Modules/Toolbox.SharePoint/Functions/New-AppGraphSPStructure.ps1

<#
.SYNOPSIS
    Déploie une structure documentaire complète (Dossiers) sur SharePoint via Microsoft Graph API.

.DESCRIPTION
    Moteur V2 de déploiement qui interprète le JSON de structure pour créer
    l'arborescence (Graph API 100%). Remplace PnP.
#>
function New-AppGraphSPStructure {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$TargetSiteUrl,
        [Parameter(Mandatory)] [string]$TargetLibraryName,
        [Parameter(Mandatory = $false)] [string]$RootFolderName, 
        [Parameter(Mandatory)] [string]$StructureJson,
        [Parameter(Mandatory)] [string]$ClientId,
        [Parameter(Mandatory)] [string]$Thumbprint,
        [Parameter(Mandatory)] [string]$TenantName,
        [Parameter(Mandatory = $false)] [string]$TargetFolderUrl,
        [Parameter(Mandatory = $false)] [string]$TargetFolderItemId,
        [Parameter(Mandatory = $false)] [hashtable]$FormValues,
        [Parameter(Mandatory = $false)] [hashtable]$RootMetadata,
        [Parameter(Mandatory = $false)] [hashtable]$TrackingInfo,
        [Parameter(Mandatory = $false)] [string]$FolderSchemaJson,
        [Parameter(Mandatory = $false)] [string]$FolderSchemaName
    )

    $result = @{ Success = $true; Logs = [System.Collections.Generic.List[string]]::new(); Errors = [System.Collections.Generic.List[string]]::new(); FinalUrl = "" }

    function Log { param($m, $l = "Info") Write-AppLog -Message $m -Level $l -Collection $result.Logs -PassThru }
    function Err { param($m) $result.Success = $false; Write-AppLog -Message $m -Level Error -Collection $result.Errors; Write-AppLog -Message $m -Level Error -Collection $result.Logs -PassThru }

    function Update-AppGraphTags {
        param($SiteId, $ListId, $ListItemId, $TagsConfig)
        if (-not $ListItemId) { return }
        $groupedTags = $TagsConfig | Group-Object Name
        $fieldsHash = @{}
        try {
            foreach ($g in $groupedTags) {
                $fieldName = $g.Name
                $resolvedValues = @()
                foreach ($t in $g.Group) {
                    if ($t.IsDynamic -and $FormValues -and $t.SourceVar) {
                        $dynVal = $FormValues[$t.SourceVar]
                        if ($null -ne $dynVal -and $dynVal -ne "") { $resolvedValues += $dynVal }
                    }
                    else {
                        if ($t.Value) { $resolvedValues += $t.Value } elseif ($t.Term) { $resolvedValues += $t.Term }
                    }
                }
                
                # --- FIX v4.19/4.21: Gestion Robuste des Types de Données ---
                if ($resolvedValues.Count -eq 0) { continue }
                
                # Récupération du type depuis le schéma dossier pour cast éventuel
                $colDef = ($FolderSchemaJson | ConvertFrom-Json) | Where-Object { $_.Name -eq $fieldName } | Select-Object -First 1
                
                $finalValues = @()
                foreach ($val in $resolvedValues) {
                    if ($colDef.Type -eq "Nombre") {
                        if ($val -is [int] -or $val -is [int64] -or $val -match '^-?\d+$') {
                            $finalValues += [int64]$val
                        }
                        elseif ($val -as [double]) {
                            $finalValues += [double]$val
                        }
                        else {
                            $finalValues += $val
                        }
                    }
                    elseif ($colDef.Type -eq "Choix Multiples" -and $val -is [string] -and $val -match ';') {
                        # Découpage pour Item v4.40 : On split les chaînes concaténées
                        $parts = $val -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
                        $finalValues += $parts
                    }
                    else {
                        $finalValues += $val
                    }
                }
                
                if ($finalValues.Count -eq 0) { continue }
                
                if ($colDef.Type -eq "Choix Multiples") {
                    # --- RESTAURATION v4.29 : Envoi natif en tableau pour le Multi-Choix ---
                    $fieldsHash[$fieldName] = $finalValues 
                }
                elseif ($finalValues.Count -eq 1) { 
                    $fieldsHash[$fieldName] = $finalValues[0] 
                }
                else { 
                    $fieldsHash[$fieldName] = $finalValues 
                }
            }
            if ($fieldsHash.Count -gt 0) {
                try {
                    # 1. Tentative Standard (Graph Beta)
                    Set-AppGraphListItemMetadata -SiteId $SiteId -ListId $ListId -ListItemId $ListItemId -Fields $fieldsHash -ErrorAction Stop | Out-Null
                    Log "Métadonnées appliquées sur $ListItemId." "DEBUG"
                }
                catch {
                    # 2. Fallback v4.36: Si le patch groupé échoue, on tente une conversion string join
                    # car certaines colonnes Choice ne sont pas passées en multi-mode.
                    Log "Échec PATCH groupé sur $ListItemId, tentative de fallback String..." "WARNING"
                    $fallbackHash = @{}
                    foreach ($k in $fieldsHash.Keys) {
                        if ($fieldsHash[$k] -is [array]) { $fallbackHash[$k] = $fieldsHash[$k] -join "; " }
                        else { $fallbackHash[$k] = $fieldsHash[$k] }
                    }
                    try {
                        Set-AppGraphListItemMetadata -SiteId $SiteId -ListId $ListId -ListItemId $ListItemId -Fields $fallbackHash -ErrorAction Stop | Out-Null
                        Log "Métadonnées (Fallback String) appliquées sur $ListItemId." "DEBUG"
                    }
                    catch {
                        Log "Échec critique des métadonnées sur $ListItemId : $($_.Exception.Message)" "ERROR"
                    }
                }
            }
        }
        catch { Log "Erreur critique Update-AppGraphTags : $($_.Exception.Message)" "WARNING" }
    }

    try {
        Log "Initialisation Graph API V2..." "DEBUG"
        Connect-AppAzureCert -TenantId $TenantName -ClientId $ClientId -Thumbprint $Thumbprint | Out-Null
        
        $siteId = Get-AppGraphSiteId -SiteUrl $TargetSiteUrl
        if (-not $siteId) { throw "Impossible de résoudre le Site." }
        
        $libDrive = Get-AppGraphListDriveId -SiteId $siteId -ListDisplayName $TargetLibraryName
        if (-not $libDrive -or -not $libDrive.DriveId) { throw "Bibliothèque introuvable." }
        
        $listId = $libDrive.ListId
        $driveId = $libDrive.DriveId
        
        $FolderContentTypeId = "0x0120" # Default Folder CT
        if ($FolderSchemaJson -and $FolderSchemaName) {
            try {
                $schemaDef = $FolderSchemaJson | ConvertFrom-Json
                if ($schemaDef -is [array] -and $schemaDef.Count -gt 0) {
                    Log "Traitement du Schéma de Dossier Avancé '$FolderSchemaName' ($($schemaDef.Count) colonnes)..." "INFO"
                    
                    # --- EXTRACTION DYNAMIQUE DES CHOIX v4.35 (FIX RECURSION) ---
                    $colIds = @()
                    $script:allTags = @()
                    function Get-AllTagsRecursive {
                        param($obj)
                        if ($null -eq $obj) { return }
                        if ($obj -is [array] -or $obj -is [System.Collections.IEnumerable]) {
                            foreach ($item in $obj) { Get-AllTagsRecursive $item }
                            return
                        }
                        if ($obj -is [PSCustomObject] -or $obj -is [hashtable]) {
                            if ($obj.Tags) { 
                                foreach ($t in $obj.Tags) {
                                    $v = if ($t.Value) { $t.Value } elseif ($t.Term) { $t.Term } else { $null }
                                    if ($v -is [string] -and $v -match ';') {
                                        # Découpage v4.40 : Support des tags groupés par ';'
                                        $parts = $v -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
                                        foreach ($p in $parts) { $script:allTags += [PSCustomObject]@{ Name = $t.Name; Value = $p } }
                                    }
                                    elseif ($null -ne $v) {
                                        $script:allTags += [PSCustomObject]@{ Name = $t.Name; Value = $v }
                                    }
                                }
                            }
                            # On ne recurse que sur les branches de données connues pour éviter le Stack Overflow
                            if ($obj.Folders) { Get-AllTagsRecursive $obj.Folders }
                            if ($obj.Files) { Get-AllTagsRecursive $obj.Files }
                            if ($obj.Publications) { Get-AllTagsRecursive $obj.Publications }
                            if ($obj.Links) { Get-AllTagsRecursive $obj.Links }
                            if ($obj.InternalLinks) { Get-AllTagsRecursive $obj.InternalLinks }
                        }
                    }
                    $structure = $StructureJson | ConvertFrom-Json
                    Get-AllTagsRecursive $structure

                    # --- EXTRACTION COMPLÉMENTAIRE v4.40 (Form & Root Metadata - FIX SPLIT) ---
                    if ($RootMetadata) {
                        foreach ($k in $RootMetadata.Keys) {
                            $v = $RootMetadata[$k]
                            if ($v -is [string] -and $v -match ';') {
                                $parts = $v -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
                                foreach ($p in $parts) { $script:allTags += [PSCustomObject]@{ Name = $k; Value = $p } }
                            }
                            elseif ($v -is [array]) { foreach ($val in $v) { $script:allTags += [PSCustomObject]@{ Name = $k; Value = $val } } }
                            elseif ($null -ne $v -and $v -ne "") { $script:allTags += [PSCustomObject]@{ Name = $k; Value = $v } }
                        }
                    }
                    if ($FormValues) {
                        foreach ($k in $FormValues.Keys) {
                            $v = $FormValues[$k]
                            $finalVal = if ($v.Content) { $v.Content } elseif ($v.Text) { $v.Text } else { $v }
                            
                            if ($finalVal -is [string] -and $finalVal -match ';') {
                                $parts = $finalVal -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
                                foreach ($p in $parts) { $script:allTags += [PSCustomObject]@{ Name = $k; Value = $p } }
                            }
                            elseif ($finalVal -is [array]) { foreach ($val in $finalVal) { $script:allTags += [PSCustomObject]@{ Name = $k; Value = $val } } }
                            elseif ($null -ne $finalVal -and $finalVal -ne "") { $script:allTags += [PSCustomObject]@{ Name = $k; Value = $finalVal } }
                        }
                    }

                    foreach ($c in $schemaDef) {
                        $isMulti = ($c.Type -eq "Choix Multiples")
                        if ($c.Type -eq "Nombre") { $gType = "Number" }
                        elseif ($isMulti -or $c.Type -eq "Choix") { $gType = "Choice" }
                        else { $gType = "Text" }
                        
                        $choices = @()
                        if ($gType -eq "Choice") {
                            # On cherche toutes les valeurs uniques pour ce tag dans la structure
                            $foundVals = $script:allTags | Where-Object { $_.Name -eq $c.Name } | ForEach-Object { if ($_.Value) { $_.Value } elseif ($_.Term) { $_.Term } } | Select-Object -Unique
                            if ($foundVals) { $choices = @($foundVals) }
                            else { $choices = @("Choix 1") } # Fallback si pas de valeur trouvée dans le JSON
                        }
                        
                        $resCol = New-AppGraphSiteColumn -SiteId $siteId -Name $c.Name -DisplayName $c.Name -Type $gType -Choices $choices -AllowMultiple:$isMulti
                        if ($resCol) { 
                            $colIds += $resCol.Column.id 
                            if ($resCol.Status -eq "Created") { Log "Colonne '$($c.Name)' : Créée avec $($choices.Count) options." "SUCCESS" }
                            else { Log "Colonne '$($c.Name)' : Mise à jour ($($choices.Count) options)." "INFO" }
                        }
                    }
                    
                    # --- ATTENTE PROPAGATION v4.19/4.21 ---
                    # SharePoint peut mettre du temps à rendre les colonnes disponibles sur les items
                    Start-Sleep -Seconds 3
                    
                    $ctSafeName = "SBuilder_" + ($FolderSchemaName -replace '[\\/:*?"<>|#%]', '_')
                    Log "Préparation du Modèle (Content Type) '$FolderSchemaName'..." "INFO"
                    $resCT = New-AppGraphContentType -SiteId $siteId -Name $ctSafeName -Description "Modèle '$FolderSchemaName' configuré via SharePointBuilder" -Group "SharePointBuilder" -BaseId "0x0120" -ColumnIdsToBind $colIds
                    
                    if ($resCT) {
                        $newCT = $resCT.ContentType
                        if ($resCT.Status -eq "Created") { Log "Modèle '$FolderSchemaName' : Créé avec succès." "SUCCESS" }
                        else { Log "Modèle '$FolderSchemaName' : Déjà existant." "INFO" }
                        Log "Attachement du Type de Contenu à la bibliothèque..." "INFO"
                        $addCtUri = "https://graph.microsoft.com/v1.0/sites/$siteId/lists/$listId/contentTypes/addCopy"
                        $bodyCtAdd = @{ contentType = $newCT.id }
                        try {
                            $resAdd = Invoke-MgGraphRequest -Method POST -Uri $addCtUri -Body $bodyCtAdd -ContentType "application/json" -ErrorAction Stop
                            $FolderContentTypeId = $resAdd.id
                            Log "Schéma attaché avec succès. CT_ID: $FolderContentTypeId" "SUCCESS"
                        }
                        catch {
                            Log "Attente confirmation d'attachement (déjà existant ?)..." "DEBUG"
                            $exCts = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/lists/$listId/contentTypes"
                            $lCt = $exCts.value | Where-Object { $_.name -eq $ctSafeName }
                            if ($lCt) { 
                                $FolderContentTypeId = $lCt.id 
                                Log "Type de contenu récupéré sur la liste. CT_ID: $FolderContentTypeId" "SUCCESS"
                            }
                            else {
                                Log "Impossible de trouver le ContentType sur la liste cible." "WARNING"
                            }
                        }
                    }
                }
            }
            catch {
                Err "Erreur fatale lors du traitement du Schéma '$FolderSchemaName' : $($_.Exception.Message)"
                return $result
            }
        }
        
        $structure = $StructureJson | ConvertFrom-Json
        $globalDeployId = if ($TrackingInfo -and $TrackingInfo.Count -gt 0) { [Guid]::NewGuid().ToString() } else { $null }

        $DeployedFoldersMap = @{}

        function New-AppGraphLinkFile {
            param($ParentItemId, $LinkName, $LinkUrl, $Tags)
            try {
                $linkContent = "[InternetShortcut]`nURL=$LinkUrl"
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($linkContent)
                $safeName = $LinkName
                if (-not $safeName.EndsWith(".url", [System.StringComparison]::OrdinalIgnoreCase)) { $safeName += ".url" }
                
                $uri = "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$driveId/items/$ParentItemId`:/$safeName`:/content"
                $fRes = Invoke-MgGraphRequest -Method PUT -Uri $uri -Body $bytes -ContentType "text/plain"
                Log "Lien créé : $safeName" "INFO"
                
                $mergedTags = [System.Collections.Generic.List[psobject]]::new()
                if ($Tags) { foreach ($t in $Tags) { $mergedTags.Add($t) } }
                
                if ($mergedTags.Count -gt 0) {
                    try {
                        $fInfo = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$driveId/items/$($fRes.id)?`$expand=listItem"
                        if ($fInfo.listItem) {
                            Update-AppGraphTags -SiteId $siteId -ListId $listId -ListItemId $fInfo.listItem.id -TagsConfig $mergedTags
                        }
                    }
                    catch { Log "Erreur application tags sur le lien '$safeName': $($_.Exception.Message)" "WARNING" }
                }
            }
            catch {
                Log "Erreur fatale création lien '$LinkName' : $($_.Exception.Message)" "WARNING"
            }
        }

        function Set-NewFolder {
            param($ParentItemId, $FolderObj)
            if ($FolderObj.Type -and $FolderObj.Type -ne "Folder") { Log "Type $($FolderObj.Type) ignoré en V2 pour le moment." "WARNING"; return }

            $folderName = $FolderObj.Name
            Log "Création dossier '$folderName'..." "INFO"
            
            $fRes = $null
            try {
                if ($ParentItemId -eq 'root') {
                    $fRes = New-AppGraphFolder -SiteId $siteId -DriveId $driveId -FolderName $folderName
                }
                else {
                    $body = @{ name = $folderName; folder = @{}; "@microsoft.graph.conflictBehavior" = "replace" } | ConvertTo-Json -Depth 5
                    $fRes = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$driveId/items/$ParentItemId/children" -Body $body -ContentType "application/json"
                }
                
                if ($FolderObj.Id -and $fRes -and $fRes.id) {
                    $DeployedFoldersMap[$FolderObj.Id] = $fRes.id
                }
            }
            catch { Err "CRASH création '$folderName' : $($_.Exception.Message)"; return }

            # Récupération systématique du ListItem si on a besoin de modifier les métadonnées (Tags ou CT)
            if ($FolderObj.Tags -or $globalDeployId -or $FolderContentTypeId -ne "0x0120") {
                try {
                    $fInfo = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$driveId/items/$($fRes.id)?`$expand=listItem"
                    $liId = $fInfo.listItem.id
                    
                    # --- Application du Content Type Avancé ---
                    if ($FolderContentTypeId -ne "0x0120") {
                        try {
                            $patchCtUri = "https://graph.microsoft.com/v1.0/sites/$siteId/lists/$listId/items/$liId"
                            $patchCtBody = @{ contentType = @{ id = $FolderContentTypeId } }
                            Invoke-MgGraphRequest -Method PATCH -Uri $patchCtUri -Body $patchCtBody -ContentType "application/json" -ErrorAction Stop | Out-Null
                            Log "Modèle '$FolderSchemaName' appliqué sur '$folderName'." "DEBUG"
                            # --- ATTENTE PROPAGATION ITEM v4.20/4.21 ---
                            Start-Sleep -Seconds 1
                        }
                        catch {
                            Log "Échec application Modèle sur '$folderName' : $($_.Exception.Message)" "WARNING"
                        }
                    }
                    
                    $mergedTags = [System.Collections.Generic.List[psobject]]::new()
                    if ($FolderObj.Tags) { foreach ($t in $FolderObj.Tags) { $mergedTags.Add($t) } }
                    
                    if ($mergedTags.Count -gt 0) { Update-AppGraphTags -SiteId $siteId -ListId $listId -ListItemId $liId -TagsConfig $mergedTags }
                }
                catch { Log "Impossible d'appliquer les métadonnées sur '$folderName' : $($_.Exception.Message)" "WARNING" }
            }

            if ($FolderObj.Permissions) {
                foreach ($perm in $FolderObj.Permissions) {
                    $email = $perm.Email
                    $role = switch ($perm.Level.ToLower()) { "full control" { "write" } "contribute" { "write" } default { "read" } }
                    try {
                        $inviteBody = @{
                            requireSignIn   = $true
                            sendSignInPromo = $false
                            roles           = @($role)
                            recipients      = @( @{ email = $email } )
                        } | ConvertTo-Json -Depth 5
                        Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$driveId/items/$($fRes.id)/invite" -Body $inviteBody -ContentType "application/json" | Out-Null
                        Log "Permission ajoutée Graph : $email ($role)" "INFO"
                    }
                    catch { Log "⚠️ Erreur permission Graph : $($_.Exception.Message)" "WARNING" }
                }
            }

            if ($FolderObj.Folders) {
                foreach ($sub in $FolderObj.Folders) { Set-NewFolder -ParentItemId $fRes.id -FolderObj $sub }
            }
        }

        $startItemId = if (-not [string]::IsNullOrWhiteSpace($TargetFolderItemId)) { $TargetFolderItemId } else { "root" }
        
        if (-not [string]::IsNullOrWhiteSpace($RootFolderName)) {
            Log "Création Racine: $RootFolderName" "INFO"
            $rootRes = New-AppGraphFolder -SiteId $siteId -DriveId $driveId -FolderName $RootFolderName -ParentFolderId $startItemId
            $startItemId = $rootRes.id
            $result.FinalUrl = $rootRes.webUrl
            if (($RootMetadata -and $RootMetadata.Count -gt 0) -or ($FolderContentTypeId -ne "0x0120")) {
                try {
                    $rInfo = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$driveId/items/$($rootRes.id)?`$expand=listItem"
                    $rLiId = $rInfo.listItem.id
                    
                    # --- Application du Content Type Avancé (Racine) ---
                    if ($FolderContentTypeId -ne "0x0120") {
                        try {
                            $patchCtUri = "https://graph.microsoft.com/v1.0/sites/$siteId/lists/$listId/items/$rLiId"
                            $patchCtBody = @{ contentType = @{ id = $FolderContentTypeId } }
                            Invoke-MgGraphRequest -Method PATCH -Uri $patchCtUri -Body $patchCtBody -ContentType "application/json" -ErrorAction Stop | Out-Null
                            Log "Modèle '$FolderSchemaName' appliqué sur la racine '$RootFolderName'." "DEBUG"
                            # --- ATTENTE PROPAGATION RACINE v4.20/4.21 ---
                            Start-Sleep -Seconds 2
                        }
                        catch {
                            Log "Échec application Modèle sur la racine : $($_.Exception.Message)" "WARNING"
                        }
                    }
                    
                    if ($RootMetadata -and $RootMetadata.Count -gt 0) {
                        $metaTags = @()
                        foreach ($k in $RootMetadata.Keys) { $metaTags += [PSCustomObject]@{ Name = $k; Value = $RootMetadata[$k] } }
                        Update-AppGraphTags -SiteId $siteId -ListId $listId -ListItemId $rLiId -TagsConfig $metaTags
                    }
                }
                catch { Log "Erreur maj métadonnées racine: $($_.Exception.Message)" "WARNING" }
            }
        }
        if ($structure.Folders) {
            foreach ($sub in $structure.Folders) { Set-NewFolder -ParentItemId $startItemId -FolderObj $sub }
        }

        Log "--- DÉBUT DE LA PASSE 2 : CONTENUS (Flat JSON) ---" "INFO"
        $flatCollections = @(
            @($structure.Publications),
            @($structure.Links),
            @($structure.InternalLinks),
            @($structure.Files)
        )
        
        foreach ($collection in $flatCollections) {
            if ($null -ne $collection -and $collection.Count -gt 0) {
                foreach ($item in $collection) {
                    $targetItemId = $startItemId
                    if (-not [string]::IsNullOrWhiteSpace($item.ParentId) -and $DeployedFoldersMap.ContainsKey($item.ParentId)) {
                        $targetItemId = $DeployedFoldersMap[$item.ParentId]
                    }
                    elseif (-not [string]::IsNullOrWhiteSpace($item.ParentId)) {
                        Log "⚠️ Parent (ID: $($item.ParentId)) introuvable pour '$($item.Name)'. Création à la racine." "WARNING"
                    }
                    
                    if ($item.Type -eq "Link") {
                        New-AppGraphLinkFile -ParentItemId $targetItemId -LinkName $item.Name -LinkUrl $item.Url -Tags $item.Tags
                    }
                    elseif ($item.Type -eq "InternalLink") {
                        $targetNodeId = $item.TargetNodeId
                        if ($targetNodeId -and $DeployedFoldersMap.ContainsKey($targetNodeId)) {
                            $targetGraphId = $DeployedFoldersMap[$targetNodeId]
                            try {
                                $tInfo = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$driveId/items/$targetGraphId"
                                $linkUrl = $tInfo.webUrl
                                New-AppGraphLinkFile -ParentItemId $targetItemId -LinkName $item.Name -LinkUrl $linkUrl -Tags $item.Tags
                            }
                            catch { Log "Impossible de résoudre le nœud cible de l'InternalLink" "WARNING" }
                        }
                        else {
                            Log "⚠️ Impossible de résoudre le dossier cible pour l'InternalLink $($item.Name)." "WARNING"
                        }
                    }
                    elseif ($item.Type -eq "File") {
                        if ($item.SourceUrl) {
                            try {
                                Log "Téléchargement et Upload du fichier : $($item.Name)" "DEBUG"
                                # Utilisation de HttpClient pour le stream
                                $client = New-Object System.Net.Http.HttpClient
                                $fileBytes = $client.GetByteArrayAsync($item.SourceUrl).Result
                                
                                $uploadUri = "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$driveId/items/$targetItemId`:/$($item.Name)`:/content"
                                $fRes = Invoke-MgGraphRequest -Method PUT -Uri $uploadUri -Body $fileBytes -ContentType "application/octet-stream"
                                Log "Fichier créé : $($item.Name)" "INFO"
                                
                                if ($item.Tags) {
                                    $fInfo = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$driveId/items/$($fRes.id)?`$expand=listItem"
                                    Update-AppGraphTags -SiteId $siteId -ListId $listId -ListItemId $fInfo.listItem.id -TagsConfig $item.Tags
                                }
                            }
                            catch { Log "Échec transfert fichier $($item.Name) : $($_.Exception.Message)" "WARNING" }
                        }
                    }
                    elseif ($item.Type -eq "Publication") {
                        # Simulation simple d'une publication par un lien URL vers le dossier cible
                        $pubName = "Publication - " + $item.Name
                        $pubUrl = $TargetSiteUrl # @todo: Mieux gérer l'URL cible
                        New-AppGraphLinkFile -ParentItemId $targetItemId -LinkName $pubName -LinkUrl $pubUrl -Tags $item.Tags
                        Log "Publication simulée via lien : $pubName" "INFO"
                    }
                }
            }
        }
        
    }
    catch { Err "Erreur fatale déploiement Graph : $($_.Exception.Message)" }
    return $result
}
