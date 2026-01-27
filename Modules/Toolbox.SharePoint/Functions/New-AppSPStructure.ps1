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
        [Parameter(Mandatory = $false)] [string]$TargetFolderUrl
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
        # On simule un parcours virtuel
        if ($structure.Folders) { Build-IdMap -SubStructure $structure.Folders -CurrentPath "" }
        else { Build-IdMap -SubStructure $structure -CurrentPath "" }

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
                    
                    # GESTION TAGS POUR LIENS
                    if ($FolderObj.Tags) {
                        Log (Loc "log_deploy_apply_tags") "DEBUG"
                        $valuesHash = @{}
                        foreach ($tag in $FolderObj.Tags) { $valuesHash[$tag.Name] = $tag.Value }
                         
                        if ($valuesHash.Count -gt 0) {
                            try {
                                # Récupération Item
                                $fileItem = $resLink.File.ListItemAllFields
                                if (-not $fileItem) {
                                    # Fallback : Re-fetch si l'objet retourné n'a pas les champs chargés
                                    $temp = Get-PnPFile -Url $resLink.File.ServerRelativeUrl -AsListItem -Connection $conn -ErrorAction Stop
                                    $fileItem = $temp
                                }
                                 
                                Set-PnPListItem -List $TargetLibraryName -Identity $fileItem.Id -Values $valuesHash -Connection $conn -ErrorAction Stop
                                Log (Loc "log_deploy_tags_applied") "INFO"
                            }
                            catch { Err "Erreur Tags Lien : $($_.Exception.Message)" }
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
                # Attention : $libUrl est ServerRelative (ex: /sites/MySite/MyLib)
                
                $uri = New-Object Uri($TargetSiteUrl)
                $baseHost = "$($uri.Scheme)://$($uri.Host)"
                $fullTargetUrl = "$baseHost$startPath$relPath"
                
                # B. Création .url
                if (-not $linkName.EndsWith(".url")) { $linkName += ".url" }
                
                $resLink = New-AppSPLink -Name $linkName -TargetUrl $fullTargetUrl -Folder $CurrentPath -Connection $conn
                if ($resLink.Success) { 
                    Log "Lien interne créé vers '$relPath'." "DEBUG" 
                    
                    # GESTION TAGS POUR LIENS INTERNES
                    if ($FolderObj.Tags) {
                        Log (Loc "log_deploy_apply_tags") "DEBUG"
                        $valuesHash = @{}
                        foreach ($tag in $FolderObj.Tags) { $valuesHash[$tag.Name] = $tag.Value }
                         
                        if ($valuesHash.Count -gt 0) {
                            try {
                                # Item
                                $fileItem = $resLink.File.ListItemAllFields
                                if (-not $fileItem) {
                                    $temp = Get-PnPFile -Url $resLink.File.ServerRelativeUrl -AsListItem -Connection $conn -ErrorAction Stop
                                    $fileItem = $temp
                                }
                                 
                                Set-PnPListItem -List $TargetLibraryName -Identity $fileItem.Id -Values $valuesHash -Connection $conn -ErrorAction Stop
                                Log (Loc "log_deploy_tags_applied") "INFO"
                            }
                            catch { Err "Erreur Tags Lien Interne : $($_.Exception.Message)" }
                        }
                    }
                }
                else { Err "Erreur lien interne '$linkName' : $($resLink.Message)" }
                return
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
                            $spRole = switch ($role.ToLower()) { "read" { "Read" } "contribute" { "Contribute" } "full" { "Full Control" } Default { "Read" } }
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

                # 4. TAGS
                if ($FolderObj.Tags) {
                    Log (Loc "log_deploy_apply_tags") "DEBUG"
                    $valuesHash = @{}
                    foreach ($tag in $FolderObj.Tags) { $valuesHash[$tag.Name] = $tag.Value }
                    if ($valuesHash.Count -gt 0) {
                        try {
                            Set-PnPListItem -List $TargetLibraryName -Identity $folderItem.Id -Values $valuesHash -Connection $conn -ErrorAction Stop
                            Log (Loc "log_deploy_tags_applied") "INFO"
                        }
                        catch { Err "Erreur Tags : $($_.Exception.Message)" }
                    }
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
                        if ($pub.UseModelName -eq $true -and -not [string]::IsNullOrWhiteSpace($RootFolderName)) {
                            $rawDestPath = "$rawDestPath/$RootFolderName"
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

                        # C-bis. GESTION TAGS SUR LA PUBLICATION (CIBLE)
                        if ($pub.Tags) {
                            Log "Application des tags sur la publication..." "DEBUG"
                            $valuesHash = @{}
                            foreach ($tag in $pub.Tags) { $valuesHash[$tag.Name] = $tag.Value }
                             
                            if ($valuesHash.Count -gt 0) {
                                try {
                                    # Récupération Item Cible
                                    $pubItem = $resShortcut.File.ListItemAllFields
                                    if (-not $pubItem) {
                                        $temp = Get-PnPFile -Url $resShortcut.File.ServerRelativeUrl -AsListItem -Connection $targetCtx -ErrorAction Stop
                                        $pubItem = $temp
                                    }
                                    # Note: On doit identifier la List de destination. Resolve-PnPFolder nous a donné un folder.
                                    # On peut essayer de déduire la List via le contexte ou l'item.
                                    # Pour simplifier, on applique sur l'item récupéré (ListItem object direct PnP)
                                     
                                    # Set-PnPListItem sur un objet ListItem direct nécessite PnP 1.5+ ou Identity
                                    # Si on a l'ID et la List Id, c'est mieux.
                                     
                                    # Astuce : Set-PnPListItem accepte -Identity <ListItem> sur le contexte courant
                                    Set-PnPListItem -Identity $pubItem -Values $valuesHash -Connection $targetCtx -ErrorAction Stop
                                    Log "Tags appliqués sur la publication." "INFO"
                                }
                                catch {
                                    Log "  ⚠️ Erreur Tags Publication : $($_.Exception.Message)" "WARNING"
                                }
                            }
                        }

                        # D. ATTRIBUTION DROITS SOURCE (GRANT)
                        if ($pub.GrantUser) {
                            $spRole = switch ($pub.GrantLevel) { "Contribute" { "Contribute" } Default { "Read" } }
                            Log (Loc "log_deploy_pub_grant" @($pub.GrantUser, $spRole)) "DEBUG"
                            try {
                                Set-PnPListItemPermission -List $TargetLibraryName -Identity $folderItem.Id -User $pub.GrantUser -AddRole $spRole -Connection $conn -ErrorAction Stop
                                Log (Loc "log_deploy_pub_rights_ok") "INFO"
                            }
                            catch {
                                # Retry User
                                try {
                                    New-PnPUser -LoginName $pub.GrantUser -Connection $conn -ErrorAction SilentlyContinue | Out-Null
                                    Set-PnPListItemPermission -List $TargetLibraryName -Identity $folderItem.Id -User $pub.GrantUser -AddRole $spRole -Connection $conn -ErrorAction Stop
                                    Log (Loc "log_deploy_pub_rights_ok") "INFO"
                                }
                                catch {
                                    Log "  ⚠️ Erreur droits : $($_.Exception.Message)" "WARNING"
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