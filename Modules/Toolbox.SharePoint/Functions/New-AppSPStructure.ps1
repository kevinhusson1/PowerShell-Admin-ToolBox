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

    $result = @{ Success = $true; Logs = [System.Collections.Generic.List[string]]::new(); Errors = [System.Collections.Generic.List[string]]::new(); FinalUrl = "" }

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
        if ($FolderSchemaJson -and $FolderSchemaName) {
            Log "Vérification/Création du modèle de dossier : $FolderSchemaName" "INFO"
            # Logic de création de colonnes et attachement CT (Repris de New-AppGraphSPStructure)
            try {
                # FolderSchemaJson est déjà l'ARRAY des colonnes JSON string
                $schemaDef = $FolderSchemaJson | ConvertFrom-Json
                $colIds = @()
                foreach ($c in $schemaDef) {
                    $isMulti = ($c.Type -eq "Choix Multiples")
                    $gType = "Text"
                    if ($c.Type -eq "Nombre") { $gType = "Number" }
                    elseif ($c.Type -like "Choix*") { $gType = "Choice" }
                    elseif ($c.Type -eq "Date et Heure") { $gType = "DateTime" }
                    elseif ($c.Type -eq "Oui/Non") { $gType = "Boolean" }
                    
                    # Récupération des choix uniques pour pré-remplir la colonne
                    $choices = @()
                    if ($gType -eq "Choice") {
                        # Extraction de toutes les valeurs de tous les tags correspondants dans l'arbre entier
                        $allVals = $plan | ForEach-Object { 
                            if ($_.Tags) { 
                                $_.Tags | Where-Object { $_.Name -eq $c.Name } | Select-Object -ExpandProperty Value 
                            } 
                        }
                        $choices = $allVals | Select-Object -Unique | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                        if (-not $choices -or $choices.Count -eq 0) { $choices = @("Valeur 1") }
                    }

                    $resCol = New-AppGraphSiteColumn -SiteId $siteId -Name $c.Name -DisplayName $c.Name -Type $gType -Choices $choices -AllowMultiple:$isMulti
                    if ($resCol) { $colIds += $resCol.Column.id }
                }

                $ctSafeName = "SBuilder_" + ($FolderSchemaName -replace '[\\/:*?"<>|#%]', '_')
                $resCT = New-AppGraphContentType -SiteId $siteId -Name $ctSafeName -Description "Modèle $FolderSchemaName" -Group "SBuilder" -BaseId "0x0120" -ColumnIdsToBind $colIds
                if ($resCT) {
                    # Attachement à la liste
                    $addCtUri = "https://graph.microsoft.com/v1.0/sites/$siteId/lists/$listId/contentTypes/addCopy"
                    $bodyCtAdd = @{ contentType = $resCT.ContentType.id }
                    try {
                        $resAdd = Invoke-MgGraphRequest -Method POST -Uri $addCtUri -Body $bodyCtAdd -ContentType "application/json" -ErrorAction Stop
                        $FolderContentTypeId = $resAdd.id
                        Log "Modèle '$FolderSchemaName' attaché (#$FolderContentTypeId)." "SUCCESS"
                    }
                    catch {
                        # Déjà existant ?
                        $exCts = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/lists/$listId/contentTypes"
                        $lCt = $exCts.value | Where-Object { $_.name -eq $ctSafeName }
                        if ($lCt) { $FolderContentTypeId = $lCt.id; Log "Modèle existant récupéré." "DEBUG" }
                    }
                }
            }
            catch { Log "Avertissement sur le Schéma : $($_.Exception.Message)" "WARNING" }
        }

        # 5. EXECUTION DU PLAN
        $DeployedFoldersMap = @{} # Mapping ID interne -> Graph ItemId
        $startParentId = if ($TargetFolderItemId) { $TargetFolderItemId } else { "root" }

        # 3. GÉNÉRATION DU PLAN
        Log "Analyse de la structure et génération du plan..." "DEBUG"
        $plan = Get-AppSPDeploymentPlan -StructureJson $StructureJson -FormValues $FormValues -RootMetadata $RootMetadata

        # 3.bis RÉSOLUTION DES TYPES DE COLONNES ET MAPPING (via Schéma)
        $MultiChoiceColumns = @()
        $SchemaMapping = @{} # Mapping "Nom Affichage" ou "Nom" -> "Nom Interne"
        if ($FolderSchemaJson) {
            try {
                $schemaDef = $FolderSchemaJson | ConvertFrom-Json
                foreach ($c in $schemaDef) {
                    $kLow = $c.Name.ToLower()
                    if ($c.Type -match "Choix Multiples") { $MultiChoiceColumns += $kLow }
                    
                    # On stocke le mapping pour pouvoir retrouver "Year" si on nous donne "Année"
                    $internal = $c.Name
                    $SchemaMapping[$internal.ToLower()] = $internal
                    if ($c.DisplayName) { $SchemaMapping[$c.DisplayName.ToLower()] = $internal }
                }
            } catch { Log "Erreur analyse types colonnes du schéma." "WARNING" }
        }

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

        # Helper pour formater les champs pour Graph Beta
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

                if ($MultiChoiceColumns -and ($MultiChoiceColumns -contains $finalKeyLow)) {
                    # C'est un choix multiple : Graph Beta exige un tableau + l'annotation @odata.type
                    $final["$finalKey@odata.type"] = "Collection(Edm.String)"
                    if ($val -is [string]) { $final[$finalKey] = @($val) }
                    elseif ($val -is [array]) { $final[$finalKey] = $val }
                    else { $final[$finalKey] = @($val.ToString()) }
                }
                elseif ($val -is [array]) {
                    # Fallback si c'est un tableau mais pas listé dans le schéma
                    $final["$finalKey@odata.type"] = "Collection(Edm.String)"
                    $final[$finalKey] = $val
                }
                else {
                    $final[$finalKey] = $val
                }
            }
            return $final
        }.GetNewClosure()
                    
        # -- Création Racine --
        if (-not [string]::IsNullOrWhiteSpace($RootFolderName)) {
            Log "Traitement Racine : $RootFolderName" "INFO"
            $rootRes = New-AppGraphFolder -SiteId $siteId -DriveId $driveId -FolderName $RootFolderName -ParentFolderId $startParentId
            $startParentId = $rootRes.id
            $DeployedFoldersMap["root"] = $startParentId
            $result.FinalUrl = $rootRes.webUrl

            # Application CT & Meta
            if ($RootMetadata -or $FolderContentTypeId -ne "0x0120") {
                try {
                    $liReq = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$driveId/items/$($rootRes.id)/listItem?`$select=id" -ErrorAction Stop
                    
                    $fields = @{}
                    if ($RootMetadata) { $fields = & $FormatFields -InputFields $RootMetadata }
                    
                    $ctArg = if ($FolderContentTypeId -ne "0x0120") { $FolderContentTypeId } else { $null }
                    
                    if ($fields.Count -gt 0 -or $ctArg) {
                        Set-AppGraphListItemMetadata -SiteId $siteId -ListId $listId -ListItemId $liReq.id -Fields $fields -ContentTypeId $ctArg | Out-Null
                    }
                }
                catch { Log "Erreur application Metadata racine : $_" "WARNING" }
            }
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
                    # Vérifier si c'est une erreur 'Forbidden' mais que l'utilisateur a peut être déjà les droits par héritage
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
                    $liReq = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$driveId/items/$folderItemId/listItem?`$select=id" -ErrorAction Stop
                    Log "  Application Tags/CT sur $($op.Name) (ListItem ID: $($liReq.id)) | CT: $ctArg" "DEBUG"
                    Set-AppGraphListItemMetadata -SiteId $siteId -ListId $listId -ListItemId $liReq.id -Fields $finalFields -ContentTypeId $ctArg | Out-Null
                    Log "  Metadata appliqués." "SUCCESS"
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
                
                # 1. Obtenir l'URL de la cible publiée (le dossier source à pointer)
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
                    # 2. Résolution de la Bibliothèque cible (ex: /Partage/Path -> PubLib="Partage", PubPath="Path")
                    # Par défaut on utilise la config du noeud (TargetFolderPath)
                    $targetRaw = if ($op.RawNode.TargetFolderPath) { $op.RawNode.TargetFolderPath } else { "/Shared Documents" }
                    $pParts = $targetRaw -split "/" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                    
                    $pubLibName = if ($pParts.Count -gt 0) { $pParts[0] } else { "Shared Documents" }
                    
                    # 2. Résolution Chemin Cible (Relatif à la Bibliothèque)
                    # On retire le nom de la bibliothèque du chemin pour obtenir le sous-chemin relatif
                    $pubRelSubPath = $op.RawNode.TargetFolderPath -replace "^.*?$([regex]::Escape($pubLibName))", "" -replace "^/", ""
                    
                    # NOUVEAU : Si UseFormName est vrai, on crée un dossier au nom de la racine dans la cible
                    if ($op.RawNode.UseFormName -and $RootFolderName) {
                        $pubRelSubPath = if ([string]::IsNullOrWhiteSpace($pubRelSubPath)) { $RootFolderName } else { "$pubRelSubPath/$RootFolderName" }
                    }

                    try {
                        $pubDriveRes = Get-AppGraphListDriveId -SiteId $siteId -ListDisplayName $pubLibName
                        $pDriveId = $pubDriveRes.DriveId
                        
                        Log "Publication vers : $pubLibName ($pubRelSubPath) [Drive: $pDriveId]" "DEBUG"
                        
                        # 3. Assurer la création des dossiers parents sur la cible
                        $folders = $pubRelSubPath -split "/" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                        $currentParent = "root"
                        foreach ($fName in $folders) {
                            $isNewProjectFolder = ($fName -eq $RootFolderName)
                            try {
                                # Approche 'Check or Create' pour éviter ConflictBehavior='replace' sur les dossiers racines ou protégés
                                $fRes = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$pDriveId/items/$currentParent/children?`$filter=name eq '$fName'" -ErrorAction Stop
                                if ($fRes.value.Count -gt 0) {
                                    $currentParent = $fRes.value[0].id
                                } else {
                                    $fCreated = New-AppGraphFolder -SiteId $siteId -DriveId $pDriveId -FolderName $fName -ParentFolderId $currentParent
                                    $currentParent = $fCreated.id
                                }
                            } catch { 
                                Log "Erreur dossier publication '$fName' : $_" "WARNING" 
                                # Fallback on tente la création brute si le GET échoue
                                $fCreated = New-AppGraphFolder -SiteId $siteId -DriveId $pDriveId -FolderName $fName -ParentFolderId $currentParent
                                $currentParent = $fCreated.id
                            }

                            # NOUVEAU : Application des métadonnées sur le dossier projet si demandé (UseFormMetadata)
                            if ($isNewProjectFolder -and $op.RawNode.UseFormMetadata -and $RootMetadata) {
                                try {
                                    $pLiReq = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$pDriveId/items/$currentParent/listItem?`$select=id" -ErrorAction Stop
                                    $pFields = & $FormatFields -InputFields $RootMetadata
                                    if ($pFields.Count -gt 0) {
                                        # On utilise le listId de la bibliothèque de destination
                                        Set-AppGraphListItemMetadata -SiteId $siteId -ListId $pubDriveRes.ListId -ListItemId $pLiReq.id -Fields $pFields | Out-Null
                                        Log "  Métadonnées appliquées au dossier de publication." "DEBUG"
                                    }
                                } catch { Log "  Erreur application Meta publication ($fName) : $_" "WARNING" }
                            }
                        }

                        # 4. Création du fichier .url
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

        # 6. TRACKING (Enregistrement Historique)
        if ($TrackingInfo -and (Get-Command "New-AppSPTrackingList" -ErrorAction SilentlyContinue)) {
            # Note: New-AppSPTrackingList est encore PnP. À migrer plus tard ou utiliser tel quel si connexion dispo.
            Log "Enregistrement dans l'historique (Tracking)..." "DEBUG"
            # @todo: Migration Tracking vers Graph
        }

        # Export mapping local JSON ID -> Microsoft Graph ListItem ID (pour State In-Situ)
        $result.DeployedNodes = $DeployedFoldersMap

        if ($TrackingInfo -and $TrackingInfo.TemplateId -and $DeployedFoldersMap.ContainsKey("root")) {
            $rootId = $DeployedFoldersMap["root"]
            if (-not [string]::IsNullOrWhiteSpace($rootId)) {
                Log "Génération et sauvegarde du state.json In-Situ..." "INFO"
                try {
                    Save-AppSPDeploymentState -SiteId $siteId -DriveId $driveId -RootFolderItemId $rootId -DeployedNodes $DeployedFoldersMap -TemplateId $TrackingInfo.TemplateId -FormValues $FormValues | Out-Null
                    Log "  > State In-Situ uploadé." "DEBUG"
                }
                catch {
                    Log "  > Impossible d'écrire le State In-Situ : $_" "WARNING"
                }
            }
        }

        Log "Déploiement terminé." "SUCCESS"
    }
    catch {
        Err "Erreur critique : $($_.Exception.Message)"
    }

    return $result
}
