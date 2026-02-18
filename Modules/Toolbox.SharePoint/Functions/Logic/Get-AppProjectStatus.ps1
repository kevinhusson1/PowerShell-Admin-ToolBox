function Get-AppProjectStatus {
    param(
        [Parameter(Mandatory)] [string]$SiteUrl,
        [Parameter(Mandatory)] [string]$FolderUrl,
        [Parameter(Mandatory)] [string]$ClientId,
        [Parameter(Mandatory)] [string]$Thumbprint,
        [Parameter(Mandatory)] [string]$TenantName
    )

    $status = [PSCustomObject]@{
        Exists       = $false
        IsTracked    = $false
        DeploymentId = $null
        HistoryItem  = $null
        FolderItem   = $null
        Error        = $null
    }

    try {
        # 1. CONNEXION
        Write-Output "[LOG] Connexion PnP en cours vers : $SiteUrl"
        $cleanTenant = $TenantName -replace "\.onmicrosoft\.com$", ""
        
        # [FIX] Force return connection to avoid ambient context issues in Jobs
        $conn = Connect-PnPOnline -Url $SiteUrl -ClientId $ClientId -Thumbprint $Thumbprint -Tenant "$cleanTenant.onmicrosoft.com" -ReturnConnection -ErrorAction Stop
        Write-Output "[LOG] Connexion établie (App-Only)."

        # 2. RESOLUTION DOSSIER
        Write-Output "[LOG] Résolution du chemin relatif : $FolderUrl"
        
        try {
            # Conversion ServerRelative -> SiteRelative pour Resolve-PnPFolder
            $uri = [Uri]$SiteUrl
            $sitePath = $uri.AbsolutePath.TrimEnd('/') # /sites/MySite
            
            $targetPath = $FolderUrl
            if ($targetPath.StartsWith($sitePath, [System.StringComparison]::InvariantCultureIgnoreCase)) {
                $targetPath = $targetPath.Substring($sitePath.Length).TrimStart('/')
            }
            
            $folder = Resolve-PnPFolder -SiteRelativePath $targetPath -Connection $conn -ErrorAction Stop
            $status.Exists = $true
            Write-Output "[LOG] Dossier trouvé : $targetPath"
        }
        catch {
            Write-Output "[LOG] ECHEC: Dossier introuvable ou accès refusé."
            $status.Error = "Dossier introuvable : $targetPath"
            return $status
        }

        # 3. LECTURE PROPERTY BAG (via CSOM pour fiabilité)
        Write-Output "[LOG] Lecture des propriétés du dossier (Recherche de GUID)..."
        $ctx = $conn.Context
        $ctx.Load($folder)
        $ctx.Load($folder.Properties)
        $ctx.Load($folder.ListItemAllFields) # Pour les métadonnées
        $ctx.ExecuteQuery()

        $status.FolderItem = $folder.ListItemAllFields
        
        if ($folder.Properties.FieldValues.ContainsKey("_AppDeploymentId")) {
            $guid = $folder.Properties["_AppDeploymentId"]
            $status.IsTracked = $true
            $status.DeploymentId = $guid
            Write-Output "[LOG] Projet SUIVI détecté. ID = $guid"
        }
        else {
            Write-Output "[LOG] Aucun ID de déploiement trouvé sur ce dossier."
        }

        # 4. LECTURE HISTORY LIST
        if ($status.IsTracked) {
            Write-Output "[LOG] Recherche de détails dans 'App_DeploymentHistory'..."
            $caml = @"
            <View>
                <Query>
                    <Where>
                        <Eq><FieldRef Name='Title'/><Value Type='Text'>$($status.DeploymentId)</Value></Eq>
                    </Where>
                </Query>
                <RowLimit>1</RowLimit>
            </View>
"@
            $historyItems = Get-PnPListItem -List "App_DeploymentHistory" -Query $caml -Connection $conn -ErrorAction SilentlyContinue
            
            # [FIX] Robust selection (Handle Scalar vs Array)
            $h = $historyItems | Select-Object -First 1
            
            if ($h) {
                Write-Output "[LOG] Historique trouvé. Chargement des métadonnées..."
                
                $status.HistoryItem = [PSCustomObject]@{
                    Title           = $h["Title"]
                    ConfigName      = $h["ConfigName"]
                    TemplateVersion = $h["TemplateVersion"]
                    DeployedDate    = $h["DeployedDate"]
                    DeployedBy      = $h["DeployedBy"]
                    FormValuesJson  = $h["FormValuesJson"]
                    TemplateJson    = $h["TemplateJson"]
                }
            }
            else {
                Write-Output "[LOG] AVERTISSEMENT: ID trouvé, mais aucune entrée dans l'historique."
            }
        }

    }
    catch {
        Write-Output "[LOG] ERREUR CRITIQUE: $($_.Exception.Message)"
        $status.Error = $_.Exception.Message
    }

    return $status
}
