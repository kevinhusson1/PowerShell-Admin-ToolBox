function Repair-AppProject {
    <#
    .SYNOPSIS
        Répare les éléments divergents d'un projet SharePoint (Métadonnées et Structure).
    
    .PARAMETER TargetUrl
        URL relative du site ou dossier racine du projet.
    
    .PARAMETER RepairItems
        Liste d'objets @{ Type="Meta"|"Structure"; Key=...; Value=...; Raw=... }
        
    .PARAMETER Connection
        Connexion PnP PowerShell active.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetUrl,

        [Parameter(Mandatory = $true)]
        [array]$RepairItems,

        [Parameter(Mandatory = $true)]
        [PnP.PowerShell.Commands.Base.PnPConnection]$Connection,

        [Parameter(Mandatory = $false)]
        [string]$TemplateJson,

        [Parameter(Mandatory = $false)]
        [string]$FormValuesJson,

        [Parameter(Mandatory = $false)]
        [string]$FormDefinitionJson,

        [Parameter(Mandatory = $false)]
        [string]$ClientId,

        [Parameter(Mandatory = $false)]
        [string]$Thumbprint,

        [Parameter(Mandatory = $false)]
        [string]$TenantName
    )

    $LogsList = [System.Collections.Generic.List[string]]::new()
    $Errors = @()

    $TargetUrl = [uri]::UnescapeDataString($TargetUrl)

    $ProjectModelName = ""
    $RootMetadataHash = @{}

    if (-not [string]::IsNullOrWhiteSpace($FormValuesJson)) {
        try {
            $fv = $FormValuesJson | ConvertFrom-Json
            if ($fv.PreviewText) { $ProjectModelName = $fv.PreviewText }

            if (-not [string]::IsNullOrWhiteSpace($FormDefinitionJson)) {
                $fd = $FormDefinitionJson | ConvertFrom-Json
                foreach ($field in $fd.Layout) {
                    if ($field.IsMetadata -and $null -ne $fv."$($field.Name)" -and $fv."$($field.Name)" -ne "") {
                        $RootMetadataHash[$field.Name] = $fv."$($field.Name)"
                    }
                }
            }
        }
        catch {}
    }

    function Log { 
        param($m, $l = "Info") 
        $LogsList.Add("AppLog: [$l] $m")
        # On utilise Write-Output avec un préfixe pour le flux standard (Receive-Job)
        Write-Output "[LOG] AppLog: [$l] $m"
        Write-Verbose "[$l] $m" 
    }

    try {
        Log "Début de la réparation sur : $TargetUrl"
        
        # Pré-chargement des listes pour correspondre aux URLs (Evite l'erreur System.Object[])
        $allLists = Get-PnPList -Connection $Connection -Includes RootFolder.ServerRelativeUrl, Title
        
        # 1. Repair Metadata
        $metaItems = $RepairItems | Where-Object { $_.Type -eq "Meta" }
        if ($metaItems) {
            Log "Correction de $($metaItems.Count) métadonnées..."
            $hash = @{}
            foreach ($m in $metaItems) {
                # Cas spécial "Nom du Dossier (PreviewText)"
                if ($m.Key -eq "Nom du Dossier (PreviewText)" -or $m.Key -eq "PreviewText") {
                    Log " > ACTION REQUISE : Le renommage physique du répertoire (-> $($m.Value)) doit être efféctué via le bouton 'Renommer' de l'interface pour garantir la mise à jour complète de l'identité du projet." "Warning"
                }
                else {
                    $valSet = $m.Value
                    if ($valSet -match " \| ") { $valSet = $valSet -split " \| " }
                    $hash[$m.Key] = $valSet
                    Log " > Set $($m.Key) = '$($m.Value)'"
                }
            }
            
            # Apply to Folder
            try {
                $list = $allLists | Where-Object { $TargetUrl.StartsWith($_.RootFolder.ServerRelativeUrl, [System.StringComparison]::InvariantCultureIgnoreCase) } | Sort-Object { $_.RootFolder.ServerRelativeUrl.Length } -Descending | Select-Object -First 1

                $folder = Get-PnPFolder -Url $TargetUrl -Connection $Connection -Includes ListItemAllFields -ErrorAction Stop
                $listItem = $folder.ListItemAllFields

                if ($listItem -and $listItem.Id -and $list) {
                    if ($hash.Count -gt 0) {
                        Set-AppSPMetadata -List $list.Title -ItemId $listItem.Id -Values $hash -Connection $Connection
                        Log "Métadonnées racine appliquées avec succès." "Success"
                    }
                    else {
                        Log "Aucune métadonnée applicable en masse requise sur la racine." "Info"
                    }
                }
                else {
                    Log "Impossible de récupérer le ListItem du dossier ou la liste parente." "Error"
                }
            }
            catch {
                Log "Erreur lors de la mise à jour des métadonnées : $($_.Exception.Message)" "Error"
            }
        }

        # 2. Repair Structure
        $structItems = $RepairItems | Where-Object { $_.Type -eq "Structure" }
        if ($structItems) {
            Log "Correction de $($structItems.Count) éléments de structure..."
            
            $baseObj = $null
            if (-not [string]::IsNullOrWhiteSpace($TemplateJson)) {
                $baseObj = $TemplateJson | ConvertFrom-Json
            }

            function Find-StructureNode {
                param($NodeList, $TargetName, $TargetType, $CurrentPath)
                if (-not $NodeList) { return $null }
                $list = if ($NodeList -is [System.Array]) { $NodeList } else { @($NodeList) }
                foreach ($n in $list) {
                    $nType = if ($n.Type) { $n.Type } else { "Folder" }

                    if (($n.Name -eq $TargetName -or "$($n.Name).url" -eq $TargetName -or "$($n.Name).docx" -eq $TargetName) -and $nType -eq $TargetType) { 
                        return @{ Node = $n; ParentPath = $CurrentPath }
                    }
                    if ($nType -ne "Link" -and $nType -ne "InternalLink" -and $nType -ne "Publication" -and $nType -ne "File" -and $n.Name) {
                        if ($n.Folders) {
                            $found = Find-StructureNode -NodeList $n.Folders -TargetName $TargetName -TargetType $TargetType -CurrentPath "$CurrentPath/$($n.Name)"
                            if ($found) { return $found }
                        }
                    }
                    else {
                        if ($n.Folders) {
                            $found = Find-StructureNode -NodeList $n.Folders -TargetName $TargetName -TargetType $TargetType -CurrentPath $CurrentPath
                            if ($found) { return $found }
                        }
                    }
                }
                return $null
            }

            foreach ($s in $structItems) {
                $txt = $s.Raw
                
                if ($txt -match "Manquant : '(.+?)' \((Dossier|Link|InternalLink|Publication Raccourci Local|File)\)" -or
                    $txt -match "Le dossier de destination du lien de publication '(.+?)' n'existe plus.*?" -or
                    $txt -match "La destination du lien interne '(.+?)'") {
                    
                    $itemName = ""
                    $mappedType = ""

                    if ($txt -match "Manquant : '(.+?)' \((Dossier|Link|InternalLink|Publication Raccourci Local|File)\)") {
                        $itemName = $Matches[1]
                        $itemTypeStr = $Matches[2]
                        
                        # Convert Display Type to JSON Node Type
                        $mappedType = "Folder"
                        if ($itemTypeStr -eq "Link") { $mappedType = "Link" }
                        if ($itemTypeStr -eq "InternalLink") { $mappedType = "InternalLink" }
                        if ($itemTypeStr -eq "Publication Raccourci Local") { $mappedType = "Publication" }
                        if ($itemTypeStr -eq "File") { $mappedType = "File" }
                    }
                    elseif ($txt -match "Le dossier de destination du lien de publication '(.+?)' n'existe plus.*?") {
                        $itemName = $Matches[1]
                        $mappedType = "Publication"
                    }
                    elseif ($txt -match "La destination du lien interne '(.+?)'") {
                        $itemName = $Matches[1]
                        $mappedType = "InternalLink"
                    }

                    Log " > Restauration complète requise pour : $itemName ($mappedType)"
                    if (-not $baseObj) {
                        Log "   Echec : TemplateJson non fourni. Impossible de recréer l'élément manquant." "Error"
                        continue
                    }

                    $resNode = Find-StructureNode -NodeList $baseObj.Folders -TargetName $itemName -TargetType $mappedType -CurrentPath $TargetUrl
                    if (-not $resNode) {
                        if ($baseObj.Name -eq $itemName) {
                            $resNode = @{ Node = $baseObj; ParentPath = $TargetUrl.Substring(0, $TargetUrl.LastIndexOf('/')) }
                        }
                        if (-not $resNode) {
                            Log "   Echec : Noeud '$itemName' introuvable dans le TemplateJson." "Error"
                            continue
                        }
                    }

                    try {
                        $list = $allLists | Where-Object { $resNode.ParentPath.StartsWith($_.RootFolder.ServerRelativeUrl, [System.StringComparison]::InvariantCultureIgnoreCase) } | Sort-Object { $_.RootFolder.ServerRelativeUrl.Length } -Descending | Select-Object -First 1
                        
                        $nodeWrap = @{ Folders = @($resNode.Node) }
                        $nodeJsonStr = $nodeWrap | ConvertTo-Json -Depth 10 -Compress
                        
                        $formHash = $null
                        if (-not [string]::IsNullOrWhiteSpace($FormValuesJson)) { $formHash = $FormValuesJson | ConvertFrom-Json -AsHashtable }

                        $deployArgs = @{
                            TargetSiteUrl      = $Connection.Url
                            TargetLibraryName  = $list.Title
                            TargetFolderUrl    = $resNode.ParentPath
                            StructureJson      = $nodeJsonStr
                            ClientId           = $ClientId
                            Thumbprint         = $Thumbprint
                            TenantName         = $TenantName
                            FormValues         = $formHash
                            IdMapReferenceJson = $TemplateJson
                            ProjectModelName   = $ProjectModelName
                            ProjectRootUrl     = $TargetUrl
                            RootMetadata       = $RootMetadataHash
                        }

                        Log "   Lancement du Moteur de Délégation sur cible : $($resNode.ParentPath)..." "Info"
                        $resDeploy = New-AppSPStructure @deployArgs

                        if ($resDeploy.Success) {
                            Log "   Appliqué avec succès (Restauration récursive)." "Success"
                        }
                        else {
                            $errStr = $resDeploy.Errors -join " | "
                            Log "   Echec restauration : $errStr" "Error"
                        }
                    }
                    catch {
                        Log "   Echec delegation Moteur : $($_.Exception.Message)" "Error"
                    }
                }
                elseif ($txt -match "Métadonnée '(.+?)' incorrecte sur '(.+?)' : attendu '(.+?)' vs réel '.*?'" -or $txt -match "Métadonnées inaccessibles sur '(.+?)' \(Attendu '(.+?)': '(.+?)'\)") {
                    
                    $keyName = ""
                    $itemName = ""
                    $expectedValue = ""

                    if ($txt -match "Métadonnées inaccessibles sur '(.+?)' \(Attendu '(.+?)': '(.+?)'\)") {
                        $itemName = $Matches[1]
                        $keyName = $Matches[2]
                        $expectedValue = $Matches[3]
                    }
                    elseif ($txt -match "Métadonnée '(.+?)' incorrecte sur '(.+?)' : attendu '(.+?)' vs réel '.*?'") {
                        $keyName = $Matches[1]
                        $itemName = $Matches[2]
                        $expectedValue = $Matches[3]
                    }
                    
                    # Détection d'un tableau à valeurs multiples ("Valeur1 | Valeur2")
                    $actualValueToSet = $expectedValue
                    if ($expectedValue -match " \| ") {
                        $actualValueToSet = $expectedValue -split " \| "
                    }
                    
                    $newPath = "$TargetUrl/$itemName"
                    Log " > Correction métadonnée $keyName = '$expectedValue' sur : $newPath"
                    try {
                        $list = $allLists | Where-Object { $newPath.StartsWith($_.RootFolder.ServerRelativeUrl, [System.StringComparison]::InvariantCultureIgnoreCase) } | Sort-Object { $_.RootFolder.ServerRelativeUrl.Length } -Descending | Select-Object -First 1

                        if (-not $list) { throw "Impossible de déterminer la bibliothèque." }

                        $listItem = $null
                        try {
                            $f = Get-PnPFolder -Url $newPath -Connection $Connection -Includes ListItemAllFields -ErrorAction Stop
                            $listItem = $f.ListItemAllFields
                        }
                        catch {
                            # Fallback : Recherche via requête list PnP robuste (contourne les erreurs Get-File sur les .url)
                            $safeName1 = $itemName.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;")
                            $safeName2 = "$safeName1.url"
                            
                            $caml = "<View Scope='RecursiveAll'><Query><Where><Or><Eq><FieldRef Name='FileLeafRef'/><Value Type='Text'>$safeName1</Value></Eq><Eq><FieldRef Name='FileLeafRef'/><Value Type='Text'>$safeName2</Value></Eq></Or></Where></Query></View>"
                            
                            $items = Get-PnPListItem -List $list.Title -Query $caml -Connection $Connection -ErrorAction SilentlyContinue
                            
                            if ($items) {
                                # S'il y a plusieurs éléments du même nom dans la liste, on filtre sur celui du bon projet
                                $listItem = $items | Where-Object { 
                                    ($_["FileRef"] -as [string]).StartsWith($TargetUrl, [System.StringComparison]::InvariantCultureIgnoreCase) 
                                } | Select-Object -First 1
                            }
                        }

                        if ($listItem -and $listItem.Id) {
                            Set-AppSPMetadata -List $list.Title -ItemId $listItem.Id -Values @{ $keyName = $actualValueToSet } -Connection $Connection
                            Log "   Appliqué avec succès." "Success"
                        }
                        else {
                            Log "   Impossible de récupérer le ListItem de l'élément. La requête n'a trouvé aucun identifiant valide." "Error"
                        }
                    }
                    catch {
                        Log "   Echec correction métadonnée : $($_.Exception.Message)" "Error"
                    }
                }
                elseif ($txt -match "Cible distante de la publication '(.+?)' a un _AppDeploymentId incorrect \(Attendu '(.+?)', trouvé '.*?'\) à (.+)") {
                    $pubName = $Matches[1]
                    $expectedId = $Matches[2]
                    $targetPath = $Matches[3]
                    Log " > Cible distante ($pubName) ID incorrect (Attendu: $expectedId) : $targetPath. (Une relance complète du déploiement depuis le Dashboard principal est recommandée pour corriger les ID distant)." "Warning"
                }
                else {
                    Log " > Type de réparation inconnu pour : $txt" "Warning"
                }
            }
        }

    }
    catch {
        $Errors += $_.Exception.Message
        Log "Erreur globale réparation : $($_.Exception.Message)" "Error"
    }

    return [PSCustomObject]@{
        Success = ($Errors.Count -eq 0)
        Logs    = $LogsList.ToArray()
        Errors  = $Errors
    }
}
