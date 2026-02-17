<#
.SYNOPSIS
    Gère la sélection du dossier cible via un TreeView Inline (Modernisé).

.DESCRIPTION
    Remplace l'ancien système de popup modale.
    - Le bouton "Sélectionner..." connecte au Site et charge la racine de la Bibliothèque.
    - Le TreeView permet la navigation (Lazy Loading).
    - La sélection met à jour le champ texte et les métadonnées.
#>
function Register-RenamerPickerEvents {
    param(
        [hashtable]$Ctrl,
        [System.Windows.Window]$Window
    )
    
    # --- 0. Helper: PopulateNodeSync (Portage de SharePointBuilder) ---
    $PopulateNodeSync = {
        param($ParentNode, $FolderRelativeUrl, $Conn)
        
        $overlay = $Window.FindName("ExplorerLoadingOverlay")
        if ($overlay) { 
            $overlay.Visibility = "Visible" 
            [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([Action] {}, [System.Windows.Threading.DispatcherPriority]::Render)
        }

        try {
            # Dummy Removal (si existe)
            if ($ParentNode.Items.Count -eq 1 -and $ParentNode.Items[0].Tag -eq "DUMMY_TAG") {
                $ParentNode.Items.Clear()
            }

            $subFolders = @()
            try {
                # Utilisation de PnP pour la rapidité
                $pFolder = Get-PnPFolder -Url $FolderRelativeUrl -Connection $Conn -Includes Folders -ErrorAction Stop
                $subFolders = $pFolder.Folders | Where-Object { -not $_.Name.StartsWith("_") -and $_.Name -ne "Forms" }
            }
            catch {
                $err = $_.Exception.Message
                [System.Windows.MessageBox]::Show("Erreur lecture dossier : $err", "Erreur", "OK", "Warning")
            }

            foreach ($sub in $subFolders) {
                # Création Item Style "Modern"
                $newItem = New-Object System.Windows.Controls.TreeViewItem
                $newItem.SetResourceReference([System.Windows.Controls.TreeViewItem]::StyleProperty, "ModernTreeViewItemStyle")
                
                # Header avec Icône
                $stack = New-Object System.Windows.Controls.StackPanel
                $stack.Orientation = "Horizontal"
                
                $txtIcon = New-Object System.Windows.Controls.TextBlock; $txtIcon.Text = "📁"
                $txtIcon.SetResourceReference([System.Windows.Controls.TextBlock]::StyleProperty, "TreeItemIconStyle") 
                
                $txt = New-Object System.Windows.Controls.TextBlock; $txt.Text = $sub.Name
                
                $stack.Children.Add($txtIcon)
                $stack.Children.Add($txt)
                
                $newItem.Header = $stack
                
                # Tag Data (Keep it simple)
                $newItem.Tag = [PSCustomObject]@{
                    Name              = $sub.Name
                    ServerRelativeUrl = $sub.ServerRelativeUrl
                }
                
                # Dummy pour Lazy Load
                $dummy = New-Object System.Windows.Controls.TreeViewItem
                $dummy.Header = "Chargement..."
                $dummy.FontStyle = "Italic"
                $dummy.Tag = "DUMMY_TAG"
                $newItem.Items.Add($dummy)
                
                $ParentNode.Items.Add($newItem)
            }
        }
        catch {
            [System.Windows.MessageBox]::Show("Erreur critique TreeView : $($_.Exception.Message)")
        }
        finally {
            if ($overlay) { $overlay.Visibility = "Collapsed" }
        }
    }
    
    # Référence pour Closure
    $RefPopulate = $PopulateNodeSync

    # --- 1. Bouton "Sélectionner / Explorer" ---
    $Ctrl.BtnPickFolder.Add_Click({
            $listBox = $Ctrl.ListBox
            if (-not $listBox) { $listBox = $Window.FindName("ConfigListBox") }
            
            $cfg = $null
            if ($listBox) { $cfg = $listBox.SelectedItem }
            
            if (-not $cfg) { 
                [System.Windows.MessageBox]::Show("Veuillez d'abord sélectionner un Modèle de configuration.")
                return 
            }
            
            # UI setup
            $tvBorder = $Window.FindName("TargetExplorerBorder")
            $tv = $Window.FindName("TargetExplorerTreeView")
            if ($tvBorder -and $tvBorder.Visibility -eq "Visible") {
                # Toggle OFF ? Non, refresh plutôt ou juste focus.
                # Disons qu'on reload pour l'instant si on reclique
            }

            if ($tvBorder) { $tvBorder.Visibility = "Visible" }
            if ($tv) { 
                $tv.Items.Clear() 
                $rootPlaceholder = New-Object System.Windows.Controls.TreeViewItem
                $rootPlaceholder.Header = "Connexion au site en cours..."
                $tv.Items.Add($rootPlaceholder)
            }

            # Async Connect & Load Root
            $overlay = $Window.FindName("ExplorerLoadingOverlay")
            if ($overlay) { 
                $overlay.Visibility = "Visible" 
                [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([Action] {}, [System.Windows.Threading.DispatcherPriority]::Render)
            }

            try {
                # Paramètres Connexion
                $clientId = $Global:AppConfig.azure.authentication.userAuth.appId
                $thumb = $Global:AppConfig.azure.certThumbprint
                $tenant = $Global:AppConfig.azure.tenantName
                $siteUrl = $cfg.SiteUrl
                
                # Check cache connection
                if ($Global:RenamerExplorerConn -and $Global:RenamerExplorerConn.Url -eq $siteUrl) {
                    # Reuse
                }
                else {
                    $Global:RenamerExplorerConn = Connect-AppSharePoint -ClientId $clientId -Thumbprint $thumb -TenantName $tenant -SiteUrl $siteUrl
                }

                if ($Global:RenamerExplorerConn) {
                    # Get Library Root
                    try {
                        $lib = Get-PnPList -Identity $cfg.LibraryName -Connection $Global:RenamerExplorerConn -ErrorAction Stop
                        
                        if ($tv) {
                            $tv.Items.Clear()
                            $rootItem = New-Object System.Windows.Controls.TreeViewItem
                            $rootItem.SetResourceReference([System.Windows.Controls.TreeViewItem]::StyleProperty, "ModernTreeViewItemStyle")
                            $rootItem.Header = $lib.Title + " (Racine)"
                            $rootItem.Tag = [PSCustomObject]@{
                                Name              = "Racine"
                                ServerRelativeUrl = $lib.RootFolder.ServerRelativeUrl
                            }
                            $rootItem.IsExpanded = $true
                            $tv.Items.Add($rootItem)

                            # Populate Root
                            & $RefPopulate -ParentNode $rootItem -FolderRelativeUrl $lib.RootFolder.ServerRelativeUrl -Conn $Global:RenamerExplorerConn
                        }
                    }
                    catch {
                        [System.Windows.MessageBox]::Show("Bibliothèque '$($cfg.LibraryName)' introuvable : $($_.Exception.Message)")
                    }
                }
            }
            catch {
                [System.Windows.MessageBox]::Show("Echec Connexion : $($_.Exception.Message)")
            }
            finally {
                if ($overlay) { $overlay.Visibility = "Collapsed" }
            }

        }.GetNewClosure())


    # --- 2. Event Expand (Lazy Load) ---
    $exTV = $Window.FindName("TargetExplorerTreeView")
    if ($exTV) {
        $ActionExpandSync = {
            param($sender, $e)
            $item = $e.OriginalSource 
            
            if ($item -is [System.Windows.Controls.TreeViewItem]) {
                if ($item.Items.Count -eq 1) {
                    $firstChild = $item.Items[0]
                    if ($firstChild.Tag -eq "DUMMY_TAG") { 
                        $folderData = $item.Tag
                        if ($folderData -and $Global:RenamerExplorerConn) {
                            & $RefPopulate -ParentNode $item -FolderRelativeUrl $folderData.ServerRelativeUrl -Conn $Global:RenamerExplorerConn
                        }
                    }
                }
            }
        }.GetNewClosure()

        try { $exTV.AddHandler([System.Windows.Controls.TreeViewItem]::ExpandedEvent, [System.Windows.RoutedEventHandler]$ActionExpandSync) } catch {}
    
        # --- 3. Selection Changed (Update Logic) ---
        $exTV.Add_SelectedItemChanged({
                param($sender, $e)
                $item = $sender.SelectedItem
            
                if ($item -and $item.Tag.ServerRelativeUrl) {
                    $folderData = $item.Tag
                
                    # --- FETCH FULL OBJECT (Critical for Form Hydration) ---
                    $Window.Cursor = [System.Windows.Input.Cursors]::Wait
                    try {
                        # On doit récupérer l'objet complet pour que Register-RenamerFormEvents puisse lire .ListItemAllFields
                        # Note: Get-PnPFolder -Includes ListItemAllFields est nécessaire
                    
                        $realFolder = Get-PnPFolder -Url $folderData.ServerRelativeUrl -Connection $Global:RenamerExplorerConn -Includes ListItemAllFields, Name, ServerRelativeUrl
                    
                        # Update Tag with FULL Object
                        if ($Ctrl.TargetFolderBox) { 
                            $Ctrl.TargetFolderBox.Text = $realFolder.Name
                            $Ctrl.TargetFolderBox.Tag = $realFolder # Now contains ListItemAllFields
                        }

                        # --- METADATA DISPLAY ---
                        $itemVals = $realFolder.ListItemAllFields
                        $metaTxt = "Métadonnées actuelles :`n"
                    
                        if ($itemVals -and $itemVals.FieldValues) {
                            # Whitelist Calculation
                            $lBox = $Window.FindName("ConfigListBox")
                            $cfg = if ($lBox) { $lBox.SelectedItem } else { $null }
                        
                            $whitelist = @("Title", "FileLeafRef", "FileRef", "Created", "Modified", "Editor", "Author") 
                            if ($cfg -and $cfg.TargetFolder) {
                                $rules = Get-AppNamingRules
                                $targetRule = $rules | Where-Object { $_.RuleId -eq $cfg.TargetFolder } | Select-Object -First 1
                                if ($targetRule) {
                                    try {
                                        $layout = ($targetRule.DefinitionJson | ConvertFrom-Json).Layout
                                        foreach ($elem in $layout) { if ($elem.Name) { $whitelist += $elem.Name } }
                                    }
                                    catch {}
                                }
                            }

                            foreach ($k in $itemVals.FieldValues.Keys) {
                                if ($whitelist -contains $k) {
                                    $val = $itemVals.FieldValues[$k]
                                
                                    # Lookup Resolution
                                    if ($val -is [Microsoft.SharePoint.Client.FieldLookupValue]) { $val = $val.LookupValue }
                                    elseif ($val -is [Array] -and $val[0] -is [Microsoft.SharePoint.Client.FieldLookupValue]) { 
                                        $val = ($val | ForEach-Object { $_.LookupValue }) -join "; " 
                                    }
                                    elseif ($val -is [Microsoft.SharePoint.Client.FieldUserValue]) { $val = $val.LookupValue }
                                
                                    $metaTxt += "- $k : $val`n"
                                }
                            }
                        }
                        if ($Ctrl.CurrentMetaText) { $Ctrl.CurrentMetaText.Text = $metaTxt }

                    }
                    catch {
                        if ($Ctrl.CurrentMetaText) { $Ctrl.CurrentMetaText.Text = "Erreur lecture métadonnées : $($_.Exception.Message)" }
                        # Fallback to lightweight tag if fetch fails, to avoid null pointer
                        if ($Ctrl.TargetFolderBox) { $Ctrl.TargetFolderBox.Tag = $folderData }
                    }
                    finally {
                        $Window.Cursor = [System.Windows.Input.Cursors]::Arrow
                    }

                    # Trigger Form Update
                    if ($Global:UpdateRenamerForm) { & $Global:UpdateRenamerForm }
                }
            }.GetNewClosure())
    }
}
