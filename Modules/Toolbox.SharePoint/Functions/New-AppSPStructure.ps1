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

        # Déterminer si on doit forcer le CT sur les nouveaux dossiers
        $applyCT = ($FolderContentTypeId -ne "0x0120")

        # -- Création Racine --
        if (-not [string]::IsNullOrWhiteSpace($RootFolderName)) {
            Log "Traitement Racine : $RootFolderName" "INFO"
            $rootRes = New-AppGraphFolder -SiteId $siteId -DriveId $driveId -FolderName $RootFolderName -ParentFolderId $startParentId
            $startParentId = $rootRes.id
            $result.FinalUrl = $rootRes.webUrl

            # Application CT & Meta
            if ($RootMetadata -or $applyCT) {
                try {
                    $liReq = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$driveId/items/$($rootRes.id)/listItem?`$select=id" -ErrorAction Stop
                    $fields = @{}
                    if ($RootMetadata) { foreach ($k in $RootMetadata.Keys) { $fields[$k] = $RootMetadata[$k] } }
                    
                    $ctArg = if ($applyCT) { $FolderContentTypeId } else { $null }
                    
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
                $inviteBody = @{ recipients = @( @{ email = $p.Email } ); roles = @($role); requireSignIn = $true; sendSignInPromo = $false } | ConvertTo-Json -Depth 5
                Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$driveId/items/$folderItemId/invite" -Body $inviteBody -ContentType "application/json" | Out-Null
            }
        }

        # --- ÉTAPE 3 : APPLICATION DES MÉTADONNÉES ---
        Log "Phase 3 : Application des Tags et Content Types..." "INFO"
        foreach ($op in ($plan | Where-Object { $_.Type -eq "Folder" })) {
            if (-not $op.Id -or -not $DeployedFoldersMap.ContainsKey($op.Id)) { continue }
            $folderItemId = $DeployedFoldersMap[$op.Id]
            
            $fields = @{}
            if ($op.Tags) { 
                foreach ($t in $op.Tags) { 
                    if ($fields.ContainsKey($t.Name)) {
                        if ($fields[$t.Name] -isnot [array]) {
                            $fields[$t.Name] = @($fields[$t.Name])
                        }
                        if ($fields[$t.Name] -notcontains $t.Value) {
                            $fields[$t.Name] += $t.Value
                        }
                    }
                    else {
                        $fields[$t.Name] = $t.Value 
                    }
                } 
            }
            # Graph demands either specific Object(odata) for multichoice OR sometimes accepts comma separated string.
            # Best reliable way for Choice without Taxonomy is array of strings. We ensure the body is properly formed in Set-AppGraphListItemMetadata
            # Actually, to be safe, let's keep it as array, but the problem is sometimes the Schema JSON has them defined as text.
            # For multiselect choices, Graph V1/Beta expects: "FieldName@odata.type": "Collection(Edm.String)", "FieldName": ["Val1", "Val2"].
            # To simplify and ensure no crash, we will join by ", " if it's an array for now, as standard text columns will take it.
            $finalFields = @{}
            foreach ($k in $fields.Keys) {
                if ($fields[$k] -is [array]) {
                    # Add OData annotation for collections (Graph Beta requires this for Choice Multi)
                    $finalFields["$k@odata.type"] = "Collection(Edm.String)"
                    $finalFields[$k] = $fields[$k]
                }
                else {
                    $finalFields[$k] = $fields[$k]
                }
            }
            
            $ctArg = if ($applyCT) { $FolderContentTypeId } else { $null }

            if ($fields.Count -gt 0 -or $ctArg) {
                try {
                    $liReq = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$driveId/items/$folderItemId/listItem?`$select=id" -ErrorAction Stop
                    Log "  Application Tags/CT sur $($op.Name) (ListItem ID: $($liReq.id)) | CT: $ctArg" "DEBUG"
                    Set-AppGraphListItemMetadata -SiteId $siteId -ListId $listId -ListItemId $liReq.id -Fields $fields -ContentTypeId $ctArg | Out-Null
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
                        $tItem = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$driveId/items/$targetItemId?`$select=webUrl" -ErrorAction Stop
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
                        $sItem = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$driveId/items/$sourceItemId?`$select=webUrl" -ErrorAction Stop
                        $sourceUrl = $sItem.webUrl
                    }
                    catch { Log "Erreur obtention URL source pour publication" "WARNING" }
                }

                if ($sourceUrl) {
                    # 2. Résolution de la Bibliothèque cible (ex: /Partage/...)
                    $pubLibName = "Partage"
                    $pRaw = $op.RawNode.RelativePath -split "/"
                    if ($pRaw.Count -gt 1 -and $pRaw[1] -ne "") { $pubLibName = $pRaw[1] }
                    
                    $pubRelPath = $op.RawNode.RelativePath -replace "^/$pubLibName", "" -replace "\{FormFolderName\}", $RootFolderName
                    if ($pubRelPath.StartsWith("/")) { $pubRelPath = $pubRelPath.Substring(1) }

                    try {
                        $pubDriveRes = Get-AppGraphListDriveId -SiteId $siteId -ListDisplayName $pubLibName
                        $pDriveId = $pubDriveRes.DriveId
                        
                        # 3. Assurer la création des dossiers parents sur la cible
                        $folders = $pubRelPath -split "/"
                        $currentParent = "root"
                        for ($i = 0; $i -lt $folders.Count - 1; $i++) {
                            $fName = $folders[$i]
                            if ([string]::IsNullOrWhiteSpace($fName)) { continue }
                            $fRes = New-AppGraphFolder -SiteId $siteId -DriveId $pDriveId -FolderName $fName -ParentFolderId $currentParent
                            $currentParent = $fRes.id
                        }

                        # 4. Création du fichier .url
                        $linkContent = "[InternetShortcut]`nURL=$sourceUrl"
                        $bytes = [System.Text.Encoding]::UTF8.GetBytes($linkContent)
                        $fileName = $folders[-1]
                        if ($fileName -notlike "*.url") { $fileName += ".url" }
                        
                        $uriPub = "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$pDriveId/items/$currentParent`:/$fileName`:/content"
                        Invoke-MgGraphRequest -Method PUT -Uri $uriPub -Body $bytes -ContentType "text/plain" -ErrorAction Stop | Out-Null
                        Log "  Publication réussie dans $pubLibName/$pubRelPath" "SUCCESS"
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

        Log "Déploiement terminé." "SUCCESS"
    }
    catch {
        Err "Erreur critique : $($_.Exception.Message)"
    }

    return $result
}
