# Scripts/Sharepoint/SharepointTEST/Tests/12_FullDeploymentAudit.ps1

param(
    [Parameter(Mandatory = $false)]
    [string]$TargetUrl = "https://vosgelis365.sharepoint.com/sites/TEST_PNP/Shared%20Documents/General/TEST-2025-PPI"
)

# --- 1. CONFIGURATION & MODULES ---
$ProjectRoot = "c:\CLOUD\Github\PowerShell-Admin-ToolBox"
$ModulesPath = "$ProjectRoot\Modules"
$env:PSModulePath = "$ModulesPath;$ProjectRoot\Vendor;$env:PSModulePath"

Write-Host "[DEBUG] Chargement des modules..." -ForegroundColor Cyan
try {
    # On importe les modules de manière robuste
    Import-Module "PSSQLite" -Force
    Import-Module "$ModulesPath\Logging\Logging.psd1" -Force -ErrorAction Stop
    Import-Module "$ModulesPath\Database\Database.psd1" -Force -ErrorAction Stop
    
    # Initialisation de la base de données (Essentiel pour Get-AppConfiguration)
    Initialize-AppDatabase -ProjectRoot $ProjectRoot
    
    Import-Module "$ModulesPath\Core\Core.psd1" -Force -ErrorAction Stop
    Import-Module "$ModulesPath\Azure\Azure.psd1" -Force -ErrorAction Stop
    Import-Module "$ModulesPath\Toolbox.SharePoint\Toolbox.SharePoint.psd1" -Force -ErrorAction Stop
    Import-Module "$ModulesPath\Localization\Localization.psd1" -Force -ErrorAction Stop
    
    # Initialisation de la configuration globale
    $Global:AppConfig = Get-AppConfiguration
}
catch {
    Write-Host "[ERROR] Échec du chargement de l'environnement : $($_.Exception.Message)" -ForegroundColor Red
    return
}

# Helper de log (redéfini pour être robuste)
function Log {
    param($msg, $lvl = "Info")
    $color = switch ($lvl) {
        "Error" { "Red" }
        "Warning" { "Yellow" }
        "Success" { "Green" }
        "Debug" { "Cyan" }
        Default { "White" }
    }
    Write-Host "[$lvl] $msg" -ForegroundColor $color
    if (Get-Command Write-AppLog -ErrorAction SilentlyContinue) {
        Write-AppLog -Message $msg -Level $lvl
    }
}

Log "====================================================" "Info"
Log "   AUDIT DE DÉPLOIEMENT BUILDER (Graph v5.0)" "Info"
Log "====================================================" "Info"
Log "Cible : $TargetUrl" "Info"

# --- 2. CONNEXION ---
try {
    $Config = $Global:AppConfig
    Connect-AppAzureCert -TenantId $Config.azure.tenantId -ClientId $Config.azure.authentication.userAuth.appId -Thumbprint $Config.azure.certThumbprint | Out-Null
    Log "Connexion Microsoft Graph établie." "Debug"
}
catch {
    Log "Échec connexion : $_" "Error"
    return
}

# --- 3. RÉSOLUTION DE LA CIBLE ---
$resUrl = Resolve-AppSharePointUrl -Url $TargetUrl
if (-not $resUrl.IsValid) {
    Log "Impossible de parser l'URL : $($resUrl.Error)" "Error"
    return
}

$SiteUrl = $resUrl.SiteUrl
$ServerRelativeUrl = $resUrl.ServerRelativeUrl 

try {
    $siteId = Get-AppGraphSiteId -SiteUrl $SiteUrl
    Log "SiteId résolu : $siteId" "Debug"

    # Recherche de la bibliothèque
    Log "Identification de la bibliothèque..." "Debug"
    $listsRes = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/lists?`$select=id,displayName,webUrl,list&`$expand=drive"
    
    $targetLib = $null
    foreach ($l in $listsRes.value) {
        if ($l.list -and ($l.list.template -eq "documentLibrary" -or $l.list.template -eq 101)) {
            $libUrl = [System.Uri]::new($l.webUrl).AbsolutePath
            if ($ServerRelativeUrl.StartsWith($libUrl)) {
                $targetLib = $l
                break
            }
        }
    }

    if (-not $targetLib) { throw "Impossible de trouver la bibliothèque pour le chemin relatif : $ServerRelativeUrl" }
    
    $listId = $targetLib.id
    $driveId = $targetLib.drive.id
    $libRelUrl = [System.Uri]::new($targetLib.webUrl).AbsolutePath
    Log "Bibliothèque trouvée : $($targetLib.displayName) (ListId: $listId, DriveId: $driveId)" "Success"

    # Calcul du chemin relatif AU DRIVE
    $pathInDrive = $ServerRelativeUrl.Substring($libRelUrl.Length)
    if (-not $pathInDrive.StartsWith("/")) { $pathInDrive = "/" + $pathInDrive }
    
    # Récupération de l'ItemId du dossier cible
    $itemUri = "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$driveId/root:$($pathInDrive)"
    $targetItem = Invoke-MgGraphRequest -Method GET -Uri $itemUri
    $targetItemId = $targetItem.id
    Log "ItemId du dossier cible : $targetItemId" "Success"

}
catch {
    Log "Échec de résolution de la cible : $($_.Exception.Message)" "Error"
    return
}

# --- 4. AUDIT DU TRACKING ---
Log "--- ÉTAPE 1 : AUDIT DU SUIVI (SharePointBuilder_Tracking) ---" "Info"
$trackFound = $false
try {
    $trackingLibName = "SharePointBuilder_Tracking"
    $trackList = $listsRes.value | Where-Object { $_.displayName -eq $trackingLibName }
    
    if (-not $trackList) {
        Log "Liste de tracking '$trackingLibName' absente." "Warning"
    }
    else {
        $trackListId = $trackList.id
        $uriTrackItems = "https://graph.microsoft.com/v1.0/sites/$siteId/lists/$trackListId/items?`$expand=fields"
        $allTrack = Invoke-MgGraphRequest -Method GET -Uri $uriTrackItems
        $entry = $allTrack.value | Where-Object { $_.fields.TargetUrl -eq $TargetUrl } | Select-Object -Last 1
        
        if ($entry) {
            $f = $entry.fields
            Log "[TRACABILITÉ] Déploiement trouvé !" "Success"
            Log "  > Modèle : $($f.TemplateId) (v$($f.TemplateVersion))" "Info"
            Log "  > Config : $($f.ConfigName)" "Info"
            Log "  > Auteur  : $($f.DeployedBy)" "Info"
            Log "  > Date    : $($f.DeployedDate)" "Info"
            # Affichage des options (v5.1)
            $optStr = "Options : Racine={0}, Meta={1}, Perms={2}" -f ([bool]$f.CreateRootFolder), ([bool]$f.ApplyMetadata), ([bool]$f.OverwritePermissions)
            Log "  > $optStr" "Info"
            $trackFound = $true
        }
        else {
            Log "Aucun enregistrement trouvé dans le tracking." "Warning"
        }
    }
}
catch {
    Log "Erreur audit tracking : $_" "Warning"
}

# --- 5. AUDIT DE L'ÉTAT ---
Log "--- ÉTAPE 2 : AUDIT DE L'ÉTAT IN-SITU (SharePointBuilder_States) ---" "Info"
$stateObj = $null
try {
    $stateLibName = "SharePointBuilder_States"
    $stateLib = $listsRes.value | Where-Object { $_.displayName -eq $stateLibName }
    
    if ($stateLib) {
        $stateDriveId = $stateLib.drive.id
        $stateContent = $null
        
        # Tentative d'accès direct par ID (v5.1 - Ultra Rapide)
        if ($trackFound -and $f.StateFileId) {
            Log "Récupération directe de l'état (ID: $($f.StateFileId))..." "Debug"
            try {
                $stateContent = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$stateDriveId/items/$($f.StateFileId)/content"
            } catch { Log "  > Échec accès direct par ID, fallback sur recherche par nom..." "DEBUG" }
        }

        # Fallback : Recherche par nom si ID non fourni ou non trouvé
        if (-not $stateContent) {
            $stateFileName = "${driveId}_${targetItemId}_state.json"
            Log "Recherche du fichier d'état : $stateFileName" "Debug"
            $statesRes = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$stateDriveId/root/children?`$filter=name eq '$stateFileName'"
            
            if ($statesRes.value -and $statesRes.value.Count -gt 0) {
                $stateItem = $statesRes.value[0]
                $stateContentUri = "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$stateDriveId/items/$($stateItem.id)/content"
                $stateContent = Invoke-MgGraphRequest -Method GET -Uri $stateContentUri
            }
        }
        
        if ($stateContent) {
            # Invoke-MgGraphRequest peut désérialiser automatiquement en Hashtable
            if ($stateContent -is [string]) { $stateObj = $stateContent | ConvertFrom-Json }
            else { $stateObj = $stateContent }
            
            Log "Document d'état '.state.json' récupéré avec succès." "Success"
            Log "  > Timestamp : $($stateObj.Timestamp)" "Info"
            $nodeCount = if ($stateObj.Nodes -is [System.Collections.IDictionary]) { $stateObj.Nodes.Count } else { $stateObj.Nodes.PSObject.Properties.Count }
            Log "  > Noeuds    : $nodeCount" "Info"
        }
        else {
            Log "Fichier d'état non trouvé." "Warning"
        }
    }
}
catch {
    Log "Erreur à la récupération de l'état : $_" "Warning"
}

# --- 6. VÉRIFICATION INTÉGRITÉ ---
if ($stateObj) {
    $nodes = $stateObj.Nodes
    $total = 0; $success = 0
    
    # Itération robuste (Hashtable ou PSCustomObject)
    $entries = if ($nodes -is [System.Collections.IDictionary]) { $nodes.GetEnumerator() } else { $nodes.PSObject.Properties }

    foreach ($entry in $entries) {
        $total++; 
        $editorId = if ($entry -is [System.Collections.DictionaryEntry]) { $entry.Key } else { $entry.Name }
        $spId = if ($entry -is [System.Collections.DictionaryEntry]) { $entry.Value } else { $entry.Value }
        
        try {
            $check = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$driveId/items/$spId" -ErrorAction SilentlyContinue
            $success++
        }
        catch {}
    }
    
    if ($success -eq $total) { Log "INTÉGRITÉ : 100% ($success/$total éléments présents)." "Success" }
    else { Log "INTÉGRITÉ : DÉGRADÉE ($success/$total présents)." "Warning" }
}

# --- 7. MÉTADONNÉES ---
Log "--- ÉTAPE 4 : VÉRIFICATION MÉTADONNÉES ---" "Info"
try {
    # Récupération de la définition des colonnes pour le mapping DisplayName -> InternalName
    Log "Récupération du schéma de la bibliothèque pour mapping..." "Debug"
    $listCols = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/lists/$listId/columns?`$select=displayName,name"
    $colMapping = @{}
    foreach($c in $listCols.value) {
        $colMapping[$c.displayName.ToLower()] = $c.name
    }

    # Résolution supplémentaire via la définition du formulaire enregistrée
    $formMapping = @{}
    if ($trackFound -and $entry.fields.FormDefinitionJson) {
        try {
            $formDef = $entry.fields.FormDefinitionJson | ConvertFrom-Json
            if ($formDef.Layout) {
                foreach ($field in $formDef.Layout) {
                    if ($field.Name -and $field.TargetColumnInternalName) {
                        $formMapping[$field.Name.ToLower()] = $field.TargetColumnInternalName
                    }
                }
            }
        } catch {}
    }

    $rootMeta = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$driveId/items/$targetItemId/listItem?`$expand=fields"
    $fields = $rootMeta.fields
    
    if ($trackFound -and $entry.fields.FormValuesJson) {
        $expected = $entry.fields.FormValuesJson | ConvertFrom-Json
        $match = $true
        foreach ($prop in $expected.PSObject.Properties) {
            $key = $prop.Name
            $val = $prop.Value
            
            # Résolution du nom interne (DisplayName -> InternalName ou via FormMapping)
            $internalKey = $key
            if ($colMapping.ContainsKey($key.ToLower())) { $internalKey = $colMapping[$key.ToLower()] }
            elseif ($formMapping.ContainsKey($key.ToLower())) { $internalKey = $formMapping[$key.ToLower()] }
            
            $spVal = $fields.$internalKey
            
            # Comparaison simplifiée
            $spValStr = if ($spVal -is [array]) { $spVal -join "," } else { [string]$spVal }
            $expectedStr = if ($val -is [array]) { $val -join "," } else { [string]$val }
            
            if ($spValStr -ne $expectedStr -and -not ($key -match "Date")) {
                Log "  [ÉCART] $key (Interne utilisé: $internalKey) : SharePoint='$spValStr' vs Origine='$expectedStr'" "Warning"
                $match = $false
            }
        }
        if ($match) { Log "MÉTADONNÉES : Conformité validée." "Success" }
    }
}
catch {
    Log "Erreur audit métadonnées : $_" "Warning"
}

Log "====================================================" "Info"
Log "   AUDIT TERMINÉ" "Info"
Log "====================================================" "Info"
