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

    try {
        Log "Initialisation..." "DEBUG"
        $cleanTenant = $TenantName -replace "\.onmicrosoft\.com$", "" -replace "\.sharepoint\.com$", ""
        
        $conn = Connect-PnPOnline -Url $TargetSiteUrl -ClientId $ClientId -Thumbprint $Thumbprint -Tenant "$cleanTenant.onmicrosoft.com" -ReturnConnection -ErrorAction Stop
        Log "Connexion établie sur $TargetSiteUrl" "INFO"

        Log "Vérification de la bibliothèque '$TargetLibraryName'..." "DEBUG"
        $targetLib = Get-PnPList -Identity $TargetLibraryName -Includes RootFolder -Connection $conn -ErrorAction Stop
        if (-not $targetLib) { throw "Bibliothèque introuvable." }
        
        # DEFINITION CIBLE (Correction)
        if (-not [string]::IsNullOrWhiteSpace($TargetFolderUrl)) {
            $libUrl = $TargetFolderUrl.TrimEnd('/')
            Log "Cible définie : $libUrl" "DEBUG"
        }
        else {
            $libUrl = $targetLib.RootFolder.ServerRelativeUrl.TrimEnd('/')
            Log "Racine détectée (Auto) : $libUrl" "DEBUG"
        }
        
        $structure = $StructureJson | ConvertFrom-Json
        
        function Process-Folder {
            param($CurrentPath, $FolderObj)

            # 0. GESTION TYPE = LINK (Nouveau Mode)
            if ($FolderObj.Type -eq "Link") {
                $linkName = $FolderObj.Name
                $linkUrl = $FolderObj.Url
                Log "Création lien (Noeud) : $linkName ($linkUrl)" "INFO"
                Log "Création lien (Noeud) : $linkName ($linkUrl)" "INFO"
                $resLink = New-AppSPLink -Name $linkName -TargetUrl $linkUrl -Folder $CurrentPath -Connection $conn
                if ($resLink.Success) { Log "Lien créé avec succès." "DEBUG" }
                else { Err "Erreur création lien '$linkName' : $($resLink.Message)" }
                return # Stop ici pour un lien
            }

            $folderName = $FolderObj.Name
            $fullPath = "$CurrentPath/$folderName"
            
            Log "Traitement du dossier : $fullPath" "INFO"
            
            # 1. CRÉATION DOSSIER
            try {
                $folder = Add-PnPFolder -Name $folderName -Folder $CurrentPath -Connection $conn -ErrorAction Stop
                Log "Dossier validé : $($folder.Name)" "DEBUG"
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
                                    Log "Permission ajoutée (après résolution) : $email" "INFO"
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
                    Log "Application des tags..." "DEBUG"
                    $valuesHash = @{}
                    foreach ($tag in $FolderObj.Tags) { $valuesHash[$tag.Name] = $tag.Value }
                    if ($valuesHash.Count -gt 0) {
                        try {
                            Set-PnPListItem -List $TargetLibraryName -Identity $folderItem.Id -Values $valuesHash -Connection $conn -ErrorAction Stop
                            Log "Tags appliqués." "INFO"
                        }
                        catch { Err "Erreur Tags : $($_.Exception.Message)" }
                    }
                }
            }

            # 5. LIENS (INTERNES)
            if ($FolderObj.Links) {
                foreach ($link in $FolderObj.Links) {
                    Log "Création raccourci : $($link.Name)" "DEBUG"
                    $resLink = New-AppSPLink -Name $link.Name -TargetUrl $link.Url -Folder $folder.ServerRelativeUrl -Connection $conn
                    if ($resLink.Success) { Log "Raccourci créé." "INFO" }
                    else { Err "Erreur Lien : $($resLink.Message)" }
                }
            }
            
            # =========================================================================================
            # 6. TRAITEMENT DES PUBLICATIONS (NOUVEAU)
            # =========================================================================================
            if ($FolderObj.Folders) {
                $pubs = $FolderObj.Folders | Where-Object { $_.Type -eq "Publication" }
                foreach ($pub in $pubs) {
                    Log "🚀 Traitement Publication : $($pub.Name)" "INFO"
                    
                    try {
                        # A. RÉCUPÉRATION URL SOURCE
                        $uri = New-Object Uri($TargetSiteUrl)
                        $baseHost = "$($uri.Scheme)://$($uri.Host)"
                        $sourceFullUrl = "$baseHost$($folder.ServerRelativeUrl)"
                        Log "  > Source : $sourceFullUrl" "DEBUG"

                        # B. DÉTERMINATION SITE CIBLE
                        $targetCtx = $conn 
                        
                        if ($pub.TargetSiteMode -eq "Url" -and -not [string]::IsNullOrWhiteSpace($pub.TargetSiteUrl)) {
                            Log "  > Connexion cible distante : $($pub.TargetSiteUrl)" "DEBUG"
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
                        
                        try {
                            $targetWeb = Get-PnPWeb -Connection $targetCtx
                            $targetWebUrl = $targetWeb.ServerRelativeUrl
                            
                            $finalDestPath = $rawDestPath
                            if (-not $finalDestPath.StartsWith("/")) { $finalDestPath = "/$finalDestPath" }
                            
                            # Nettoyage intelligent du path
                            # Pour éviter de doubler /sites/X si l'input était relatif au serveur et pas au site
                            if (-not $finalDestPath.StartsWith($targetWebUrl, [System.StringComparison]::InvariantCultureIgnoreCase)) {
                                if ($targetWebUrl -ne "/") {
                                    $finalDestPath = "$targetWebUrl$finalDestPath"
                                }
                            }
                            
                            # Conversion en Site Relative Path pour Resolve-PnPFolder
                            $siteRelativeDestPath = $finalDestPath
                            if ($siteRelativeDestPath.StartsWith($targetWebUrl, [System.StringComparison]::InvariantCultureIgnoreCase)) {
                                $siteRelativeDestPath = $siteRelativeDestPath.Substring($targetWebUrl.Length)
                            }
                            $siteRelativeDestPath = $siteRelativeDestPath.TrimStart('/')
                            
                            Log "  > Chemin Cible (SiteRelative) : $siteRelativeDestPath" "DEBUG"
                            
                            # On tente de résoudre ou créer
                            # Note: Resolve-PnPFolder nécessite un chemin relatif au site
                            $targetFolder = Resolve-PnPFolder -SiteRelativePath $siteRelativeDestPath -Connection $targetCtx -ErrorAction SilentlyContinue
                            
                            $targetFolder = Resolve-PnPFolder -SiteRelativePath $siteRelativeDestPath -Connection $targetCtx -ErrorAction SilentlyContinue
                            
                            if (-not $targetFolder) {
                                throw "Le dossier cible '$finalDestPath' n'existe pas (ou accès refusé)." 
                            }
                            
                            # CRÉATION FICHIER VIA FONCTION CENTRALISÉE
                            $resLink = New-AppSPLink -Name $linkName -TargetUrl $sourceFullUrl -Folder $finalDestPath -Connection $targetCtx
                            
                            if ($resLink.Success) {
                                Log "  > Raccourci créé dans la cible : $finalDestPath/$linkName" "SUCCESS"
                            }
                            else {
                                Log "  ⚠️ Erreur création raccourci : $($resLink.Message)" "WARNING"
                            }
                        }
                        catch {
                            Log "  ⚠️ Erreur cible : $($_.Exception.Message)" "WARNING"
                        }

                        # D. ATTRIBUTION DES DROITS SOURCE
                        if (-not [string]::IsNullOrWhiteSpace($pub.GrantUser)) {
                            Log "  > Attribution droits source à : $($pub.GrantUser) ($($pub.GrantLevel))" "DEBUG"
                            try {
                                $spRole = switch ($pub.GrantLevel) { "Contribute" { "Contribute" } Default { "Read" } }
                                Set-PnPListItemPermission -List $TargetLibraryName -Identity $folderItem.Id -User $pub.GrantUser -AddRole $spRole -Connection $conn -ErrorAction Stop
                                Log "  > Droits appliqués OK." "INFO"
                            }
                            catch {
                                try {
                                    New-PnPUser -LoginName $pub.GrantUser -Connection $conn -ErrorAction SilentlyContinue | Out-Null
                                    Set-PnPListItemPermission -List $TargetLibraryName -Identity $folderItem.Id -User $pub.GrantUser -AddRole $spRole -Connection $conn -ErrorAction Stop
                                    Log "  > Droits OK (après ajout user)." "INFO"
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
            }

            # 7. RÉCUPÉRATION RECURSIVE (Classique)
            if ($FolderObj.Folders) {
                foreach ($sub in $FolderObj.Folders) {
                    # On ignore les noeuds PUBLICATION ici car ils ne sont pas des dossiers physiques a créer EN DESSOUS
                    # On ignore aussi les LIENS car traités au début (Loop 0)
                    if ($sub.Type -ne "Publication" -and $sub.Type -ne "Link") {
                        Process-Folder -CurrentPath $folder.ServerRelativeUrl -FolderObj $sub
                    }
                }
            }
        } # End Function Process-Folder

        # --- CORRECTION 2 : Gestion Racine vs Pas de Racine ---
        $startPath = $libUrl

        if (-not [string]::IsNullOrWhiteSpace($RootFolderName)) {
            Log "Création racine : $RootFolderName" "INFO"
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
                
                Log "Path converti (PnP) : '$pnpPath'" "DEBUG"
                $rootFolder = Resolve-PnPFolder -SiteRelativePath $pnpPath -Connection $conn -ErrorAction Stop
                
                $startPath = $rootFolder.ServerRelativeUrl
                Log "Racine OK : $startPath" "SUCCESS"
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
                Process-Folder -CurrentPath $startPath -FolderObj $f 
            }
        }
        else {
            Process-Folder -CurrentPath $startPath -FolderObj $structure
        }

        Log "Déploiement terminé." "SUCCESS"

    }
    catch {
        Err "CRASH MOTEUR : $($_.Exception.Message)"
    }

    return $result
}