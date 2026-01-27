# Scripts/SharePoint/SharePointBuilder/Functions/Logic/Update-TreePreview.ps1

<#
.SYNOPSIS
    Génère une prévisualisation en lecture seule de la structure de dossiers.

.DESCRIPTION
    Utilisé dans l'onglet principal pour montrer à l'utilisateur ce qui sera déployé.
    Remplace dynamiquement les variables (ex: {ProjectCode}) par les valeurs saisies dans le formulaire.
    Affiche également les badges de permissions/tags/liens.

.PARAMETER TreeView
    Le TreeView de prévisualisation (lecture seule).

.PARAMETER JsonStructure
    Le JSON du template sélectionné.

.PARAMETER FormPanel
    Le panneau contenant les contrôles du formulaire dynamique (pour récupérer les valeurs).
#>
function Global:Update-TreePreview {
    param(
        [System.Windows.Controls.TreeView]$TreeView,
        [string]$JsonStructure,
        [System.Windows.Controls.Panel]$FormPanel
    )

    if (-not $TreeView) { return }
    $TreeView.Items.Clear()

    if ([string]::IsNullOrWhiteSpace($JsonStructure)) { return }

    try {
        # 1. Récupération des valeurs du formulaire
        $replacements = @{}
        if ($FormPanel) {
            foreach ($ctrl in $FormPanel.Children) {
                $val = ""
                if ($ctrl -is [System.Windows.Controls.TextBox]) { $val = $ctrl.Text }
                elseif ($ctrl -is [System.Windows.Controls.ComboBox]) { $val = $ctrl.SelectedItem }
                
                if ($ctrl.Name -like "Input_*") {
                    $key = $ctrl.Name.Replace("Input_", "")
                    $replacements[$key] = $val
                }
            }
        }

        # 2. Parsing du JSON (Sécurisé)
        $structure = $JsonStructure | ConvertFrom-Json
        
        # Gestion intelligente : soit c'est un tableau de dossiers à la racine, soit un objet Root avec Folders
        $rootList = @()
        if ($structure.Folders) {
            $rootList = $structure.Folders
        }
        elseif ($structure.Root) {
            $rootList = @($structure.Root)
        }
        else {
            # Cas où le JSON est directement un tableau
            $rootList = $structure
        }

        # 3. Fonction récursive unifiée (Utilise les composants de l'Éditeur)
        function New-VisuItem {
            param($Node)

            # A. Résolution du Nom (Remplacement Variables)
            $rawName = if ($Node.Name) { [string]$Node.Name } else { "Dossier sans nom" }
            $finalName = $rawName
            foreach ($key in $replacements.Keys) {
                if ($finalName -match "\{$key\}") {
                    $finalName = $finalName -replace "\{$key\}", $replacements[$key]
                }
            }

            # B. Distinction TYPE (Lien vs Publication vs Dossier)
            if ($Node.Type -eq "Link") {
                # --- NOEUD LIEN ---
                $rawUrl = if ($Node.Url) { $Node.Url } else { "" }
                $finalUrl = $rawUrl
                foreach ($key in $replacements.Keys) {
                    if ($finalUrl -match "\{$key\}") {
                        $finalUrl = $finalUrl -replace "\{$key\}", $replacements[$key]
                    }
                }
                $item = New-EditorLinkNode -Name $finalName -Url $finalUrl
                return $item
            }
            elseif ($Node.Type -eq "Publication") {
                # --- NOEUD PUBLICATION ---
                
                # Note: On peut aussi vouloir remplacer des vars dans TargetFolderPath
                $item = New-EditorPubNode -Name $finalName
                
                # Hydratation simple pour la visualisation (Le Tag est utilisé par Update-EditorBadges sur le parent si nécessaire ?)
                # En fait Update-EditorBadges regarde le Type dans le Tag de l'enfant. Donc il faut bien setter le Type.
                $item.Tag.Type = "Publication"
                $item.Tag.TargetSiteMode = $Node.TargetSiteMode
                $item.Tag.TargetSiteUrl = $Node.TargetSiteUrl
                $item.Tag.TargetFolderPath = $Node.TargetFolderPath
                $item.Tag.UseModelName = $Node.UseModelName
                $item.Tag.GrantUser = $Node.GrantUser
                $item.Tag.GrantLevel = $Node.GrantLevel
                
                return $item
            }
            elseif ($Node.Type -eq "InternalLink") {
                # --- NOEUD LIEN INTERNE ---
                $item = New-EditorInternalLinkNode -Name $finalName -TargetNodeId $Node.TargetNodeId
                return $item
            }
            else {
                # --- NOEUD DOSSIER ---
                $item = New-EditorNode -Name $finalName
                
                # Hydratation (comme dans Convert-JsonToEditorTree)
                
                # Permissions
                if ($Node.Permissions) {
                    if ($null -eq $item.Tag.Permissions) { $item.Tag.Permissions = [System.Collections.Generic.List[psobject]]::new() }
                    foreach ($p in $Node.Permissions) { 
                        # Support legacy fields if needed
                        $email = if ($p.Email) { $p.Email } elseif ($p.User) { $p.User } else { $p.Identity }
                        $item.Tag.Permissions.Add([PSCustomObject]@{ Email = $email; Level = $p.Level }) 
                    }
                }
                
                # Tags
                if ($Node.Tags) {
                    if ($null -eq $item.Tag.Tags) { $item.Tag.Tags = [System.Collections.Generic.List[psobject]]::new() }
                    foreach ($t in $Node.Tags) { 
                        $n = if ($t.Name) { $t.Name } else { $t.Column }
                        $v = if ($t.Value) { $t.Value } else { $t.Term }
                        $item.Tag.Tags.Add([PSCustomObject]@{ Name = $n; Value = $v }) 
                    }
                }

                # Récursion Enfants (AVANT Update-EditorBadges pour que le compteur Public fonctionne)
                if ($Node.Folders) {
                    foreach ($subNode in $Node.Folders) {
                        $subItem = New-VisuItem -Node $subNode
                        $item.Items.Add($subItem) | Out-Null
                    }
                }

                # Mise à jour Badges & Metadonnées
                Update-EditorBadges -TreeItem $item
                
                return $item
            }
        }

        # 4. Boucle principale
        foreach ($rootNode in $rootList) {
            $tvItem = New-VisuItem -Node $rootNode
            $TreeView.Items.Add($tvItem)
        }

    }
    catch {
        Write-Verbose "Erreur Preview TreeView : $_"
    }
}