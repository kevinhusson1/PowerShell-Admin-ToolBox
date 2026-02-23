# Modules/Toolbox.SharePoint/Functions/New-AppSPStructure.ps1

<#
.SYNOPSIS
    Déploie une structure documentaire complète (Dossiers, Liens, Pubs) sur SharePoint.

.DESCRIPTION
    Moteur principal de déploiement qui interprète le JSON de structure pour créer
    l'arborescence correspondante sur le site cible.
    
    Fonctionnalités gérées :
    - Création récursive de Dossiers.
    - Création de Liens (.url) et Liens Internes (Raccourcis vers dossiers).
    - Gestion des Publications (Dossiers partagés vers d'autres sites/libs).
    - Application des permissions (Utilisateurs/Groupes).
    - Application des métadonnées (Tags), y compris les **Tags Dynamiques** via 'FormValues'.
    - Tagging du dossier racine (via 'RootMetadata').

.PARAMETER TargetSiteUrl
    L'URL du site SharePoint cible.

.PARAMETER TargetLibraryName
    Le nom de la bibliothèque documentaire.

.PARAMETER RootFolderName
    (Optionnel) Nom du dossier racine à créer (si applicable).

.PARAMETER StructureJson
    La définition JSON complète de l'arborescence (Serialisée depuis le Builder).

.PARAMETER ClientId
    ID Client de l'App Registration (Auth Certificat).

.PARAMETER Thumbprint
    Empreinte du certificat pour l'authentification Application (Graph/PnP).

.PARAMETER TenantName
    Nom du tenant (ex: contoso.onmicrosoft.com).

.PARAMETER TargetFolderUrl
    (Optionnel) Url relative du dossier parent existant (pour déploiement dans un sous-dossier).

.PARAMETER FormValues
    (Optionnel) Hashtable des valeurs saisies dans le formulaire (Clé=Variable, Val=Valeur).
    Utilisé pour résoudre les Tags Dynamiques ({IsDynamic: true}).

.PARAMETER RootMetadata
    (Optionnel) Hashtable des métadonnées à appliquer spécifiquement au dossier racine.

.OUTPUTS
    [Hashtable] Résultat { Success, Logs, Errors }.
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
        [Parameter(Mandatory = $false)] [hashtable]$FormValues,
        [Parameter(Mandatory = $false)] [hashtable]$RootMetadata,
        [Parameter(Mandatory = $false)] [hashtable]$TrackingInfo,
        [Parameter(Mandatory = $false)] [string]$IdMapReferenceJson,
        [Parameter(Mandatory = $false)] [string]$ProjectModelName,
        [Parameter(Mandatory = $false)] [string]$ProjectRootUrl
    )

    $result = @{ Success = $true; Logs = [System.Collections.Generic.List[string]]::new(); Errors = [System.Collections.Generic.List[string]]::new() }

    function Log { param($m, $l = "Info") Write-AppLog -Message $m -Level $l -Collection $result.Logs -PassThru }
    function Err {
        param($m) 
        $result.Success = $false; 
        Write-AppLog -Message $m -Level Error -Collection $result.Errors; 
        Write-AppLog -Message $m -Level Error -Collection $result.Logs -PassThru 
    }

    function Loc($key, $fArgs) {
        if (Get-Command "Get-AppLocalizedString" -ErrorAction SilentlyContinue) {
            $s = Get-AppLocalizedString -Key ("sp_builder." + $key)
            if ($s.StartsWith("MISSING:")) { return $key }
            if ($null -ne $fArgs) { return $s -f $fArgs }
            return $s
        }
        return $key 
    }

    # Helper pour l'application des tags (Append Mode & Array Support)
    function Update-SPTags {
        param($Item, $TagsConfig, $List, $Connection)
        
        if (-not $Item -or -not $Item.Id) { return }

        $groupedTags = $TagsConfig | Group-Object Name
        $valuesHash = @{}
        $updatesNeeded = $false

        try {
            $currentItem = Get-PnPListItem -List $List -Id $Item.Id -Connection $Connection -ErrorAction Stop
            
            foreach ($g in $groupedTags) {
                $fieldName = $g.Name
                # On force un tableau de chaînes pour PnP
                
                # --- RESOLUTION DYNAMIQUE ---
                $resolvedValues = @()
                foreach ($t in $g.Group) {
                    if ($t.IsDynamic -and $FormValues -and $t.SourceVar) {
                        # Valeur depuis le formulaire
                        $dynVal = $FormValues[$t.SourceVar]
                        if ($null -ne $dynVal -and $dynVal -ne "") {
                            $resolvedValues += $dynVal
                        }
                    }
                    else {
                        # Valeur statique
                        if ($t.Value) { $resolvedValues += $t.Value }
                        elseif ($t.Term) { $resolvedValues += $t.Term }
                    }
                }
                
                $newValues = $resolvedValues 

                # -- Logique APPEND --
                $existingVal = $currentItem[$fieldName]
                $mergedList = [System.Collections.Generic.List[string]]::new()
                
                if ($null -ne $existingVal) {
                    if ($existingVal -is [Microsoft.SharePoint.Client.Taxonomy.TaxonomyFieldValue]) {
                        $mergedList.Add($existingVal.Label)
                    }
                    elseif ($existingVal -is [Array] -or $existingVal -is [Microsoft.SharePoint.Client.Taxonomy.TaxonomyFieldValueCollection]) {
                        foreach ($v in $existingVal) {
                            if ($v -is [Microsoft.SharePoint.Client.Taxonomy.TaxonomyFieldValue]) { $mergedList.Add($v.Label) }
                            else { $mergedList.Add($v.ToString()) }
                        }
                    }
                    else {
                        # Fallback simple
                        $strVal = $existingVal.ToString()
                        if ($strVal -ne "") { $mergedList.Add($strVal) }
                    }
                }

                foreach ($n in $newValues) {
                    if (-not $mergedList.Contains($n)) { $mergedList.Add($n) }
                }

                # On passe un tableau à Set-PnPListItem (Gère Multi-Choice & Taxonomy correctement)
                $valuesHash[$fieldName] = $mergedList.ToArray()
                $updatesNeeded = $true
            }

            if ($updatesNeeded) {
                $kvString = ($valuesHash.GetEnumerator() | ForEach-Object { "[$($_.Key)=Array($($_.Value.Count))]" }) -join " "
                Log "  > Tags (Update/Append) : $kvString" "DEBUG"

                Set-PnPListItem -List $List -Identity $Item.Id -Values $valuesHash -Connection $Connection -ErrorAction Stop
                Log (Loc "log_deploy_tags_applied") "INFO"

                # -- Verification --
                $verifyItem = Get-PnPListItem -List $List -Id $Item.Id -Connection $Connection -ErrorAction SilentlyContinue
                foreach ($k in $valuesHash.Keys) {
                    $expectedArr = $valuesHash[$k]
                    # Extraction Actuel
                    $actualVal = $verifyItem[$k]
                    $actualLabels = @()
                    if ($actualVal -is [Microsoft.SharePoint.Client.Taxonomy.TaxonomyFieldValue]) { $actualLabels += $actualVal.Label }
                    elseif ($actualVal -is [Array]) { 
                        foreach ($x in $actualVal) {
                            if ($x -is [Microsoft.SharePoint.Client.Taxonomy.TaxonomyFieldValue]) { $actualLabels += $x.Label }
                            else { $actualLabels += $x.ToString() }
                        }
                    }
                    elseif ($actualVal) { $actualLabels += $actualVal.ToString() }

                    foreach ($exp in $expectedArr) {
                        if ($actualLabels -notcontains $exp) {
                            # Double check avec Trim
                            $found = $false
                            foreach ($a in $actualLabels) { if ($a.Trim() -eq $exp.Trim()) { $found = $true; break } }
                            if (-not $found) {
                                Log "  ⚠️ ECHEC TAG '$k' : '$exp' manquant (Actuel: $($actualLabels -join ','))" "WARNING"
                            }
                        }
                    }
                }
            }
        }
        catch {
            Log "  ⚠️ Erreur Update-SPTags : $($_.Exception.Message)" "WARNING"
        }
    }

    try {
        Log (Loc "log_deploy_init") "DEBUG"
        $cleanTenant = $TenantName -replace "\.onmicrosoft\.com$", "" -replace "\.sharepoint\.com$", ""
        
        $conn = Connect-PnPOnline -Url $TargetSiteUrl -ClientId $ClientId -Thumbprint $Thumbprint -Tenant "$cleanTenant.onmicrosoft.com" -ReturnConnection -ErrorAction Stop
        Log (Loc "log_deploy_connected" $TargetSiteUrl) "INFO"

        Log (Loc "log_deploy_check_lib" $TargetLibraryName) "DEBUG"
        $targetLib = Get-PnPList -Identity $TargetLibraryName -Includes RootFolder -Connection $conn -ErrorAction Stop
        if (-not $targetLib) { throw "Bibliothèque introuvable." }
        
        # DEFINITION CIBLE (Correction)
        if (-not [string]::IsNullOrWhiteSpace($TargetFolderUrl)) {
            $libUrl = $TargetFolderUrl.TrimEnd('/')
            Log (Loc "log_deploy_target_def" $libUrl) "DEBUG"
        }
        else {
            $libUrl = $targetLib.RootFolder.ServerRelativeUrl.TrimEnd('/')
            Log (Loc "log_deploy_target_def" $libUrl) "DEBUG" # Réutilisation target_def pour simplifier
        }
        
        $structure = $StructureJson | ConvertFrom-Json
        
        $globalDeployId = $null
        if ($TrackingInfo -and $TrackingInfo.Count -gt 0) {
            $globalDeployId = [Guid]::NewGuid().ToString()
        }
        
        # 0. PRE-PROCESSING : MAPPING ID -> PATH (Pour Liens Internes)
        Log "Construction de la carte des IDs..." "DEBUG"
        $IdToPathMap = @{}

        function Build-IdMap {
            param($SubStructure, $CurrentPath)
            
            # Si c'est un tableau (cas "Folders"), on itère
            if ($SubStructure -is [System.Array]) {
                foreach ($item in $SubStructure) { Build-IdMap -SubStructure $item -CurrentPath $CurrentPath }
                return
            }

            # Si c'est un dossier (pas un lien ni une pub)
            if ($SubStructure.Type -ne "Link" -and $SubStructure.Type -ne "InternalLink" -and $SubStructure.Type -ne "Publication" -and $SubStructure.Name) {
                # Construction path
                $myPath = "$CurrentPath/$($SubStructure.Name)"
                
                # Enregistrement ID
                if ($SubStructure.Id) {
                    $IdToPathMap[$SubStructure.Id] = $myPath
                }

                # Récursion
                if ($SubStructure.Folders) {
                    Build-IdMap -SubStructure $SubStructure.Folders -CurrentPath $myPath
                }
            }
        }

        # Lancement Mapping (Attention au path de base)
        # On simule un parcours virtuel avec le full json si référencé, sinon le sub-json
        $mapRef = $structure
        if (-not [string]::IsNullOrWhiteSpace($IdMapReferenceJson)) {
            try { $mapRef = $IdMapReferenceJson | ConvertFrom-Json } catch { Log "⚠️ Erreur parsing IdMapReferenceJson" "WARNING" }
        }
        if ($mapRef.Folders) { Build-IdMap -SubStructure $mapRef.Folders -CurrentPath "" }
        else { Build-IdMap -SubStructure $mapRef -CurrentPath "" }

        Log "Mapping IDs terminé ($($IdToPathMap.Count) entrées)." "DEBUG"


        function Set-NewFolder {
            param($CurrentPath, $FolderObj)

            # 0. GESTION TYPE = LINK (Existant)
            if ($FolderObj.Type -eq "Link") {
                $linkName = $FolderObj.Name
                $linkUrl = $FolderObj.Url
                Log (Loc "log_deploy_create_link" @($linkName, $linkUrl)) "INFO"
                $resLink = New-AppSPLink -Name $linkName -TargetUrl $linkUrl -Folder $CurrentPath -Connection $conn
                if ($resLink.Success) { 
                    Log (Loc "log_deploy_link_ok") "DEBUG" 
                    
                    # GESTION TAGS POUR LIENS (Refactorisé)
                    if ($FolderObj.Tags) {
                        # Récupération Item Robuste
                        $fileItem = $null
                        try {
                            $fileItem = Get-PnPFile -Url $resLink.File.ServerRelativeUrl -AsListItem -Connection $conn -ErrorAction Stop
                        }
                        catch { 
                            Log "  ⚠️ Erreur récupération Item pour tags lien '$linkName': $_" "WARNING"
                        }

                        if ($fileItem) {
                            Update-SPTags -Item $fileItem -TagsConfig $FolderObj.Tags -List $TargetLibraryName -Connection $conn
                        }
                    }
                }
                else { Err "Erreur création lien '$linkName' : $($resLink.Message)" }
                return # Stop ici pour un lien
            }
            
            # 0-BIS. GESTION TYPE = INTERNAL LINK (NOUVEAU)
            if ($FolderObj.Type -eq "InternalLink") {
                $linkName = $FolderObj.Name
                $targetId = $FolderObj.TargetNodeId
                
                Log (Loc "log_deploy_create_internal_link" $linkName) "INFO"
                
                # A. Résolution Cible
                if (-not $IdToPathMap.ContainsKey($targetId)) {
                    Log "⚠️ Cible introuvable pour le lien '$linkName' (ID: $targetId). Lien ignoré." "WARNING"
                    return
                }
                
                $relPath = $IdToPathMap[$targetId]
                # Construction URL absolue cible
                # $TargetSiteUrl + $TargetLibraryUrl + $relPath
                
                $uri = New-Object Uri($TargetSiteUrl)
                $baseHost = "$($uri.Scheme)://$($uri.Host)"
                
                # [FIX] Calculate absolute start path (since $startPath is not yet defined here)
                $absStartPath = $libUrl
                if (-not [string]::IsNullOrWhiteSpace($ProjectRootUrl)) {
                    $absStartPath = $ProjectRootUrl
                }
                elseif (-not [string]::IsNullOrWhiteSpace($RootFolderName)) {
                    $absStartPath = "$libUrl/$RootFolderName"
                }

                $fullTargetUrl = "$baseHost$absStartPath$relPath"
                
                # B. Création .url
                if (-not $linkName.EndsWith(".url")) { $linkName += ".url" }
                
                $resLink = New-AppSPLink -Name $linkName -TargetUrl $fullTargetUrl -Folder $CurrentPath -Connection $conn
                if ($resLink.Success) { 
                    Log "Lien interne créé vers '$relPath'." "DEBUG" 
                    
                    # GESTION TAGS POUR LIENS INTERNES (Refactorisé)
                    if ($FolderObj.Tags) {
                        # Récupération Item Robuste
                        $fileItem = $null
                        try {
                            $fileItem = Get-PnPFile -Url $resLink.File.ServerRelativeUrl -AsListItem -Connection $conn -ErrorAction Stop
                        }
                        catch { 
                            Log "  ⚠️ Erreur récupération Item pour tags lien '$linkName': $_" "WARNING"
                        }

                        if ($fileItem) {
                            Update-SPTags -Item $fileItem -TagsConfig $FolderObj.Tags -List $TargetLibraryName -Connection $conn
                        }
                    }
                }
                else { Err "Erreur lien interne '$linkName' : $($resLink.Message)" }
                return
            }

            # 0-QUATER. GESTION TYPE = FILE (NOUVEAU)
            if ($FolderObj.Type -eq "File") {
                $fileName = $FolderObj.Name
                $sourceUrl = $FolderObj.SourceUrl
                
                Log "Traitement fichier '$fileName' depuis '$sourceUrl'..." "INFO"
                
                if ([string]::IsNullOrWhiteSpace($sourceUrl)) {
                    Err "URL source manquante pour le fichier '$fileName'. Ignoré."
                    return
                }

                # 1. IMPORT FICHIER via Helper (Gère Auth SP & Web)
                try {
                    # On passe les infos d'auth pour que le helper puisse se connecter à la source si c'est du SharePoint
                    $uploadedFile = Import-AppSPFile `
                        -SourceUrl $sourceUrl `
                        -TargetConnection $conn `
                        -TargetFolderServerRelativeUrl $CurrentPath `
                        -TargetFileName $fileName `
                        -ClientId $ClientId `
                        -Thumbprint $Thumbprint `
                        -TenantName $TenantName

                    Log "Fichier '$fileName' importé avec succès." "SUCCESS"
                        
                    # 2. METADONNÉES & PERMISSIONS (Item)
                    if ($uploadedFile) {
                        $fileItem = $null
                        try {
                            $fileItem = Get-PnPFile -Url $uploadedFile.ServerRelativeUrl -AsListItem -Connection $conn -ErrorAction Stop
                        }
                        catch { Log "  ⚠️ Erreur récupération Item fichier : $_" "WARNING" }

                        if ($fileItem) {
                            # Permissions
                            if ($FolderObj.Permissions) {
                                foreach ($perm in $FolderObj.Permissions) {
                                    # Logique identique Permission Dossier
                                    $email = $perm.Email; $role = $perm.Level
                                    $spRole = switch ($role.ToLower()) { "read" { "Read" } "contribute" { "Contribute" } "full" { "Full Control" } "full control" { "Full Control" } Default { "Read" } }
                                    try {
                                        Set-PnPListItemPermission -List $TargetLibraryName -Identity $fileItem.Id -User $email -AddRole $spRole -Connection $conn -ErrorAction Stop
                                        Log "  > Permission ajoutée : $email ($spRole)" "INFO"
                                    }
                                    catch { Log "  ⚠️ Erreur permission fichier : $($_.Exception.Message)" "WARNING" }
                                }
                            }

                            # Tags
                            if ($FolderObj.Tags) {
                                Update-SPTags -Item $fileItem -TagsConfig $FolderObj.Tags -List $TargetLibraryName -Connection $conn
                            }
                        }
                    }
                }
                catch {
                    Err "Erreur import fichier '$fileName' : $($_.Exception.Message)"
                }

                return # Stop ici pour un fichier
            }
            
            # 0-TER. GESTION TYPE = PUBLICATION (Déporté ici ou traité plus bas ?)
            # Pour l'instant traité dans le bloc Folders, mais on pourrait l'uniformiser ici.
            # On laisse le bloc 6 existant pour ne pas trop perturber.

            $folderName = $FolderObj.Name
            $fullPath = "$CurrentPath/$folderName"
            
            Log (Loc "log_deploy_folder_proc" $fullPath) "INFO"
            
            # 1. CRÉATION DOSSIER (Optimisé)
            try {
                $folder = Add-PnPFolder -Name $folderName -Folder $CurrentPath -Connection $conn -ErrorAction Stop
                Log (Loc "log_deploy_folder_ok" $folder.Name) "DEBUG"
            }
            catch {
                try {
                    $folder = Resolve-PnPFolder -SiteRelativePath $fullPath -Connection $conn -ErrorAction Stop
                }
                catch {
                    Err "CRASH sur '$fullPath' : $($_.Exception.Message)"
                    return 
                }
            }

            # 2. RÉCUPÉRATION ITEM (RETRY PATTERN)
            $folderItem = $null
            $retry = 0
            while ($retry -lt 3 -and $null -eq $folderItem) {
                try {
                    $tempObj = Get-PnPFolder -Url $folder.ServerRelativeUrl -Includes ListItemAllFields -Connection $conn -ErrorAction Stop
                    $folderItem = $tempObj.ListItemAllFields
                    if ($null -eq $folderItem.Id) { throw "ID vide" }
                }
                catch {
                    Start-Sleep -Milliseconds 500
                    $retry++
                }
            }
            
            if (-not $folderItem) {
                Log "⚠️ Impossible de récupérer l'Item SharePoint (Droits/Tags ignorés)." "WARNING"
            } 
            else {
                # 3. PERMISSIONS
                if ($FolderObj.Permissions) {
                    Log "Application des permissions..." "DEBUG"
                    try {
                        foreach ($perm in $FolderObj.Permissions) {
                            $email = $perm.Email
                            $role = $perm.Level
                            $spRole = switch ($role.ToLower()) { 
                                "read" { "Read" } 
                                "contribute" { "Contribute" } 
                                "full" { "Full Control" } 
                                "full control" { "Full Control" } # Fix for JSON "Full Control"
                                Default { "Read" } 
                            }
                            try {
                                Set-PnPListItemPermission -List $TargetLibraryName -Identity $folderItem.Id -User $email -AddRole $spRole -Connection $conn -ErrorAction Stop
                                Log "Permission ajoutée : $email -> $spRole" "INFO"
                            }
                            catch {
                                try {
                                    New-PnPUser -LoginName $email -Connection $conn -ErrorAction SilentlyContinue | Out-Null
                                    Set-PnPListItemPermission -List $TargetLibraryName -Identity $folderItem.Id -User $email -AddRole $spRole -Connection $conn -ErrorAction Stop
                                    Log (Loc "log_deploy_perm_added" @($email, $spRole)) "INFO"
                                }
                                catch {
                                    Log "Erreur permission pour $email : $($_.Exception.Message)" "WARNING"
                                }
                            }
                        }
                    }
                    catch { Err "Erreur globale Permissions : $($_.Exception.Message)" }
                }

                # 4. TAGS (Refactorisé)
                if ($FolderObj.Tags) {
                    Update-SPTags -Item $folderItem -TagsConfig $FolderObj.Tags -List $TargetLibraryName -Connection $conn
                }
            }

            # 5. LIENS (INTERNES)
            if ($FolderObj.Links) {
                foreach ($link in $FolderObj.Links) {
                    Log (Loc "log_deploy_create_link" @($link.Name, $link.Url)) "DEBUG"
                    $resLink = New-AppSPLink -Name $link.Name -TargetUrl $link.Url -Folder $folder.ServerRelativeUrl -Connection $conn
                    if ($resLink.Success) { Log (Loc "log_deploy_link_ok") "INFO" }
                    else { Err "Erreur Lien : $($resLink.Message)" }
                }
            }
            
            # =========================================================================================
            # 6. TRAITEMENT DES PUBLICATIONS (NOUVEAU)
            # =========================================================================================
            if ($FolderObj.Folders) {
                $pubs = $FolderObj.Folders | Where-Object { $_.Type -eq "Publication" }
                foreach ($pub in $pubs) {
                    Log (Loc "log_deploy_pub_proc" $pub.Name) "INFO"
                    
                    try {
                        # A. RÉCUPÉRATION URL SOURCE
                        $uri = New-Object Uri($TargetSiteUrl)
                        $baseHost = "$($uri.Scheme)://$($uri.Host)"
                        $sourceFullUrl = "$baseHost$($folder.ServerRelativeUrl)"
                        Log (Loc "log_deploy_pub_source" $sourceFullUrl) "DEBUG"

                        # B. DÉTERMINATION SITE CIBLE
                        $targetCtx = $conn 
                        
                        if ($pub.TargetSiteMode -eq "Url" -and -not [string]::IsNullOrWhiteSpace($pub.TargetSiteUrl)) {
                            Log (Loc "log_deploy_pub_remote_conn" $pub.TargetSiteUrl) "DEBUG"
                            try {
                                $targetCtx = Connect-PnPOnline -Url $pub.TargetSiteUrl -ClientId $ClientId -Thumbprint $Thumbprint -Tenant "$cleanTenant.onmicrosoft.com" -ReturnConnection -ErrorAction Stop
                            }
                            catch {
                                Log "  ⚠️ Erreur connexion cible : $($_.Exception.Message)" "WARNING"
                                continue
                            }
                        }

                        # C. CRÉATION DU RACCOURCI SUR LA CIBLE
                        $linkName = $pub.Name
                        if (-not $linkName.EndsWith(".url")) { $linkName += ".url" }
                        
                        $rawDestPath = $pub.TargetFolderPath
                        
                        $pName = ""
                        if (-not [string]::IsNullOrWhiteSpace($ProjectModelName)) { $pName = $ProjectModelName }
                        elseif (-not [string]::IsNullOrWhiteSpace($RootFolderName)) { $pName = $RootFolderName }

                        if ($pub.UseModelName -eq $true -and -not [string]::IsNullOrWhiteSpace($pName)) {
                            $rawDestPath = "$rawDestPath/$pName"
                        }
                        
                        Log (Loc "log_deploy_pub_target_path" $rawDestPath) "DEBUG"

                        # FIX: Résolution du ServerRelativeUrl correct pour PnP
                        # Add-PnPFile (via New-AppSPLink) exige un ServerRelativeUrl (/sites/...)
                        try {
                            $resolvedDest = Resolve-PnPFolder -SiteRelativePath $rawDestPath -Connection $targetCtx -ErrorAction Stop
                            $rawDestPath = $resolvedDest.ServerRelativeUrl
                        }
                        catch {
                            Log "  ⚠️ Erreur résolution dossier cible '$rawDestPath' : $($_.Exception.Message)" "WARNING"
                            # On continue avec le path brut, qui échouera probablement, mais on aura tracé.
                        }

                        $resShortcut = New-AppSPLink -Name $linkName -TargetUrl $sourceFullUrl -Folder $rawDestPath -Connection $targetCtx
                        if ($resShortcut.Success) {
                            Log (Loc "log_deploy_pub_shortcut_ok" $resShortcut.File.ServerRelativeUrl) "SUCCESS"
                        }
                        else {
                            throw "Echec création raccourci : $($resShortcut.Message)"
                        }

                        # C-bis. RÉCUPÉRATION ITEM (ROBUSTE)
                        $pubItem = $null
                        try {
                            # On tente via UniqueId si dispo, sinon via URL en mode ListItem
                            if ($resShortcut.File -and $resShortcut.File.UniqueId) {
                                $pubItem = Get-PnPListItem -List $TargetLibraryName -UniqueId $resShortcut.File.UniqueId -Connection $targetCtx -ErrorAction SilentlyContinue
                            }
                            if (-not $pubItem) {
                                $pubItem = Get-PnPFile -Url $resShortcut.File.ServerRelativeUrl -AsListItem -Connection $targetCtx -ErrorAction Stop
                            }
                        }
                        catch {
                            Log "  ⚠️ Impossible de récupérer l'Item de la publication pour les métadonnées : $($_.Exception.Message)" "WARNING"
                        }

                        # GESTION TAGS
                        if ($pub.Tags -and $pubItem) {
                            Update-SPTags -Item $pubItem -TagsConfig $pub.Tags -List $TargetLibraryName -Connection $targetCtx
                        }

                        # C-ter. PUBLICATION METADATA (Formulaire -> Dossier Cible)
                        if ($pub.UseFormMetadata -and $RootMetadata -and $RootMetadata.Count -gt 0) {
                            Log "  > Application des métadonnées du formulaire sur le dossier cible de la publication..." "DEBUG"
                            try {
                                $targetFolderItem = $null

                                # 1. On tente d'utiliser le dossier déjà résolu pour la création du raccourci
                                if ($resolvedDest) {
                                    # Si ListItem manquant, on le recharge
                                    if (-not $resolvedDest.ListItemAllFields -or -not $resolvedDest.ListItemAllFields.Id) {
                                        $resolvedDest = Get-PnPFolder -Url $resolvedDest.ServerRelativeUrl -Includes ListItemAllFields -Connection $targetCtx -ErrorAction SilentlyContinue
                                    }
                                    $targetFolderItem = $resolvedDest.ListItemAllFields
                                }
                                
                                # 2. Fallback si non résolu ou item manquant
                                if (-not $targetFolderItem) {
                                    $tmpFolder = Resolve-PnPFolder -SiteRelativePath $rawDestPath -Connection $targetCtx -ErrorAction Stop
                                    $tmpFolder = Get-PnPFolder -Url $tmpFolder.ServerRelativeUrl -Includes ListItemAllFields -Connection $targetCtx -ErrorAction Stop
                                    $targetFolderItem = $tmpFolder.ListItemAllFields
                                }

                                if ($targetFolderItem) {
                                    # Conversion Metadata -> Format Tags
                                    $metaTags = @()
                                    foreach ($k in $RootMetadata.Keys) {
                                        $metaTags += [PSCustomObject]@{ Name = $k; Value = $RootMetadata[$k] }
                                    }
                                    
                                    Update-SPTags -Item $targetFolderItem -TagsConfig $metaTags -List $TargetLibraryName -Connection $targetCtx
                                    Log "    Metadonnées appliquées sur le dossier '$rawDestPath'." "INFO"
                                }
                                else {
                                    Log "  ⚠️ Erreur Meta Pub : Impossible de récupérer l'Item du dossier cible." "WARNING"
                                }
                            }
                            catch { Log "  ⚠️ Erreur Meta Pub : $($_.Exception.Message)" "WARNING" }
                        }

                        # C-quater. PROPAGATION ID DEPLOIEMENT (PROPERTY BAG)
                        if ($globalDeployId) {
                            $folderToTag = $resolvedDest
                            if (-not $folderToTag) {
                                try { $folderToTag = Resolve-PnPFolder -SiteRelativePath $rawDestPath -Connection $targetCtx -ErrorAction Stop } catch {}
                            }
                            
                            if ($folderToTag) {
                                Log "  > Application de l'ID de déploiement principal ($globalDeployId) sur la publication..." "DEBUG"
                                try {
                                    $ctxTarget = $folderToTag.Context
                                    $ctxTarget.Load($folderToTag.Properties)
                                    $ctxTarget.ExecuteQuery()
                                    
                                    $folderToTag.Properties["_AppDeploymentId"] = $globalDeployId
                                    $folderToTag.Update()
                                    $ctxTarget.ExecuteQuery()
                                    
                                    Log "    Tag ID Déploiement ajouté sur la destination." "INFO"
                                }
                                catch {
                                    Log "  ⚠️ Erreur application ID Déploiement : $($_.Exception.Message)" "WARNING"
                                }
                            }
                        }

                    }
                    catch {
                        Log "  ❌ Erreur traitement publication : $($_.Exception.Message)" "ERROR"
                    }
                }
            } # Fin Bloc Publication

            # 7. RÉCUPÉRATION RECURSIVE (Classique)
            if ($FolderObj.Folders) {
                foreach ($sub in $FolderObj.Folders) {
                    # On ignore les noeuds PUBLICATION ici car ils sont traités spécifiquement plus haut.
                    # FIX: On laisse passer les LIENS (Type=Link) pour qu'ils soient traités par l'appel récursif (qui gère le cas unitaire).
                    if ($sub.Type -ne "Publication") {
                        Set-NewFolder -CurrentPath $folder.ServerRelativeUrl -FolderObj $sub
                    }
                }
            }
        } # End Function Set-NewFolder

        # --- CORRECTION 2 : Gestion Racine vs Pas de Racine ---
        $startPath = $libUrl

        if (-not [string]::IsNullOrWhiteSpace($RootFolderName)) {
            Log (Loc "log_deploy_create_root" $RootFolderName) "INFO"
            try {
                # Support Path Nesting (Parent/Child) via Resolve-PnPFolder
                $fullRootPath = "$libUrl/$RootFolderName"
                
                # Conversion en SiteRelative pour éviter AccessDenied sur certains contextes PnP
                $siteUri = [Uri]$TargetSiteUrl
                $sitePath = $siteUri.AbsolutePath.TrimEnd('/')
                $pnpPath = $fullRootPath
                if ($pnpPath.StartsWith($sitePath, [System.StringComparison]::InvariantCultureIgnoreCase)) { 
                    $pnpPath = $pnpPath.Substring($sitePath.Length).TrimStart('/') 
                }
                
                Log (Loc "log_deploy_path_conv" $pnpPath) "DEBUG"
                $rootFolder = Resolve-PnPFolder -SiteRelativePath $pnpPath -Connection $conn -ErrorAction Stop
                
                $startPath = $rootFolder.ServerRelativeUrl
                Log (Loc "log_deploy_root_ok" $startPath) "SUCCESS"
                
                # APPLICATION METADONNÉES RACINE (Formulaire)
                if ($RootMetadata -and $RootMetadata.Count -gt 0) {
                    Log (Loc "log_deploy_root_meta") "DEBUG"
                    try {
                        # Récupération Item Dossier Racine
                        $rootItem = Get-PnPFolder -Url $rootFolder.ServerRelativeUrl -Includes ListItemAllFields -Connection $conn -ErrorAction Stop
                        if ($rootItem.ListItemAllFields) {
                            # Conversion Standard
                            $metaTags = @()
                            foreach ($k in $RootMetadata.Keys) {
                                $metaTags += [PSCustomObject]@{ Name = $k; Value = $RootMetadata[$k] }
                            }
                            Update-SPTags -Item $rootItem.ListItemAllFields -TagsConfig $metaTags -List $TargetLibraryName -Connection $conn
                            Log "Métadonnées de formulaire appliquées au dossier racine." "INFO"
                        }
                    }
                    catch { Log "⚠️ Erreur application métadonnées racine : $($_.Exception.Message)" "WARNING" }
                }

                # =========================================================================================
                # PERSISTENCE & TRACKING (NOUVEAU)
                # =========================================================================================
                if ($TrackingInfo -and $TrackingInfo.Count -gt 0) {
                    Log "Initialization du suivi de déploiement (Tracking)..." "DEBUG"
                    try {
                        # 1. Provisionning de la liste cachée (Une fois par site)
                        # On charge le helper à la volée si besoin (normalement importé via Module)
                        if (Get-Command "New-AppSPTrackingList" -ErrorAction SilentlyContinue) {
                            New-AppSPTrackingList -Connection $conn | Out-Null
                        }

                        # 2. Génération Deployment ID
                        $deployId = $globalDeployId
                        if (-not $deployId) { $deployId = [Guid]::NewGuid().ToString() } # Fallback sécurité
                        
                        # 3. Marquage du Dossier (Property Bag)
                        # Fix: EnsureProperties n'est pas toujours dispo sur l'objet Folder wrapper.
                        # On utilise CSOM Standard.
                        
                        $ctx = $rootFolder.Context
                        $ctx.Load($rootFolder.Properties)
                        $ctx.ExecuteQuery()
                        
                        $rootFolder.Properties["_AppDeploymentId"] = $deployId
                        $rootFolder.Update()
                        $ctx.ExecuteQuery()
                        
                        Log "Dossier marqué avec ID: $deployId" "DEBUG"

                        # 4. Enregistrement Historique dans la Liste
                        $itemValues = @{
                            "Title"              = $deployId
                            "TargetUrl"          = $startPath
                            "TemplateId"         = $TrackingInfo["TemplateId"]
                            "TemplateVersion"    = $TrackingInfo["TemplateVersion"]
                            "NamingRuleId"       = $TrackingInfo["NamingRuleId"]
                            "ConfigName"         = $TrackingInfo["ConfigName"]
                            "DeployedBy"         = $TrackingInfo["DeployedBy"]
                            "TemplateJson"       = $StructureJson
                            "FormValuesJson"     = ($FormValues | ConvertTo-Json -Depth 5 -Compress)
                            "FormDefinitionJson" = $TrackingInfo["FormDefinitionJson"] # Schema
                            "DeployedDate"       = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
                        }
                        Add-PnPListItem -List "App_DeploymentHistory" -Values $itemValues -Connection $conn -ErrorAction Stop | Out-Null
                        Log "Historique de déploiement archivé dans 'App_DeploymentHistory'." "SUCCESS"
                    }
                    catch {
                        Log "⚠️ Erreur Tracking : $($_.Exception.Message)" "WARNING"
                    }
                }

            }
            catch {
                Err "Erreur racine : $($_.Exception.Message)"
                return $result
            }
        }
        else {
            Log "Déploiement direct à la racine de la bibliothèque." "INFO"
        }

        # Lancement Récursion
        if ($structure.Folders) {
            foreach ($f in $structure.Folders) { 
                Set-NewFolder -CurrentPath $startPath -FolderObj $f 
            }
        }
        else {
            Set-NewFolder -CurrentPath $startPath -FolderObj $structure
        }

        Log (Loc "log_deploy_finished") "SUCCESS"

    }
    catch {
        Err "CRASH MOTEUR : $($_.Exception.Message)"
    }

    return $result
}