# Modules/Toolbox.SharePoint/Functions/New-AppSPStructure.ps1

<#
.SYNOPSIS
    Déploie une structure documentaire sur SharePoint via Microsoft Graph API.
.DESCRIPTION
    Nouvelle version unifiée (v5.0) qui remplace PnP par Graph API.
    Interprète le JSON via Get-AppSPDeploymentPlan et exécute les opérations à plat.
#>
function New-AppSPStructure {
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

    $result = @{ Success = $true; Logs = [System.Collections.Generic.List[string]]::new(); Errors = [System.Collections.Generic.List[string]]::new(); FinalUrl = ""; Maintenance = @{ HistoryUrl = $null; StatesUrl = $null } }

    function Log { param($m, $l = "Info") Write-AppLog -Message $m -Level $l -Collection $result.Logs -PassThru }
    function Err { param($m) $result.Success = $false; Write-AppLog -Message $m -Level Error -Collection $result.Errors; Write-AppLog -Message $m -Level Error -Collection $result.Logs -PassThru }

    try {
        Log "Initialisation du moteur de déploiement unifié (Graph v5.0)..." "DEBUG"
        
        # 1. AUTHENTICATION
        Connect-AppAzureCert -TenantId $TenantName -ClientId $ClientId -Thumbprint $Thumbprint | Out-Null
        
        # 2. RESOLUTION IDS
        $siteId = Get-AppGraphSiteId -SiteUrl $TargetSiteUrl
        if (-not $siteId) { throw "Impossible de résoudre le SiteId." }
        
        $libDrive = Get-AppGraphListDriveId -SiteId $siteId -ListDisplayName $TargetLibraryName
        if (-not $libDrive -or -not $libDrive.DriveId) { throw "Bibliothèque '$TargetLibraryName' introuvable." }
        
        $listId = $libDrive.ListId
        $driveId = $libDrive.DriveId

        # 3. GÉNÉRATION DU PLAN
        Log "Analyse de la structure et génération du plan..." "DEBUG"
        $plan = Get-AppSPDeploymentPlan -StructureJson $StructureJson -FormValues $FormValues -RootMetadata $RootMetadata

        # 4. GESTION DU SCHEMA (CONTENT TYPE) SI APPLICABLE
        $FolderContentTypeId = "0x0120"
        $MultiChoiceColumns = @()
        $SchemaMapping = @{}
        
        if ($FolderSchemaJson -and $FolderSchemaName) {
            Log "Vérification du schéma sur le site (Optimisation Cache)..." "DEBUG"
            $siteColsCache = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$SiteId/columns?`$select=id,name,displayName,columnGroup,indexed" -ErrorAction SilentlyContinue
            $siteCtsCache = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$SiteId/contentTypes" -ErrorAction SilentlyContinue

            Log "Vérification/Création du modèle de dossier : $FolderSchemaName" "INFO"
            try {
                $schemaDef = $FolderSchemaJson | ConvertFrom-Json
                $colIds = @()
                foreach ($c in $schemaDef) {
                    $kLow = $c.Name.ToLower()
                    Log "  Colonne : $($c.Name) ($($c.Type))" "DEBUG"
                    $isMulti = ($c.Type -eq "Choix Multiples")
                    if ($isMulti) { $MultiChoiceColumns += $kLow }

                    $gType = "Text"
                    if ($c.Type -eq "Nombre") { $gType = "Number" }
                    elseif ($c.Type -like "Choix*") { $gType = "Choice" }
                    elseif ($c.Type -eq "Date et Heure") { $gType = "DateTime" }
                    elseif ($c.Type -eq "Oui/Non") { $gType = "Boolean" }
                    
                    $choices = @()
                    if ($gType -eq "Choice") {
                        $allVals = $plan | ForEach-Object { if ($_.Tags) { $_.Tags | Where-Object { $_.Name -eq $c.Name } | Select-Object -ExpandProperty Value } }
                        $choices = $allVals | Select-Object -Unique | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                        if (-not $choices -or $choices.Count -eq 0) { $choices = @("Valeur 1") }
                    }

                    $colIndexed = $c.Indexed
                    if ($isMulti -and $colIndexed) {
                        Log "    (!) L'indexation est désactivée pour la colonne multi-choix '$($c.Name)' (Restriction SharePoint)." "WARNING"
                        $colIndexed = $false
                    }

                    $resCol = New-AppGraphSiteColumn -SiteId $siteId -Name $c.Name -DisplayName $c.Name -Type $gType -Choices $choices -AllowMultiple:$isMulti -Indexed:$colIndexed -ColumnCache $siteColsCache
                    if ($resCol) { 
                        $colIds += $resCol.Column.id
                        $realInternalName = $resCol.Column.name
                        $SchemaMapping[$kLow] = $realInternalName
                    }
                }

                $ctSafeName = "SBuilder_" + ($FolderSchemaName -replace '[\\/:*?"<>|#%]', '_')
                $resCT = New-AppGraphContentType -SiteId $siteId -Name $ctSafeName -Description "Modèle $FolderSchemaName" -Group "SBuilder" -BaseId "0x0120" -ColumnIdsToBind $colIds -ContentTypeCache $siteCtsCache
                
                if ($resCT) {
                    $addCtUri = "https://graph.microsoft.com/v1.0/sites/$siteId/lists/$listId/contentTypes/addCopy"
                    $bodyCtAdd = @{ contentType = $resCT.ContentType.id } | ConvertTo-Json -Compress
                    $ctAttached = $false
                    try {
                        for ($i = 1; $i -le 2; $i++) {
                            try {
                                Invoke-MgGraphRequest -Method POST -Uri $addCtUri -Body $bodyCtAdd -ContentType "application/json" -ErrorAction Stop | Out-Null
                                $ctAttached = $true
                                Log "Modèle '$FolderSchemaName' attaché à la liste." "SUCCESS"
                                break
                            } catch {
                                if ($_.Exception.Message -match "already exists" -or $_.Exception.Message -match "409") {
                                    $ctAttached = $true; break
                                }
                                Log "  Attachement modèle impossible (tentative $i/2)..." "DEBUG"
                                if ($i -lt 2) { Start-Sleep -Seconds 5 }
                            }
                        }
                    } catch { Log "Erreur copie Content Type : $($_.Exception.Message)" "WARNING" }

                    if ($ctAttached) {
                        $exCts = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/lists/$listId/contentTypes"
                        $lCt = $exCts.value | Where-Object { $_.name -eq $ctSafeName }
                        if ($lCt) { $FolderContentTypeId = $lCt.id }
                    }

                    # Vérification / Fallback
                    $columnsReady = $false
                    $listCols = $null
                    if ($ctAttached) {
                        Log "  Vérification de la présence des colonnes (via CT)..." "DEBUG"
                        for ($w = 1; $w -le 4; $w++) {
                            $listCols = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/lists/$listId/columns" -ErrorAction SilentlyContinue
                            if ($listCols -and $listCols.value) {
                                $foundCount = ($schemaDef | Where-Object { $cn = $_.Name; $listCols.value | Where-Object { $_.displayName -eq $cn } }).Count
                                if ($foundCount -eq $schemaDef.Count) { $columnsReady = $true; break }
                            }
                            Start-Sleep -Seconds 5
                        }
                    }

                    if (-not $columnsReady) {
                        Log "  Utilisation du mode FALLBACK (Binding individuel ultra-robuste)..." "WARNING"
                        $listColsUrl = "https://graph.microsoft.com/v1.0/sites/$siteId/lists/$listId/columns"
                        $currentListCols = Invoke-MgGraphRequest -Method GET -Uri $listColsUrl -ErrorAction SilentlyContinue
                        
                        foreach ($cId in $colIds) {
                            $alreadyPresent = $false
                            if ($currentListCols -and $currentListCols.value) {
                                $alreadyPresent = $currentListCols.value | Where-Object { $_.id -eq $cId -or $_.sourceColumn.id -eq $cId }
                            }
                            if ($alreadyPresent) { continue }

                            try {
                                $bindPayload = @{ id = $cId } | ConvertTo-Json
                                Invoke-MgGraphRequest -Method POST -Uri $listColsUrl -Body $bindPayload -ContentType "application/json" -ErrorAction Stop | Out-Null
                                Start-Sleep -Milliseconds 500
                            } catch {
                                if ($_.Exception.Message -notmatch "already exists|409|404") {
                                    Log "    ⚠️ Échec binding colonne $cId : $($_.Exception.Message)" "WARNING"
                                }
                            }
                        }
                        $listCols = Invoke-MgGraphRequest -Method GET -Uri $listColsUrl -ErrorAction SilentlyContinue
                        $columnsReady = $true 
                    }

                    if ($columnsReady -and $listCols -and $listCols.value) {
                        foreach ($col in $listCols.value) {
                            $kLow = $col.displayName.ToLower()
                            if ($SchemaMapping.ContainsKey($kLow)) { 
                                $SchemaMapping[$kLow] = $col.name 
                                Log "    Mapping final : $($col.displayName) -> $($col.name)" "DEBUG"
                            }
                        }
                    }
                }
            } catch { Log "Erreur critique sur le Schéma : $($_.Exception.Message)" "ERROR" }
        }

        # 5. EXECUTION DU PLAN
        $DeployedFoldersMap = @{} 
        $startParentId = if ($TargetFolderItemId) { $TargetFolderItemId } else { "root" }

        # 3.ter RÉSOLUTION DU MAPPING FORMULAIRE -> METADONNÉE (Via Définition du Formulaire)
        $FormFieldMapping = @{}
        if ($TrackingInfo -and $TrackingInfo.FormDefinitionJson) {
            try {
                $formDef = $TrackingInfo.FormDefinitionJson | ConvertFrom-Json
                # On supporte le format { Layout = [ { Name, TargetColumnInternalName }, ... ] }
                if ($formDef.Layout) {
                    foreach ($field in $formDef.Layout) {
                        if ($field.Name -and $field.TargetColumnInternalName) {
                            $FormFieldMapping[$field.Name.ToLower()] = $field.TargetColumnInternalName
                        }
                    }
                }
            } catch { Log "Erreur analyse mapping formulaire." "WARNING" }
        }

        # Helper pour formater les champs pour Graph
        $FormatFields = {
            param([hashtable]$InputFields)
            if ($null -eq $InputFields) { return @{} }
            $final = @{}
            foreach ($k in $InputFields.Keys) {
                $val = $InputFields[$k]
                
                # Résolution du nom interne réel via le schéma OU le mapping du formulaire
                $kLow = $k.ToLower()
                $finalKey = if ($SchemaMapping.ContainsKey($kLow)) { $SchemaMapping[$kLow] } 
                            elseif ($FormFieldMapping.ContainsKey($kLow)) { $FormFieldMapping[$kLow] }
                            else { $k }
                
                $finalKeyLow = $finalKey.ToLower()

                # Détection robuste du format Collection(Edm.String)
                $isExplicitMulti = ($MultiChoiceColumns -and ($MultiChoiceColumns -contains $finalKeyLow))
                $isImplicitMulti = ($val -is [array] -and $val.Count -gt 0)

                if ($isExplicitMulti -or $isImplicitMulti) {
                    # Réactivation de l'annotation @odata.type pour Graph v1.0
                    $collectionType = "Collection(Edm.String)"
                    $final["$finalKey`@odata.type"] = $collectionType
                    
                    if ($val -is [string]) { $final[$finalKey] = @($val) }
                    elseif ($val -is [array]) { $final[$finalKey] = $val }
                    else { $final[$finalKey] = @($val.ToString()) }
                }
                else {
                    $final[$finalKey] = $val
                }
            }
            return $final
        }.GetNewClosure()
                    
        # -- Gestion de la Racine (Création ou Utilisation de l'existant) --
        $baseFolderId = $startParentId
        if (-not [string]::IsNullOrWhiteSpace($RootFolderName)) {
            Log "Traitement Racine : $RootFolderName" "INFO"
            $rootRes = New-AppGraphFolder -SiteId $siteId -DriveId $driveId -FolderName $RootFolderName -ParentFolderId $startParentId
            $baseFolderId = $rootRes.id
            $result.FinalUrl = $rootRes.webUrl
        }
        else {
            # Si pas de nom de dossier racine, la "racine" du déploiement est le dossier cible
            Log "Déploiement direct dans le dossier cible (ID: $baseFolderId)" "DEBUG"
        }
        
        $DeployedFoldersMap["root"] = $baseFolderId
        $startParentId = $baseFolderId # Pour que les enfants se créent au bon endroit

        # Application CT & Meta sur la racine (Dossier créé ou dossier cible)
        if ($RootMetadata -or $FolderContentTypeId -ne "0x0120") {
            try {
                # Logique de Retry pour pallier l'Eventual Consistency de Graph
                $liReq = $null
                for ($i = 1; $i -le 3; $i++) {
                    try {
                        $liReq = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$driveId/items/$baseFolderId/listItem?`$select=id" -ErrorAction Stop
                        if ($liReq) { break }
                    }
                    catch { 
                        Log "  Attente indexation listItem racine (tentative $i/3)..." "DEBUG"
                        Start-Sleep -Seconds 2 
                    }
                }
                
                if ($liReq) {
                    $fields = @{}
                    if ($RootMetadata) { $fields = & $FormatFields -InputFields $RootMetadata }
                    
                    $ctArg = if ($FolderContentTypeId -ne "0x0120") { $FolderContentTypeId } else { $null }
                    
                    if ($fields.Count -gt 0 -or $ctArg) {
                        Set-AppGraphListItemMetadata -SiteId $siteId -ListId $listId -ListItemId $liReq.id -Fields $fields -ContentTypeId $ctArg | Out-Null
                    }
                }
            }
            catch { Log "Erreur application Metadata racine : $_" "WARNING" }
        }

        # --- ÉTAPE 1 : CRÉATION DES DOSSIERS ---
        Log "Phase 1 : Création des dossiers..." "INFO"
        foreach ($op in ($plan | Where-Object { $_.Type -eq "Folder" })) {
            $parentId = $startParentId
            if ($op.ParentId -and $op.ParentId -ne "root" -and $DeployedFoldersMap.ContainsKey($op.ParentId)) {
                $parentId = $DeployedFoldersMap[$op.ParentId]
            }

            Log "Création : $($op.Name)" "INFO"
            $fRes = New-AppGraphFolder -SiteId $siteId -DriveId $driveId -FolderName $op.Name -ParentFolderId $parentId
            if ($op.Id) { $DeployedFoldersMap[$op.Id] = $fRes.id }
        }

        # --- ÉTAPE 2 : APPLICATION DES PERMISSIONS ---
        Log "Phase 2 : Application des permissions..." "INFO"
        foreach ($op in ($plan | Where-Object { $_.Type -eq "Folder" -and $_.Permissions })) {
            if (-not $op.Id -or -not $DeployedFoldersMap.ContainsKey($op.Id)) { continue }
            $folderItemId = $DeployedFoldersMap[$op.Id]

            foreach ($p in $op.Permissions) {
                $role = switch ($p.Level.ToLower()) { "full control" { "write" } "contribute" { "write" } default { "read" } }
                $inviteBody = @{ recipients = @( @{ email = $p.Email } ); roles = @($role); requireSignIn = $true; sendInvite = $false } | ConvertTo-Json -Depth 5
                try {
                    Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$driveId/items/$folderItemId/invite" -Body $inviteBody -ContentType "application/json" -ErrorAction Stop | Out-Null
                    Log "  Permission '$role' appliquée pour $($p.Email)" "SUCCESS"
                }
                catch { 
                    if ($_.Exception.Message -match "Forbidden") {
                        Log "  Permission pour $($p.Email) ignorée (potentiellement déjà présent par héritage)." "WARNING"
                    } else {
                        Log "  Erreur invitation pour $($p.Email) : $($_.Exception.Message)" "WARNING" 
                    }
                }
            }
        }

        # --- ÉTAPE 3 : APPLICATION DES MÉTADONNÉES ---
        Log "Phase 3 : Application des Tags et Content Types..." "INFO"
        foreach ($op in ($plan | Where-Object { $_.Type -eq "Folder" })) {
            if (-not $op.Id -or -not $DeployedFoldersMap.ContainsKey($op.Id)) { continue }
            $folderItemId = $DeployedFoldersMap[$op.Id]
            
            $rawFields = @{}
            if ($op.Tags) { 
                foreach ($t in $op.Tags) { 
                    $finalName = $t.Name
                    if ($rawFields.ContainsKey($finalName)) {
                        if ($rawFields[$finalName] -isnot [array]) { $rawFields[$finalName] = @($rawFields[$finalName]) }
                        if ($rawFields[$finalName] -notcontains $t.Value) { $rawFields[$finalName] += $t.Value }
                    }
                    else { $rawFields[$finalName] = $t.Value }
                } 
            }
            
            $finalFields = & $FormatFields -InputFields $rawFields
            
            # Application
            $applyCT = ($FolderSchemaJson -and $FolderSchemaName)
            $ctArg = if ($applyCT) { $FolderContentTypeId } else { $null }

            if ($finalFields.Count -gt 0 -or $ctArg) {
                try {
                    $liReq = $null
                    for ($i = 1; $i -le 3; $i++) {
                        try {
                            $liReq = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$driveId/items/$folderItemId/listItem?`$select=id" -ErrorAction Stop
                            if ($liReq) { break }
                        }
                        catch { 
                            Log "  Attente indexation listItem pour $($op.Name) (tentative $i/3)..." "DEBUG"
                            Start-Sleep -Seconds 2 
                        }
                    }

                    if ($liReq) {
                        Log "  Application Tags/CT sur $($op.Name) (ListItem ID: $($liReq.id)) | CT: $ctArg" "DEBUG"
                        Set-AppGraphListItemMetadata -SiteId $siteId -ListId $listId -ListItemId $liReq.id -Fields $finalFields -ContentTypeId $ctArg | Out-Null
                        Log "  Metadata appliqués." "SUCCESS"
                    }
                    else { throw "Impossible de récupérer le ListItem ID après 3 tentatives." }
                }
                catch { 
                    Log "Erreur application Metadata sur $($op.Name) : $_" "WARNING" 
                    if ($_.Exception.Message -like "*Bad Request*") {
                        Log "  Détail Erreur : Les noms de colonnes ou les formats de données sont incorrects." "DEBUG"
                    }
                }
            }
        }

        # --- ÉTAPE 4 : CRÉATION DES LIENS ---
        Log "Phase 4 : Création des Liens (Externes & Internes)..." "INFO"
        foreach ($op in ($plan | Where-Object { $_.Type -eq "Link" -or $_.Type -eq "InternalLink" })) {
            $parentId = $startParentId
            if ($op.ParentId -and $op.ParentId -ne "root" -and $DeployedFoldersMap.ContainsKey($op.ParentId)) {
                $parentId = $DeployedFoldersMap[$op.ParentId]
            }

            $targetUrl = ""
            if ($op.Type -eq "Link") {
                $targetUrl = $op.RawNode.Url
            }
            elseif ($op.Type -eq "InternalLink") {
                Log "Lien interne : $($op.Name)" "INFO"
                if ($op.RawNode.TargetNodeId -and $DeployedFoldersMap.ContainsKey($op.RawNode.TargetNodeId)) {
                    $targetItemId = $DeployedFoldersMap[$op.RawNode.TargetNodeId]
                    try {
                        $tItem = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$driveId/items/$($targetItemId)?`$select=webUrl" -ErrorAction Stop
                        $targetUrl = $tItem.webUrl
                        
                        Log "Création lien interne : $($op.Name) -> $targetUrl" "INFO"
                        $linkContent = "[InternetShortcut]`nURL=$targetUrl"
                        $bytes = [System.Text.Encoding]::UTF8.GetBytes($linkContent)
                        $safeName = if ($op.Name -like "*.url") { $op.Name } else { "$($op.Name).url" }
                        $uriUpload = "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$driveId/items/$parentId`:/$safeName`:/content"
                        Invoke-MgGraphRequest -Method PUT -Uri $uriUpload -Body $bytes -ContentType "text/plain" | Out-Null
                    }
                    catch { Log "Erreur résolution URL interne $($op.Name) : $_" "WARNING" }
                }
            }

            if ($targetUrl) {
                $safeName = if ($op.Name -like "*.url") { $op.Name } else { "$($op.Name).url" }
                Log "Création lien : $safeName dans parent ID $parentId" "INFO"
                $linkContent = "[InternetShortcut]`nURL=$targetUrl"
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($linkContent)
                $uriUpload = "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$driveId/items/$parentId`:/$safeName`:/content"
                Invoke-MgGraphRequest -Method PUT -Uri $uriUpload -Body $bytes -ContentType "text/plain" | Out-Null
            }
        }

        # --- ÉTAPE 5 : IMPORT DES FICHIERS ET PUBLICATIONS ---
        Log "Phase 5 : Import des Fichiers et Publications..." "INFO"
        foreach ($op in ($plan | Where-Object { $_.Type -eq "File" -or $_.Type -eq "Publication" })) {
            
            if ($op.Type -eq "File") {
                $parentId = $startParentId
                if ($op.ParentId -and $op.ParentId -ne "root" -and $DeployedFoldersMap.ContainsKey($op.ParentId)) {
                    $parentId = $DeployedFoldersMap[$op.ParentId]
                }
                
                Log "Import fichier : $($op.Name)" "INFO"
                if ($op.RawNode.SourceUrl) {
                    try {
                        $client = New-Object System.Net.Http.HttpClient
                        $fileBytes = $client.GetByteArrayAsync($op.RawNode.SourceUrl).Result
                        $uriFile = "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$driveId/items/$parentId`:/$($op.Name)`:/content"
                        Invoke-MgGraphRequest -Method PUT -Uri $uriFile -Body $fileBytes -ContentType "application/octet-stream" | Out-Null
                    }
                    catch { Log "Erreur import $($op.Name) : $_" "WARNING" }
                }
            }
            elseif ($op.Type -eq "Publication") {
                Log "Création Publication : $($op.Name)" "INFO"
                $sourceUrl = ""
                if ($op.ParentId -and $DeployedFoldersMap.ContainsKey($op.ParentId)) {
                    $sourceItemId = $DeployedFoldersMap[$op.ParentId]
                    try {
                        $srcItem = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$driveId/items/$($sourceItemId)?`$select=webUrl" -ErrorAction Stop
                        $sourceUrl = $srcItem.webUrl
                    }
                    catch { Log "Erreur obtention URL source pour publication" "WARNING" }
                }

                if ($sourceUrl) {
                    $targetRaw = if ($op.RawNode.TargetFolderPath) { $op.RawNode.TargetFolderPath } else { "/Shared Documents" }
                    $pParts = $targetRaw -split "/" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                    $pubLibName = if ($pParts.Count -gt 0) { $pParts[0] } else { "Shared Documents" }
                    $pubRelSubPath = $op.RawNode.TargetFolderPath -replace "^.*?$([regex]::Escape($pubLibName))", "" -replace "^/", ""
                    
                    if ($op.RawNode.UseFormName -and $RootFolderName) {
                        $pubRelSubPath = if ([string]::IsNullOrWhiteSpace($pubRelSubPath)) { $RootFolderName } else { "$pubRelSubPath/$RootFolderName" }
                    }

                    try {
                        $pubDriveRes = Get-AppGraphListDriveId -SiteId $siteId -ListDisplayName $pubLibName
                        $pDriveId = $pubDriveRes.DriveId
                        $folders = $pubRelSubPath -split "/" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                        $currentParent = "root"
                        foreach ($fName in $folders) {
                            $isNewProjectFolder = ($fName -eq $RootFolderName)
                            try {
                                $fRes = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$pDriveId/items/$currentParent/children?`$filter=name eq '$fName'" -ErrorAction Stop
                                if ($fRes.value.Count -gt 0) {
                                    $currentParent = $fRes.value[0].id
                                } else {
                                    $fCreated = New-AppGraphFolder -SiteId $siteId -DriveId $pDriveId -FolderName $fName -ParentFolderId $currentParent
                                    $currentParent = $fCreated.id
                                }
                            } catch { 
                                $fCreated = New-AppGraphFolder -SiteId $siteId -DriveId $pDriveId -FolderName $fName -ParentFolderId $currentParent
                                $currentParent = $fCreated.id
                            }

                            if ($isNewProjectFolder -and $op.RawNode.UseFormMetadata -and $RootMetadata) {
                                try {
                                    $pLiReq = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$pDriveId/items/$currentParent/listItem?`$select=id" -ErrorAction Stop
                                    $pFields = & $FormatFields -InputFields $RootMetadata
                                    if ($pFields.Count -gt 0) {
                                        Set-AppGraphListItemMetadata -SiteId $siteId -ListId $pubDriveRes.ListId -ListItemId $pLiReq.id -Fields $pFields | Out-Null
                                    }
                                } catch { Log "  Erreur application Meta publication ($fName) : $_" "WARNING" }
                            }
                        }

                        $linkContent = "[InternetShortcut]`nURL=$sourceUrl"
                        $bytes = [System.Text.Encoding]::UTF8.GetBytes($linkContent)
                        $fileName = if ($op.Name -like "*.url") { $op.Name } else { "$($op.Name).url" }
                        $uriPub = "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$pDriveId/items/$currentParent`:/$fileName`:/content"
                        Invoke-MgGraphRequest -Method PUT -Uri $uriPub -Body $bytes -ContentType "text/plain" -ErrorAction Stop | Out-Null
                        Log "  Publication réussie dans $pubLibName/$pubRelSubPath" "SUCCESS"
                    }
                    catch { Log "Erreur exécution publication : $_" "WARNING" }
                }
            }
        }

        # 6. TRACKING
        if ($TrackingInfo -and $siteId) {
            Log "Enregistrement dans l'historique (Tracking Graph)..." "INFO"
            try {
                $trackLibName = "SharePointBuilder_Tracking"
                $trackListId = $null
                $listsRes = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/lists?`$select=id,displayName,webUrl"
                $foundTrack = $listsRes.value | Where-Object { $_.displayName -eq $trackLibName }
                
                if ($foundTrack) {
                    $trackListId = $foundTrack.id
                    $result.Maintenance.HistoryUrl = $foundTrack.webUrl
                } else {
                    $trackDef = @{
                        displayName = $trackLibName
                        columns = @(
                            @{ name = "TargetUrl"; text = @{} },
                            @{ name = "TemplateId"; text = @{} },
                            @{ name = "TemplateVersion"; text = @{} },
                            @{ name = "ConfigName"; text = @{} },
                            @{ name = "NamingRuleId"; text = @{} },
                            @{ name = "DeployedBy"; text = @{} },
                            @{ name = "TemplateJson"; text = @{ allowMultipleLines = $true } },
                            @{ name = "FormValuesJson"; text = @{ allowMultipleLines = $true } },
                            @{ name = "FormDefinitionJson"; text = @{ allowMultipleLines = $true } },
                            @{ name = "FolderSchemaJson"; text = @{ allowMultipleLines = $true } },
                            @{ name = "DeployedDate"; dateTime = @{} },
                            # Nouvelles colonnes de contrôle (v5.1)
                            @{ name = "CreateRootFolder"; boolean = @{} },
                            @{ name = "ApplyMetadata"; boolean = @{} },
                            @{ name = "OverwritePermissions"; boolean = @{} },
                            @{ name = "StateFileId"; text = @{} }
                        )
                        list = @{ template = "genericList"; hidden = $true }
                    } | ConvertTo-Json -Depth 5 -Compress
                    $tRes = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/lists" -Body ([System.Text.Encoding]::UTF8.GetBytes($trackDef)) -ContentType "application/json" -ErrorAction Stop
                    $trackListId = $tRes.id
                    $result.Maintenance.HistoryUrl = $tRes.webUrl
                }

                if ($trackListId) {
                    # Récupération de l'utilisateur authentifié (v5.2)
                    $me = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/me" -ErrorAction SilentlyContinue
                    $authUser = if ($me -and $me.displayName) { $me.displayName } else { "SharepointApp" }

                    $itemFields = @{
                        Title                = if ($TrackingInfo.TemplateId) { $TrackingInfo.TemplateId } else { "UNKNOWN" }
                        TargetUrl            = if ($result.FinalUrl) { $result.FinalUrl } else { "$TargetSiteUrl/$TargetLibraryName/$RootFolderName" }
                        TemplateId           = $TrackingInfo.TemplateId
                        TemplateVersion      = $TrackingInfo.TemplateVersion
                        ConfigName           = $TrackingInfo.ConfigName
                        NamingRuleId         = $TrackingInfo.NamingRuleId
                        DeployedBy           = $authUser
                        TemplateJson         = $StructureJson
                        FormValuesJson       = if ($FormValues) { $FormValues | ConvertTo-Json -Depth 5 -Compress } else { "" }
                        FormDefinitionJson   = $TrackingInfo.FormDefinitionJson
                        FolderSchemaJson     = $FolderSchemaJson
                        DeployedDate         = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
                        # Valeurs des colonnes de contrôle (Forçage booléen strict)
                        CreateRootFolder     = if ($TrackingInfo.CreateRootFolder) { $true } else { $false }
                        ApplyMetadata        = if ($TrackingInfo.ApplyMetadata) { $true } else { $false }
                        OverwritePermissions = if ($TrackingInfo.OverwritePermissions) { $true } else { $false }
                    }
                    $itemBody = @{ fields = $itemFields } | ConvertTo-Json -Depth 5 -Compress
                    $trackItemRes = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/lists/$trackListId/items" -Body ([System.Text.Encoding]::UTF8.GetBytes($itemBody)) -ContentType "application/json" -ErrorAction Stop
                    $trackItemId = $trackItemRes.id
                    Log "  > Historique enregistré (ID: $trackItemId)." "DEBUG"
                }
            } catch { Log "  > Erreur Tracking : $_" "WARNING" }
        }

        # Export mapping local JSON ID -> Microsoft Graph ListItem ID (pour State In-Situ)
        $result.DeployedNodes = $DeployedFoldersMap

        if ($TrackingInfo -and $TrackingInfo.TemplateId -and $DeployedFoldersMap.ContainsKey("root")) {
            $rootId = $DeployedFoldersMap["root"]
            if (-not [string]::IsNullOrWhiteSpace($rootId)) {
                Log "Génération et sauvegarde du state.json In-Situ..." "INFO"
                try {
                    $stateLibName = "SharePointBuilder_States"
                    $stateDriveId = $null
                    
                    # Réutilisation de l'énumération des listes pour l'URL d'état
                    $foundState = $listsRes.value | Where-Object { $_.displayName -eq $stateLibName }

                    try {
                        $stateDriveRes = Get-AppGraphListDriveId -SiteId $siteId -ListDisplayName $stateLibName
                        $stateDriveId = $stateDriveRes.DriveId
                        if ($foundState) { $result.Maintenance.StatesUrl = $foundState.webUrl }
                    } catch {
                        $newListBody = @{ displayName = $stateLibName; list = @{ template = "documentLibrary"; hidden = $true } } | ConvertTo-Json -Depth 5 -Compress
                        $sRes = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/lists" -Body ([System.Text.Encoding]::UTF8.GetBytes($newListBody)) -ContentType "application/json" -ErrorAction Stop
                        $stateDriveRes = Get-AppGraphListDriveId -SiteId $siteId -ListDisplayName $stateLibName
                        $stateDriveId = $stateDriveRes.DriveId
                        $result.Maintenance.StatesUrl = $sRes.webUrl
                    }

                    if ($stateDriveId) {
                        $stateRes = Save-AppSPDeploymentState -SiteId $siteId -StateDriveId $stateDriveId -TargetDriveId $driveId -RootFolderItemId $rootId -DeployedNodes $DeployedFoldersMap -TemplateId $TrackingInfo.TemplateId -FormValues $FormValues -CreateRootFolder $TrackingInfo.CreateRootFolder -ApplyMetadata $TrackingInfo.ApplyMetadata -OverwritePermissions $TrackingInfo.OverwritePermissions
                        if ($stateRes -and $stateRes.id -and $trackItemId) {
                            # Mise à jour rétroactive du tracking avec le StateFileId (v5.1)
                            Log "  > Liaison StateFileId ($($stateRes.id)) au tracking..." "DEBUG"
                            $updateTrackBody = @{ fields = @{ StateFileId = $stateRes.id } } | ConvertTo-Json -Compress
                            Invoke-MgGraphRequest -Method PATCH -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/lists/$trackListId/items/$trackItemId" -Body ([System.Text.Encoding]::UTF8.GetBytes($updateTrackBody)) -ContentType "application/json" -ErrorAction SilentlyContinue | Out-Null
                        }
                        Log "  > State In-Situ uploadé." "DEBUG"
                    }
                }
                catch { Log "  > Impossible d'écrire le State In-Situ : $_" "WARNING" }
            }
        }

        Log "Déploiement terminé." "SUCCESS"
    }
    catch {
        Err "Erreur critique : $($_.Exception.Message)"
    }

    return $result
}
