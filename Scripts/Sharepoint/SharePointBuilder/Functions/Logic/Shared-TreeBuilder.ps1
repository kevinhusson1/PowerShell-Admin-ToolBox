<#
.SYNOPSIS
    Génère un TreeViewItem complet à partir d'un objet de données (JSON deserialisé), partagé entre l'Éditeur et le Déploiement.

.DESCRIPTION
    Cette fonction est le MOTEUR UNIFIÉ de rendu de l'arbre. Elle est utilisée pour :
    1. Charger un modèle JSON dans l'Éditeur (Mode Édition).
    2. Afficher la prévisualisation avant déploiement (Mode Visualisation).

    Fonctionnalités :
    - Distinction automatique des types de nœuds (Dossier, Lien, Publication, Lien Interne).
    - Remplacement de variables (ex: {ProjectCode}) si un dictionnaire 'Replacements' est fourni.
    - Hydratation récursive des enfants (Sous-dossiers).
    - Création visuelle des Permissions et Tags enfants.
    - Mise à jour automatique des Badges (Macarons) via Update-EditorBadges.

.PARAMETER NodeData
    L'objet de données (PSCustomObject) provenant du JSON. Doit contenir 'Name', et optionnellement 'Type', 'Url', 'Children', etc.

.PARAMETER Replacements
    [Optionnel] Hashtable des valeurs pour remplacer les variables dans les Noms et URLs.
    Ex: @{ "ProjectCode" = "1234" } remplacera "{ProjectCode}" par "1234".

.OUTPUTS
    [System.Windows.Controls.TreeViewItem] L'élément graphique prêt à être ajouté à l'arbre.
    Retourne $null si les données sont invalides.
#>
function Global:New-BuilderTreeItem {
    param(
        [psobject]$NodeData,
        [hashtable]$Replacements = $null
    )

    if (-not $NodeData) { return $null }

    # 1. Résolution des noms (Variable Replacement)
    # Si $Replacements est fourni, on applique. Sinon on garde le nom brut.
    $finalName = $NodeData.Name
    $finalUrl = $NodeData.Url
    
    if ($Replacements) {
        foreach ($key in $Replacements.Keys) {
            if ($finalName -match "\{$key\}") { 
                $finalName = $finalName -replace "\{$key\}", $Replacements[$key] 
            }
            if ($finalUrl -match "\{$key\}") { 
                $finalUrl = $finalUrl -replace "\{$key\}", $Replacements[$key] 
            }
        }
    }

    $item = $null

    # 2. Création du Noeud selon Type
    if ($NodeData.Type -eq "Link") {
        $item = New-EditorLinkNode -Name $finalName -Url $finalUrl
    }
    elseif ($NodeData.Type -eq "Publication") {
        $item = New-EditorPubNode -Name $finalName
        # Hydratation Props Publication
        $item.Tag.TargetSiteMode = $NodeData.TargetSiteMode
        $item.Tag.TargetSiteUrl = $NodeData.TargetSiteUrl
        $item.Tag.TargetFolderPath = $NodeData.TargetFolderPath
        $item.Tag.UseModelName = $NodeData.UseModelName
        $item.Tag.UseFormMetadata = if ($NodeData.UseFormMetadata) { $NodeData.UseFormMetadata } else { $false }
        $item.Tag.GrantUser = $NodeData.GrantUser
        $item.Tag.GrantLevel = $NodeData.GrantLevel
        
        # Initial Visual Update for Metadata
        if ($item.Tag.UseFormMetadata) {
            if ($item.Header -is [System.Windows.Controls.StackPanel] -and $item.Header.Children.Count -ge 2) { 
                $txt = $item.Header.Children[1]
                $txt.Text += " [META]"
                $txt.Foreground = [System.Windows.Media.Brushes]::Teal
            }
        }
    }
    elseif ($NodeData.Type -eq "InternalLink") {
        $item = New-EditorInternalLinkNode -Name $finalName -TargetNodeId $NodeData.TargetNodeId
    }
    elseif ($NodeData.Type -eq "File") {
        $finalSourceUrl = if ($NodeData.SourceUrl) { $NodeData.SourceUrl } else { "" }
        if ($Replacements) {
            foreach ($key in $Replacements.Keys) {
                if ($finalSourceUrl -match "\{$key\}") { 
                    $finalSourceUrl = $finalSourceUrl -replace "\{$key\}", $Replacements[$key] 
                }
            }
        }
        $item = New-EditorFileNode -Name $finalName -SourceUrl $finalSourceUrl
    }
    else {
        # Default: Folder
        $item = New-EditorNode -Name $finalName
        if ($NodeData.Id) { $item.Tag.Id = $NodeData.Id }
    }

    # 3. Hydratation Enfants Communs (Permissions, Tags)
    
    # Permissions
    if ($NodeData.Permissions) {
        # Si le Tag.Permissions existe (Folder), on le vide d'abord pour éviter doublons data vs visuel
        if ($null -ne $item.Tag.Permissions) { $item.Tag.Permissions.Clear() }
        
        foreach ($p in $NodeData.Permissions) {
            $email = if ($p.Email) { $p.Email } elseif ($p.User) { $p.User } else { $p.Identity }
            
            # Ajout Data (si supporté par le Tag du noeud)
            if ($null -ne $item.Tag.Permissions) {
                $item.Tag.Permissions.Add([PSCustomObject]@{ Email = $email; Level = $p.Level }) 
            }
            
            # Ajout Visuel
            $pNode = New-EditorPermNode -Email $email -Level $p.Level
            $item.Items.Add($pNode) | Out-Null
        }
    }

    # Tags
    if ($NodeData.Tags) {
        if ($null -ne $item.Tag.Tags) { $item.Tag.Tags.Clear() }
        
        foreach ($t in $NodeData.Tags) {
            $n = if ($t.Name) { $t.Name } else { $t.Column }
            $v = if ($t.Value) { $t.Value } else { $t.Term }

            # Ajout Data
            if ($null -ne $item.Tag.Tags) {
                # Attention : Pour Links/Pubs/InternalLinks, .Tags est une List[psobject] initialisée par New-Editor*Node
                $item.Tag.Tags.Add([PSCustomObject]@{ Name = $n; Value = $v }) 
            }

            # Ajout Visuel
            $tNode = New-EditorTagNode -Name $n -Value $v -IsDynamic ($t.IsDynamic -eq $true)
            
            # Hydration Dynamic Props
            if ($t.IsDynamic) {
                $tNode.Tag.IsDynamic = $true
                $tNode.Tag.SourceForm = $t.SourceForm
                $tNode.Tag.SourceVar = $t.SourceVar
                
                # Visual text is now handled by New-EditorTagNode
            }
            
            $item.Items.Add($tNode) | Out-Null
        }
    }

    # 4. Récursion (Folders/Children)
    if ($NodeData.Folders) {
        foreach ($subNode in $NodeData.Folders) {
            $subItem = New-BuilderTreeItem -NodeData $subNode -Replacements $Replacements
            if ($subItem) {
                $item.Items.Add($subItem) | Out-Null
            }
        }
    }

    # 5. Mise à jour des Badges (CRITIQUE pour l'affichage unifié)
    Update-EditorBadges -TreeItem $item

    return $item
}
