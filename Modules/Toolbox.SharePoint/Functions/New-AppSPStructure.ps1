function New-AppSPStructure {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$TargetSiteUrl,
        [Parameter(Mandatory)] [string]$TargetLibraryName,
        [Parameter(Mandatory)] [string]$RootFolderName,
        [Parameter(Mandatory)] [string]$StructureJson,
        [Parameter(Mandatory)] [string]$ClientId,
        [Parameter(Mandatory)] [string]$Thumbprint,
        [Parameter(Mandatory)] [string]$TenantName
    )

    $result = @{ Success = $true; Logs = [System.Collections.Generic.List[string]]::new(); Errors = [System.Collections.Generic.List[string]]::new() }

    function Log { param($m, $l="INFO") $result.Logs.Add("$l|$m"); Write-Verbose "[$l] $m" }
    function Err { param($m) $result.Errors.Add($m); $result.Success = $false; Log $m "ERROR"; Write-Error $m }

    try {
        Log "Initialisation..." "DEBUG"
        $cleanTenant = $TenantName -replace "\.onmicrosoft\.com$", "" -replace "\.sharepoint\.com$", ""
        
        $conn = Connect-PnPOnline -Url $TargetSiteUrl -ClientId $ClientId -Thumbprint $Thumbprint -Tenant "$cleanTenant.onmicrosoft.com" -ReturnConnection -ErrorAction Stop
        Log "Connexion établie sur $TargetSiteUrl" "INFO"

        Log "Vérification de la bibliothèque '$TargetLibraryName'..." "DEBUG"
        $targetLib = Get-PnPList -Identity $TargetLibraryName -Includes RootFolder -Connection $conn -ErrorAction Stop
        if (-not $targetLib) { throw "Bibliothèque introuvable." }
        
        $libUrl = $targetLib.RootFolder.ServerRelativeUrl.TrimEnd('/')
        Log "Racine détectée : $libUrl" "DEBUG"
        
        $structure = $StructureJson | ConvertFrom-Json
        
        function Process-Folder {
            param($CurrentPath, $FolderObj)

            $folderName = $FolderObj.Name
            if ($CurrentPath -eq $libUrl) { $folderName = $RootFolderName }
            $fullPath = "$CurrentPath/$folderName"
            
            Log "Traitement du dossier : $fullPath" "INFO"
            
            # 1. CRÉATION DOSSIER
            try {
                $folder = Add-PnPFolder -Name $folderName -Folder $CurrentPath -Connection $conn -ErrorAction Stop
                Log "Dossier validé : $($folder.Name)" "DEBUG"
            } catch {
                try {
                    $folder = Resolve-PnPFolder -SiteRelativePath $fullPath -Connection $conn -ErrorAction Stop
                } catch {
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
                } catch {
                    Start-Sleep -Milliseconds 500
                    $retry++
                }
            }
            
            if (-not $folderItem) {
                Log "⚠️ Impossible de récupérer l'Item SharePoint (Droits/Tags ignorés)." "WARNING"
            } 
            else {
                # 3. PERMISSIONS (Mode Additif par défaut)
                if ($FolderObj.Permissions) {
                    Log "Application des permissions..." "DEBUG"
                    try {
                        # --- OPTIONNEL : CASSER L'HÉRITAGE SI DEMANDÉ ---
                        # Si tu ajoutes "BreakInheritance": true dans le JSON plus tard :
                        if ($FolderObj.BreakInheritance -eq $true) {
                             Log "Rupture d'héritage demandée." "INFO"
                             # Break-PnPListItemRoleInheritance -List $TargetLibraryName -Identity $folderItem.Id -CopyRoleAssignments:$false -Connection $conn
                        }
                        # ------------------------------------------------

                        foreach ($perm in $FolderObj.Permissions) {
                            $email = $perm.Email
                            $role = $perm.Level
                            $spRole = switch ($role.ToLower()) { "read" {"Read"} "contribute" {"Contribute"} "full" {"Full Control"} Default {"Read"} }
                            
                            try {
                                Set-PnPListItemPermission -List $TargetLibraryName -Identity $folderItem.Id -User $email -AddRole $spRole -Connection $conn -ErrorAction Stop
                                Log "Permission ajoutée : $email -> $spRole" "INFO"
                            } catch {
                                # Retry avec création user
                                try {
                                    New-PnPUser -LoginName $email -Connection $conn -ErrorAction SilentlyContinue | Out-Null
                                    Set-PnPListItemPermission -List $TargetLibraryName -Identity $folderItem.Id -User $email -AddRole $spRole -Connection $conn -ErrorAction Stop
                                    Log "Permission ajoutée (après résolution) : $email" "INFO"
                                } catch {
                                    Log "Erreur permission pour $email : $($_.Exception.Message)" "WARNING"
                                }
                            }
                        }
                    } catch { Err "Erreur globale Permissions : $($_.Exception.Message)" }
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
                        } catch { Err "Erreur Tags : $($_.Exception.Message)" }
                    }
                }
            }

            # 5. LIENS
            if ($FolderObj.Links) {
                foreach ($link in $FolderObj.Links) {
                    Log "Création raccourci : $($link.Name)" "DEBUG"
                    try {
                        $tempFile = [System.IO.Path]::GetTempFileName() + ".url"
                        "[InternetShortcut]`r`nURL=$($link.Url)" | Set-Content -Path $tempFile
                        Add-PnPFile -Path $tempFile -Folder $folder.ServerRelativeUrl -NewFileName "$($link.Name).url" -Connection $conn | Out-Null
                        Remove-Item $tempFile -Force
                        Log "Raccourci créé." "INFO"
                    } catch { Err "Erreur Lien : $($_.Exception.Message)" }
                }
            }

            # 6. RÉCURSION
            if ($FolderObj.Folders) {
                foreach ($sub in $FolderObj.Folders) {
                    Process-Folder -CurrentPath $folder.ServerRelativeUrl -FolderObj $sub
                }
            }
        }

        # Lancement Racine
        Log "Création racine : $RootFolderName" "INFO"
        try {
            $rootFolder = Add-PnPFolder -Name $RootFolderName -Folder $libUrl -Connection $conn -ErrorAction Stop
            Log "Racine OK : $($rootFolder.ServerRelativeUrl)" "SUCCESS"
        } catch {
            Err "Erreur racine : $($_.Exception.Message)"
            return $result
        }

        # Lancement Récursion
        if ($structure.Folders) {
            foreach ($f in $structure.Folders) { 
                Process-Folder -CurrentPath $rootFolder.ServerRelativeUrl -FolderObj $f 
            }
        } else {
            Process-Folder -CurrentPath $libUrl -FolderObj $structure
        }

        Log "Déploiement terminé." "SUCCESS"

    } catch {
        Err "CRASH MOTEUR : $($_.Exception.Message)"
    }

    return $result
}