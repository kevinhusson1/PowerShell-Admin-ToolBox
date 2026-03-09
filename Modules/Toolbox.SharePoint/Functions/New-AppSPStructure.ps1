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
                    $gType = switch ($c.Type) { "Nombre" { "Number" } "Choix" { "Choice" } "Choix Multiples" { "Choice" } Default { "Text" } }
                    
                    # Récupération des choix uniques pour pré-remplir la colonne
                    $choices = @()
                    if ($gType -eq "Choice") {
                        $choices = $plan | ForEach-Object { $_.Tags | Where-Object { $_.Name -eq $c.Name } | Select-Object -ExpandProperty Value } | Select-Object -Unique
                        if (-not $choices) { $choices = @("Default Choice") }
                    }

                    $resCol = New-AppGraphSiteColumn -SiteId $siteId -Name $c.Name -DisplayName $c.Name -Type $gType -Choices $choices -AllowMultiple:$isMulti
                    if ($resCol) { $colIds += $resCol.Column.id }
                }

                $ctSafeName = "SBuilder_" + ($FolderSchemaName -replace '[\\/:*?"<>|#%]', '_')
                $resCT = New-AppGraphContentType -SiteId $siteId -Name $ctSafeName -BaseId "0x0120" -ColumnIdsToBind $colIds
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
                $fields = @{}
                if ($applyCT) { $fields["contentType"] = @{ id = $FolderContentTypeId } }
                if ($RootMetadata) { foreach ($k in $RootMetadata.Keys) { $fields[$k] = $RootMetadata[$k] } }
                Set-AppGraphListItemMetadata -SiteId $siteId -ListId $listId -ListItemId $rootRes.id -Fields $fields | Out-Null
            }
        }

        # -- Boucle de Déploiement --
        foreach ($op in $plan) {
            $parentId = $startParentId
            if ($op.ParentId -and $op.ParentId -ne "root" -and $DeployedFoldersMap.ContainsKey($op.ParentId)) {
                $parentId = $DeployedFoldersMap[$op.ParentId]
            }

            switch ($op.Type) {
                "Folder" {
                    Log "Création : $($op.Name)" "INFO"
                    $fRes = New-AppGraphFolder -SiteId $siteId -DriveId $driveId -FolderName $op.Name -ParentFolderId $parentId
                    if ($op.Id) { $DeployedFoldersMap[$op.Id] = $fRes.id }

                    # Meta & CT
                    $fields = @{}
                    if ($applyCT) { $fields["contentType"] = @{ id = $FolderContentTypeId } }
                    if ($op.Tags) { foreach ($t in $op.Tags) { $fields[$t.Name] = $t.Value } }
                    if ($fields.Count -gt 0) {
                        Set-AppGraphListItemMetadata -SiteId $siteId -ListId $listId -ListItemId $fRes.id -Fields $fields | Out-Null
                    }

                    # Permissions
                    if ($op.Permissions) {
                        foreach ($p in $op.Permissions) {
                            $role = switch ($p.Level.ToLower()) { "full control" { "write" } "contribute" { "write" } default { "read" } }
                            $inviteBody = @{ recipients = @( @{ email = $p.Email } ); roles = @($role); requireSignIn = $true; sendSignInPromo = $false } | ConvertTo-Json -Depth 5
                            Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$driveId/items/$($fRes.id)/invite" -Body $inviteBody -ContentType "application/json" | Out-Null
                        }
                    }
                }
                "Link" {
                    Log "Lien externe : $($op.Name)" "INFO"
                    $linkContent = "[InternetShortcut]`nURL=$($op.RawNode.Url)"
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($linkContent)
                    $safeName = if ($op.Name -like "*.url") { $op.Name } else { "$($op.Name).url" }
                    $uriUpload = "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$driveId/items/$parentId`:/$safeName`:/content"
                    Invoke-MgGraphRequest -Method PUT -Uri $uriUpload -Body $bytes -ContentType "text/plain" | Out-Null
                }
                "InternalLink" {
                    Log "Lien interne : $($op.Name)" "INFO"
                    if ($op.TargetPath) {
                        # @todo: Résoudre l'URL web du dossier cible via Graph pour le raccourci
                        Log "  Cible : $($op.TargetPath)" "DEBUG"
                    }
                }
                "File" {
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
