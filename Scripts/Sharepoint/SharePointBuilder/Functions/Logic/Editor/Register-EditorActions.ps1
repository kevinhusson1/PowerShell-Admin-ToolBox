# Scripts/SharePoint/SharePointBuilder/Functions/Logic/Editor/Register-EditorActions.ps1

<#
.SYNOPSIS
    Gère les actions déclenchées par les boutons de l'éditeur (Ajout de noeuds, Sauvegarde, dialogues).
#>
function Global:Register-EditorActionHandlers {
    param(
        [hashtable]$Ctrl,
        [System.Windows.Window]$Window,
        [hashtable]$Context
    )

    # ==========================================================================
    # 0. HELPERS LOCAUX
    # ==========================================================================
    $SetStatus = {
        param([string]$Msg, [string]$Type = "Normal")
        if ($Ctrl.EdStatusText) {
            $Ctrl.EdStatusText.Text = $Msg
            $brushKey = switch ($Type) {
                "Success" { "SuccessBrush" }
                "Error" { "DangerBrush" }
                "Warning" { "WarningBrush" }
                Default { "TextSecondaryBrush" }
            }
            try { $Ctrl.EdStatusText.Foreground = $Window.FindResource($brushKey) } catch { }
        }
    }.GetNewClosure()

    $ResetUI = {
        if ($Ctrl.EdTree) { $Ctrl.EdTree.Items.Clear() }
        if ($Ctrl.EdNameBox) { $Ctrl.EdNameBox.Text = "" }
        # Reset inputs
        if ($Ctrl.EdPermIdentityBox) { $Ctrl.EdPermIdentityBox.Text = "" }
        if ($Ctrl.EdTagNameBox) { $Ctrl.EdTagNameBox.Text = "" }
        if ($Ctrl.EdLinkNameBox) { $Ctrl.EdLinkNameBox.Text = "" }
        if ($Ctrl.EdPubNameBox) { $Ctrl.EdPubNameBox.Text = "" }
        
        # Hide all panels
        if ($Ctrl.EdNoSelPanel) { $Ctrl.EdNoSelPanel.Visibility = "Visible" }
        if ($Ctrl.EdPropPanel) { $Ctrl.EdPropPanel.Visibility = "Collapsed" }
        if ($Ctrl.EdPropPanelPerm) { $Ctrl.EdPropPanelPerm.Visibility = "Collapsed" }
        if ($Ctrl.EdPropPanelTag) { $Ctrl.EdPropPanelTag.Visibility = "Collapsed" }
        if ($Ctrl.EdPropPanelLink) { $Ctrl.EdPropPanelLink.Visibility = "Collapsed" }
        if ($Ctrl.EdPropPanelInternalLink) { $Ctrl.EdPropPanelInternalLink.Visibility = "Collapsed" }
        if ($Ctrl.EdPropPanelPub) { $Ctrl.EdPropPanelPub.Visibility = "Collapsed" }
        
        if ($Ctrl.EdLoadCb) { $Ctrl.EdLoadCb.Tag = $null; $Ctrl.EdLoadCb.SelectedIndex = -1 }
        & $SetStatus -Msg "Interface réinitialisée."
    }.GetNewClosure()

    $LoadTemplateList = {
        try {
            if ($Ctrl.EdLoadCb) {
                $tpls = @(Get-AppSPTemplates)
                $Ctrl.EdLoadCb.ItemsSource = $tpls
                $Ctrl.EdLoadCb.DisplayMemberPath = "DisplayName"
            }
        }
        catch { }
    }.GetNewClosure()

    # Initial Loading
    & $LoadTemplateList

    # ==========================================================================
    # 1. ACTIONS ARBORESCENCE (TOOLBAR)
    # ==========================================================================
    if ($Ctrl.EdBtnNew) {
        $Ctrl.EdBtnNew.Add_Click({
                if ($Ctrl.EdTree -and $Ctrl.EdTree.Items.Count -gt 0) {
                    if ([System.Windows.MessageBox]::Show("Tout effacer ?", "Confirmation", "YesNo", "Warning") -eq 'No') { return }
                }
                & $ResetUI
                & $SetStatus -Msg "Nouvel espace de travail vierge prêt."
            }.GetNewClosure())
    }

    if ($Ctrl.EdBtnRoot) {
        $Ctrl.EdBtnRoot.Add_Click({ 
                $newItem = New-EditorNode -Name "Racine"
                if ($Ctrl.EdTree) { 
                    $Ctrl.EdTree.Items.Add($newItem) | Out-Null; $newItem.IsSelected = $true; $newItem.Focus() 
                    Sort-EditorTreeRecursive -ItemCollection $Ctrl.EdTree.Items
                }
            }.GetNewClosure())
    }

    if ($Ctrl.EdBtnRootLink) {
        $Ctrl.EdBtnRootLink.Add_Click({
                $newItem = New-EditorLinkNode -Name "Nouveau Lien" -Url "https://pnp.github.io/"
                if ($Ctrl.EdTree) { 
                    $Ctrl.EdTree.Items.Add($newItem) | Out-Null; $newItem.IsSelected = $true; $newItem.Focus() 
                    Sort-EditorTreeRecursive -ItemCollection $Ctrl.EdTree.Items
                }
            }.GetNewClosure())
    }

    if ($Ctrl.EdBtnChild) {
        $Ctrl.EdBtnChild.Add_Click({
                $p = if ($Ctrl.EdTree) { $Ctrl.EdTree.SelectedItem }
                if ($null -eq $p) { [System.Windows.MessageBox]::Show("Sélectionnez un dossier.", "Info", "OK", "Information"); return }
                $n = New-EditorNode -Name "Nouveau dossier"; $p.Items.Add($n) | Out-Null; $p.IsExpanded = $true; $n.IsSelected = $true; $n.Focus()
                $n = New-EditorNode -Name "Nouveau dossier"; $p.Items.Add($n) | Out-Null; $p.IsExpanded = $true; $n.IsSelected = $true; $n.Focus()
                Sort-EditorTreeRecursive -ItemCollection $p.Items -Level 1
            }.GetNewClosure())
    }

    if ($Ctrl.EdBtnChildLink) {
        $Ctrl.EdBtnChildLink.Add_Click({
                $p = if ($Ctrl.EdTree) { $Ctrl.EdTree.SelectedItem }
                if ($null -eq $p) { [System.Windows.MessageBox]::Show("Sélectionnez un dossier.", "Info", "OK", "Information"); return }
                if ($p.Tag.Type -eq "Link") { [System.Windows.MessageBox]::Show("Impossible d'ajouter un lien dans un lien.", "Info", "OK", "Warning"); return }
                if ($p.Tag.Type -eq "Publication") { [System.Windows.MessageBox]::Show("Impossible d'ajouter quoi que ce soit dans un nœud de publication.", "Info", "OK", "Warning"); return }
                
                $n = New-EditorLinkNode -Name "Nouveau lien" -Url "https://pnp.github.io/"
                $p.Items.Add($n) | Out-Null; $p.IsExpanded = $true; $n.IsSelected = $true; $n.Focus()
                $n = New-EditorLinkNode -Name "Nouveau lien" -Url "https://pnp.github.io/"
                $p.Items.Add($n) | Out-Null; $p.IsExpanded = $true; $n.IsSelected = $true; $n.Focus()
                Sort-EditorTreeRecursive -ItemCollection $p.Items -Level 1
            }.GetNewClosure())
    }

    # NEW: Internal Link (Lien Interne)
    if ($Ctrl.EdBtnChildInternalLink) {
        $Ctrl.EdBtnChildInternalLink.Add_Click({
                # FIX: Force Reload Function if missing (Just in case, though Global fixes it)
                if (-not (Get-Command New-EditorInternalLinkNode -ErrorAction SilentlyContinue)) {
                    $f = Join-Path $Context.ScriptRoot "Functions\Logic\New-EditorInternalLinkNode.ps1"
                    if (Test-Path $f) { . $f }
                }

                $p = if ($Ctrl.EdTree) { $Ctrl.EdTree.SelectedItem }
                if ($null -eq $p) { [System.Windows.MessageBox]::Show("Sélectionnez un dossier.", "Info", "OK", "Information"); return }
                # Validation Nesting
                if ($p.Tag.Type -eq "Link") { [System.Windows.MessageBox]::Show("Impossible d'ajouter un lien dans un lien.", "Info", "OK", "Warning"); return }
                if ($p.Tag.Type -eq "InternalLink") { [System.Windows.MessageBox]::Show("Impossible d'ajouter un lien dans un lien.", "Info", "OK", "Warning"); return }
                if ($p.Tag.Type -eq "Publication") { [System.Windows.MessageBox]::Show("Impossible d'ajouter quoi que ce soit dans un nœud de publication.", "Info", "OK", "Warning"); return }

                # 1. PRÉPARATION DIALOGUE (RECURSIVE CLONE FOR TREEVIEW)
                function Clone-ForDialog {
                    param($SourceItem)
                    
                    if ($SourceItem.Name -eq "MetaItem") { return $null }
                    $t = if ($SourceItem.Tag.Type) { $SourceItem.Tag.Type } else { "Folder" }
                    if ($t -ne "Folder") { return $null }

                    $newItem = New-Object System.Windows.Controls.TreeViewItem
                    
                    # Style Header Simple
                    $stack = New-Object System.Windows.Controls.StackPanel -Property @{ Orientation = "Horizontal" }
                    $txt = New-Object System.Windows.Controls.TextBlock -Property @{ Text = $SourceItem.Tag.Name; VerticalAlignment = "Center" }
                    $icon = New-Object System.Windows.Controls.TextBlock -Property @{ Text = "📁"; Margin = "0,0,5,0"; VerticalAlignment = "Center"; Foreground = "#FFB300" }
                    
                    $stack.Children.Add($icon) | Out-Null
                    $stack.Children.Add($txt) | Out-Null
                    $newItem.Header = $stack
                    $newItem.Tag = $SourceItem.Tag
                    $newItem.IsExpanded = $true

                    foreach ($child in $SourceItem.Items) {
                        $clonedChild = Clone-ForDialog -SourceItem $child
                        if ($clonedChild) {
                            $newItem.Items.Add($clonedChild) | Out-Null
                        }
                    }
                    return $newItem
                }

                $dialogRootItems = @()
                foreach ($rootItem in $Ctrl.EdTree.Items) {
                    $clonedRoot = Clone-ForDialog -SourceItem $rootItem
                    if ($clonedRoot) { $dialogRootItems += $clonedRoot }
                }
                
                if ($dialogRootItems.Count -eq 0) {
                    [System.Windows.MessageBox]::Show("Aucun dossier cible disponible.", "Info", "OK", "Warning"); return
                }

                # 2. DIALOGUE XAML
                $xaml = @"
<Window xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation'
        xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'
        Title='Sélectionner une cible' Height='500' Width='400' WindowStartupLocation='CenterOwner' ResizeMode='NoResize'>
    <Window.Resources>
        <Style x:Key='DialogButtonStyle' TargetType='Button'>
            <Setter Property='Background' Value='#EEEEEE'/>
            <Setter Property='Foreground' Value='#333333'/>
            <Setter Property='Padding' Value='15,0'/>
            <Setter Property='BorderThickness' Value='0'/>
            <Setter Property='FontWeight' Value='SemiBold'/>
            <Setter Property='Template'>
                <Setter.Value>
                    <ControlTemplate TargetType='Button'>
                        <Border Background='{TemplateBinding Background}' CornerRadius='4'>
                            <ContentPresenter HorizontalAlignment='Center' VerticalAlignment='Center'/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Style.Triggers>
                <Trigger Property='IsMouseOver' Value='True'>
                    <Setter Property='Background' Value='#DDDDDD'/>
                </Trigger>
            </Style.Triggers>
        </Style>
        <Style x:Key='PrimaryDialogButtonStyle' TargetType='Button' BasedOn='{StaticResource DialogButtonStyle}'>
            <Setter Property='Background' Value='#00695C'/>
            <Setter Property='Foreground' Value='White'/>
            <Style.Triggers>
                <Trigger Property='IsMouseOver' Value='True'>
                    <Setter Property='Background' Value='#004D40'/>
                </Trigger>
            </Style.Triggers>
        </Style>
        <Style x:Key='ExpandCollapseToggleStyle' TargetType='ToggleButton'>
            <Setter Property='Focusable' Value='False'/>
            <Setter Property='Width' Value='19'/>
            <Setter Property='Height' Value='13'/>
            <Setter Property='Template'>
                <Setter.Value>
                    <ControlTemplate TargetType='ToggleButton'>
                        <Border Background='Transparent' Height='13' Width='19'>
                            <Path x:Name='ExpandPath' Data='M 4 0 L 8 4 L 4 8' Stroke='#666' StrokeThickness='1.5' HorizontalAlignment='Left' VerticalAlignment='Center' Margin='6,0,0,0'/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property='IsChecked' Value='True'>
                                <Setter TargetName='ExpandPath' Property='Data' Value='M 0 4 L 4 8 L 8 4'/>
                                <Setter TargetName='ExpandPath' Property='Fill' Value='#666'/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    
    <Grid Margin='20'>
        <Grid.RowDefinitions>
            <RowDefinition Height='Auto'/>
            <RowDefinition Height='*'/>
            <RowDefinition Height='Auto'/>
        </Grid.RowDefinitions>
        
        <StackPanel Margin='0,0,0,15'>
            <StackPanel Orientation='Horizontal' Margin='0,0,0,5'>
                <TextBlock Text='🔗' FontSize='16' Margin='0,0,10,0' VerticalAlignment='Center'/>
                <TextBlock Text='Lien Interne' FontWeight='Bold' FontSize='16' Foreground='#00695C' VerticalAlignment='Center'/>
            </StackPanel>
            <TextBlock Text='Veuillez sélectionner le dossier vers lequel ce lien doit pointer.' Foreground='#666666' TextWrapping='Wrap'/>
        </StackPanel>
        
        <Border Grid.Row='1' BorderBrush='#DDDDDD' BorderThickness='1' CornerRadius='4' Background='White'>
            <TreeView x:Name='FolderTree' BorderThickness='0' Margin='2'>
                <TreeView.ItemContainerStyle>
                    <Style TargetType='TreeViewItem'>
                        <Setter Property='IsExpanded' Value='True'/>
                        <Setter Property='FontSize' Value='13'/>
                        <Setter Property='Padding' Value='5,2'/>
                        <Setter Property='Template'>
                            <Setter.Value>
                                <ControlTemplate TargetType='TreeViewItem'>
                                    <Grid>
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width='Auto' MinWidth='19'/>
                                            <ColumnDefinition Width='*'/>
                                        </Grid.ColumnDefinitions>
                                        <Grid.RowDefinitions>
                                            <RowDefinition Height='Auto'/>
                                            <RowDefinition/>
                                        </Grid.RowDefinitions>
                                        <ToggleButton x:Name='Expander' Style='{StaticResource ExpandCollapseToggleStyle}' ClickMode='Press' IsChecked='{Binding IsExpanded, RelativeSource={RelativeSource TemplatedParent}}'/>
                                        <Border x:Name='Bd' Grid.Column='1' BorderBrush='{TemplateBinding BorderBrush}' BorderThickness='{TemplateBinding BorderThickness}' Background='{TemplateBinding Background}' Padding='{TemplateBinding Padding}' SnapsToDevicePixels='true'>
                                            <ContentPresenter x:Name='PART_Header' ContentSource='Header' HorizontalAlignment='{TemplateBinding HorizontalContentAlignment}' SnapsToDevicePixels='{TemplateBinding SnapsToDevicePixels}'/>
                                        </Border>
                                        <ItemsPresenter x:Name='ItemsHost' Grid.Column='1' Grid.Row='1'/>
                                    </Grid>
                                    <ControlTemplate.Triggers>
                                        <Trigger Property='HasItems' Value='false'>
                                            <Setter TargetName='Expander' Property='Visibility' Value='Hidden'/>
                                        </Trigger>
                                        <Trigger Property='IsSelected' Value='true'>
                                            <Setter TargetName='Bd' Property='Background' Value='#CCE5FF'/>
                                            <Setter TargetName='Bd' Property='BorderBrush' Value='#99CCFF'/>
                                            <Setter TargetName='Bd' Property='BorderThickness' Value='1'/>
                                        </Trigger>
                                        <Trigger Property='IsExpanded' Value='false'>
                                            <Setter TargetName='ItemsHost' Property='Visibility' Value='Collapsed'/>
                                        </Trigger>
                                    </ControlTemplate.Triggers>
                                </ControlTemplate>
                            </Setter.Value>
                        </Setter>
                    </Style>
                </TreeView.ItemContainerStyle>
            </TreeView>
        </Border>
        
        <StackPanel Grid.Row='2' Orientation='Horizontal' HorizontalAlignment='Right' Margin='0,15,0,0'>
            <Button x:Name='BtnCancel' Content='Annuler' Width='100' Height='36' Margin='0,0,10,0' Style='{StaticResource DialogButtonStyle}' IsCancel='True'/>
            <Button x:Name='BtnSelect' Content='Valider la cible' Width='130' Height='36' Style='{StaticResource PrimaryDialogButtonStyle}' IsDefault='True'/>
        </StackPanel>
    </Grid>
</Window>
"@
                $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
                $dlg = [System.Windows.Markup.XamlReader]::Load($reader)
                
                # Apply Style if possible (Optional)
                try { 
                    if ($Window.Resources.Contains("PrimaryButtonStyle")) { $dlg.Resources.Add("PrimaryButtonStyle", $Window.Resources["PrimaryButtonStyle"]) }
                    if ($dlg.FindName("BtnSelect")) { $dlg.FindName("BtnSelect").Style = $Window.FindResource("PrimaryButtonStyle") }
                }
                catch {}

                $tree = $dlg.FindName("FolderTree")
                $btnOk = $dlg.FindName("BtnSelect")
                $btnCancel = $dlg.FindName("BtnCancel")
                
                # INJECTION DES STYLES (Pour visuel identique)
                try {
                    if ($Window.Resources.Contains("ModernTreeViewItemStyle")) {
                        $dlg.Resources.Add("ModernTreeViewItemStyle", $Window.Resources["ModernTreeViewItemStyle"])
                        # REMOVED: Do NOT overwrite the style
                    }
                }
                catch { }

                # Populate TreeView
                foreach ($item in $dialogRootItems) {
                    $tree.Items.Add($item) | Out-Null
                }

                $dlg.Owner = $Window
                
                $btnOk.Add_Click({
                        if ($tree.SelectedItem) { $dlg.DialogResult = $true; $dlg.Close() }
                        else { [System.Windows.MessageBox]::Show("Veuillez sélectionner un dossier dans la liste.", "Attention", "OK", "Warning") }
                    }.GetNewClosure())
                
                $btnCancel.Add_Click({ $dlg.DialogResult = $false; $dlg.Close() }.GetNewClosure())

                if ($dlg.ShowDialog() -eq $true) {
                    try {
                        $sel = $tree.SelectedItem
                        if (-not $sel) { [System.Windows.MessageBox]::Show("Erreur interne : Pas de sélection récupérée.", "Bug", "OK", "Error"); return }

                        # 3. CRÉATION DU NOEUD
                        $targetData = $sel.Tag
                        $tName = "Vers $($targetData.Name)"
                        $tId = $targetData.Id
                        
                        $n = New-EditorInternalLinkNode -Name $tName -TargetNodeId $tId
                        
                        if (-not $n) { [System.Windows.MessageBox]::Show("Erreur : La fonction New-EditorInternalLinkNode a retourné `$null.", "Bug", "OK", "Error"); return }

                        $p.Items.Add($n) | Out-Null
                        $p.IsExpanded = $true
                        $n.IsSelected = $true
                        $n.Focus()
                        
                        # Important : Refresh UI du parent (StackPanel) pour afficher le lien correctement
                        $p.UpdateLayout()
                        
                        # Important : Refresh UI du parent (StackPanel) pour afficher le lien correctement
                        $p.UpdateLayout()
                        
                        Sort-EditorTreeRecursive -ItemCollection $p.Items -Level 1
                    }
                    catch {
                        [System.Windows.MessageBox]::Show("Erreur CRITIQUE création noeud : $_", "Error", "OK", "Error")
                    }
                }

            }.GetNewClosure())
    }

    if ($Ctrl.EdBtnAddPub) {
        $Ctrl.EdBtnAddPub.Add_Click({
                $p = if ($Ctrl.EdTree) { $Ctrl.EdTree.SelectedItem }
                if ($null -eq $p) { [System.Windows.MessageBox]::Show("Sélectionnez un dossier parent.", "Info", "OK", "Information"); return }
                if ($p.Tag.Type -eq "Link") { [System.Windows.MessageBox]::Show("Impossible d'ajouter une publication dans un lien.", "Info", "OK", "Warning"); return }
                if ($p.Tag.Type -eq "Publication") { [System.Windows.MessageBox]::Show("Impossible d'imbriquer des publications.", "Info", "OK", "Warning"); return }
                if ($p.Tag.Type -eq "File") { [System.Windows.MessageBox]::Show("Impossible d'ajouter un élément dans un fichier.", "Info", "OK", "Warning"); return }
            
                $n = New-EditorPubNode -Name "Vers Site..."
                $p.Items.Add($n) | Out-Null; $p.IsExpanded = $true; $n.IsSelected = $true; $n.Focus()
                Update-EditorBadges -TreeItem $p
                $n = New-EditorPubNode -Name "Vers Site..."
                $p.Items.Add($n) | Out-Null; $p.IsExpanded = $true; $n.IsSelected = $true; $n.Focus()
                Update-EditorBadges -TreeItem $p
                Sort-EditorTreeRecursive -ItemCollection $p.Items -Level 1
            }.GetNewClosure())
    }

    if ($Ctrl.EdBtnAddFile) {
        $Ctrl.EdBtnAddFile.Add_Click({
                # FIX: Force Reload Function ALWAYS
                $f = Join-Path $Context.ScriptRoot "Functions\Logic\Editor\New-EditorFileNode.ps1"
                if (Test-Path $f) { . $f }

                $p = if ($Ctrl.EdTree) { $Ctrl.EdTree.SelectedItem }
                if ($null -eq $p) { [System.Windows.MessageBox]::Show("Sélectionnez un dossier parent.", "Info", "OK", "Information"); return }
                
                # Validation Nesting
                $forbiddenTypes = @("Link", "InternalLink", "Publication", "File")
                if ($forbiddenTypes -contains $p.Tag.Type) { 
                    [System.Windows.MessageBox]::Show("Impossible d'ajouter un fichier dans ce type d'élément ($($p.Tag.Type)).", "Stop", "OK", "Warning")
                    return 
                }

                $n = New-EditorFileNode -Name "Nouveau Fichier" -SourceUrl ""
                $p.Items.Add($n) | Out-Null
                $p.IsExpanded = $true
                
                # Apply Sort first (Level 1 for Children)
                Sort-EditorTreeRecursive -ItemCollection $p.Items -Level 1
                
                # Force Layout Update to ensure container generation
                $p.UpdateLayout()
                
                # Select and Focus
                $n.IsSelected = $true
                $n.Focus()
                
                # Force Panel Update (Selection Logic) if needed
                # The SelectionChanged event should trigger principally
            }.GetNewClosure())
    }

    # Helper Fetch Info URL
    if ($Ctrl.EdFileFetchInfoButton) {
        $Ctrl.EdFileFetchInfoButton.Add_Click({
                $url = $Ctrl.EdFileUrlBox.Text
                if ([string]::IsNullOrWhiteSpace($url)) { return }

                try {
                    $req = [System.Net.WebRequest]::Create($url)
                    $req.Method = "HEAD"
                    $req.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) PowerShell/SharePointBuilder"
                    $resp = $req.GetResponse()
                    
                    # 1. Try Content-Disposition
                    $filename = ""
                    $cd = $resp.Headers["Content-Disposition"]
                    if ($cd) {
                        if ($cd -match 'filename="?([^"]+)"?') { $filename = $matches[1] }
                    }

                    # 2. Try URL Segments
                    if (-not $filename) {
                        $uri = $resp.ResponseUri
                        $seg = $uri.Segments
                        if ($seg.Count -gt 0) {
                            $filename = $seg[$seg.Count - 1]
                        }
                    }

                    $resp.Close()

                    if ($filename) {
                        # FIX: Check for Auth/Login pages redirect
                        if ($filename -match "authorize|login|signin|oauth") {
                            # Fallback to original URL last segment if response was a redirect to login
                            $rawUri = [System.Uri]$url
                            $rawSeg = $rawUri.Segments
                            if ($rawSeg.Count -gt 0) {
                                $candidate = $rawSeg[$rawSeg.Count - 1]
                                if (-not ($candidate -match "authorize|login|signin|oauth")) {
                                    $filename = $candidate
                                }
                            }
                        }

                        # Final Decode to ensure clean text (e.g. %20 -> Space)
                        $filename = [System.Web.HttpUtility]::UrlDecode($filename)

                        $Ctrl.EdFileNameBox.Text = $filename
                        & $SetStatus -Msg "Nom de fichier récupéré : $filename" -Type "Success"
                    }
                    else {
                        & $SetStatus -Msg "Impossible de déterminer le nom du fichier." -Type "Warning"
                    }
                }
                catch {
                    & $SetStatus -Msg "Erreur lors de la vérification URL : $($_.Exception.Message)" -Type "Error"
                }
            }.GetNewClosure())
    }
    
    if ($Ctrl.EdFileDeleteButton) {
        $Ctrl.EdFileDeleteButton.Add_Click({
                $sel = $Ctrl.EdTree.SelectedItem
                if ($sel -and $sel.Tag.Type -eq "File") {
                    if ([System.Windows.MessageBox]::Show("Supprimer ce fichier ?", "Confirmation", "YesNo", "Question") -eq 'Yes') {
                        $p = $sel.Parent
                        if ($p) { $p.Items.Remove($sel) }
                    }
                }
            }.GetNewClosure())
    }

    if ($Ctrl.EdBtnDel) {
        $Ctrl.EdBtnDel.Add_Click({
                $i = $Ctrl.EdTree.SelectedItem; if ($null -eq $i) { return }
                if ([System.Windows.MessageBox]::Show("Supprimer '$($i.Tag.Name)' ?", "Confirmation", "YesNo", "Question") -eq 'No') { return }
            
                $p = $i.Parent
                if ($p -is [System.Windows.Controls.ItemsControl]) {
                    $p.Items.Remove($i)

                    # FIX: Rafraîchir les badges du parent pour mettre à jour l'état visuel (ex: icône publication)
                    if ($p -is [System.Windows.Controls.TreeViewItem]) {
                        Update-EditorBadges -TreeItem $p
                    }
                }
            }.GetNewClosure())
    }

    # ==========================================================================
    # 2. ACTIONS PROPRIÉTÉS (ADD PERM / TAG)
    # ==========================================================================
    # ==========================================================================
    # 2. ACTIONS PROPRIÉTÉS (ADD PERM / TAG) - GLOBAL BUTTONS
    # ==========================================================================
    # CLOSURE FIX: We need to ensure $Ctrl is captured. Defining distinct scriptblocks invoked with GetNewClosure() is safest.
    
    if ($Ctrl.EdBtnGlobalAddPerm) {
        $Ctrl.EdBtnGlobalAddPerm.Add_Click({
                $sel = $Ctrl.EdTree.SelectedItem
                if (-not $sel) { [System.Windows.MessageBox]::Show("Sélectionnez un élément dans l'arbre.", "Info", "OK", "Information"); return }
            
                # Validation Type
                if ($sel.Tag.Type -eq "Link" -or $sel.Tag.Type -eq "InternalLink") {
                    [System.Windows.MessageBox]::Show("Les permissions ne sont pas gérées sur les raccourcis.", "Info", "OK", "Information")
                    return
                }
                # Validation Meta (Impossible d'ajouter une perm sur une perm/tag)
                if ($sel.Tag.Type -eq "Permission" -or $sel.Tag.Type -eq "Tag" -or $sel.Name -eq "MetaItem") {
                    [System.Windows.MessageBox]::Show("Impossible d'ajouter une permission à ce niveau.", "Info", "OK", "Information")
                    return
                }

                # Création NOEUD Permission
                $newNode = New-EditorPermNode -Email "user@domaine.com" -Level "Read"
            
                # Ajout à l'arbre
                $sel.Items.Add($newNode) | Out-Null
                $sel.IsExpanded = $true
                $newNode.IsSelected = $true
            
                # Update Badges Parent
                Update-EditorBadges -TreeItem $sel
            }.GetNewClosure())
    }

    if ($Ctrl.EdBtnGlobalAddTag) {
        $Ctrl.EdBtnGlobalAddTag.Add_Click({
                $sel = $Ctrl.EdTree.SelectedItem
                if (-not $sel) { [System.Windows.MessageBox]::Show("Sélectionnez un élément dans l'arbre.", "Info", "OK", "Information"); return }
            
                # Validation Meta
                if ($sel.Tag.Type -eq "Permission" -or $sel.Tag.Type -eq "Tag" -or $sel.Name -eq "MetaItem") {
                    [System.Windows.MessageBox]::Show("Impossible d'ajouter un tag à ce niveau.", "Info", "OK", "Information")
                    return
                }
            
                # Création NOEUD Tag (STATIC)
                $newNode = New-EditorTagNode -Name "NomColonne" -Value "Valeur" -IsDynamic $false
            
                # Ajout à l'arbre
                $sel.Items.Add($newNode) | Out-Null
                $sel.IsExpanded = $true
                $newNode.IsSelected = $true
            
                # Update Badges Parent
                Update-EditorBadges -TreeItem $sel
            }.GetNewClosure())
    }

    if ($Ctrl.EdBtnGlobalAddDynamicTag) {
        $Ctrl.EdBtnGlobalAddDynamicTag.Add_Click({
                $sel = $Ctrl.EdTree.SelectedItem
                if (-not $sel) { [System.Windows.MessageBox]::Show("Sélectionnez un élément dans l'arbre.", "Info", "OK", "Information"); return }
            
                # Validation Meta
                if ($sel.Tag.Type -eq "Permission" -or $sel.Tag.Type -eq "Tag" -or $sel.Name -eq "MetaItem") {
                    [System.Windows.MessageBox]::Show("Impossible d'ajouter un tag à ce niveau.", "Info", "OK", "Information")
                    return
                }
            
                # Création NOEUD Tag (DYNAMIC)
                $newNode = New-EditorTagNode -Name "NomColonne" -Value "DYNAMIC" -IsDynamic $true
                # $newNode.Tag.IsDynamic = $true # Déjà fait par paramètre
                $newNode.Tag.SourceForm = ""
                $newNode.Tag.SourceVar = ""
            
                # Ajout à l'arbre
                $sel.Items.Add($newNode) | Out-Null
                $sel.IsExpanded = $true
                $newNode.IsSelected = $true
            
                # Update Badges Parent
                Update-EditorBadges -TreeItem $sel
            }.GetNewClosure())
    }

    # ==========================================================================
    # 3. PERSISTANCE (LOAD / SAVE / NEW / DELETE)
    # ==========================================================================
    $Ctrl.EdBtnNew.Add_Click({
            if ($Ctrl.EdTree.Items.Count -gt 0) {
                if ([System.Windows.MessageBox]::Show("Tout effacer et créer un nouveau modèle ?", "Confirmation", "YesNo", "Warning") -eq 'No') { return }
            }
            & $ResetUI
            & $SetStatus -Msg "Nouveau modèle vierge prêt."
        }.GetNewClosure())

    $Ctrl.EdBtnLoad.Add_Click({
            $selectedTpl = $Ctrl.EdLoadCb.SelectedItem
            if (-not $selectedTpl) { & $SetStatus -Msg "Aucun modèle sélectionné." -Type "Warning"; return }
            
            if ($Ctrl.EdTree.Items.Count -gt 0) { if ([System.Windows.MessageBox]::Show("Charger va écraser le modèle actuel. Continuer ?", "Attention", "YesNo", "Warning") -ne 'Yes') { return } }
            
            if ($Ctrl.EdTree) { 
                Convert-JsonToEditorTree -Json $selectedTpl.StructureJson -TreeView $Ctrl.EdTree 
                Sort-EditorTreeRecursive -ItemCollection $Ctrl.EdTree.Items
            }
                
            if ($Ctrl.EdPropPanel) { $Ctrl.EdPropPanel.Visibility = "Collapsed" }
            if ($Ctrl.EdPropPanelPerm) { $Ctrl.EdPropPanelPerm.Visibility = "Collapsed" }
            if ($Ctrl.EdPropPanelTag) { $Ctrl.EdPropPanelTag.Visibility = "Collapsed" }
            if ($Ctrl.EdPropPanelLink) { $Ctrl.EdPropPanelLink.Visibility = "Collapsed" }
            if ($Ctrl.EdPropPanelInternalLink) { $Ctrl.EdPropPanelInternalLink.Visibility = "Collapsed" }
            if ($Ctrl.EdPropPanelInternalLink) { $Ctrl.EdPropPanelInternalLink.Visibility = "Collapsed" }
            if ($Ctrl.EdPropPanelPub) { $Ctrl.EdPropPanelPub.Visibility = "Collapsed" }
            if ($Ctrl.EdPanelFile) { $Ctrl.EdPanelFile.Visibility = "Collapsed" }
            if ($Ctrl.EdNoSelPanel) { $Ctrl.EdNoSelPanel.Visibility = "Visible" }
                
            $Ctrl.EdLoadCb.Tag = $selectedTpl.TemplateId
            
            & $SetStatus -Msg "Modèle '$($selectedTpl.DisplayName)' chargé." -Type "Success"
        }.GetNewClosure())

    $Ctrl.EdBtnSave.Add_Click({
            if ($Ctrl.EdTree.Items.Count -eq 0) { [System.Windows.MessageBox]::Show("L'arbre est vide.", "Erreur", "OK", "Warning"); return }

            Sort-EditorTreeRecursive -ItemCollection $Ctrl.EdTree.Items

            $json = Convert-EditorTreeToJson -TreeView $Ctrl.EdTree
        
            $currentId = $Ctrl.EdLoadCb.Tag
            $currentName = if ($Ctrl.EdLoadCb.SelectedItem) { $Ctrl.EdLoadCb.SelectedItem.DisplayName } else { "" }

            if ($currentId) {
                $msg = "Le modèle '$currentName' est actuellement chargé.`n`nVoulez-vous écraser les modifications ?`n`nOUI : Écraser l'existant`nNON : Créer une copie (Enregistrer sous)`nANNULER : Ne rien faire"
                $choice = [System.Windows.MessageBox]::Show($msg, "Sauvegarde", [System.Windows.MessageBoxButton]::YesNoCancel, [System.Windows.MessageBoxImage]::Question)
                switch ($choice) {
                    'Cancel' { return }
                    'No' {
                        $currentId = $null
                        Add-Type -AssemblyName Microsoft.VisualBasic
                        $newName = [Microsoft.VisualBasic.Interaction]::InputBox("Nom du nouveau modèle :", "Enregistrer une copie", "$currentName - Copie")
                        if ([string]::IsNullOrWhiteSpace($newName)) { return }
                        $currentName = $newName
                    }
                }
            }

            if (-not $currentId) {
                if ([string]::IsNullOrWhiteSpace($currentName)) {
                    Add-Type -AssemblyName Microsoft.VisualBasic
                    $currentName = [Microsoft.VisualBasic.Interaction]::InputBox("Nom du nouveau modèle :", "Sauvegarder", "Mon Nouveau Modèle")
                }
                if ([string]::IsNullOrWhiteSpace($currentName)) { return }
                $currentId = [Guid]::NewGuid().ToString()
            }

            try {
                Set-AppSPTemplate -TemplateId $currentId -DisplayName $currentName -Description "Modèle personnalisé" -StructureJson $json
            
                & $SetStatus -Msg "Modèle '$currentName' sauvegardé avec succès." -Type "Success"
            
                & $LoadTemplateList
                $newItem = $Ctrl.EdLoadCb.ItemsSource | Where-Object { $_.TemplateId -eq $currentId } | Select-Object -First 1
                if ($newItem) { $Ctrl.EdLoadCb.SelectedItem = $newItem; $Ctrl.EdLoadCb.Tag = $currentId }

            }
            catch { & $SetStatus -Msg "Erreur lors de la sauvegarde : $($_.Exception.Message)" -Type "Error" }

        }.GetNewClosure())

    if ($Ctrl.EdBtnDeleteTpl) {
        $Ctrl.EdBtnDeleteTpl.Add_Click({
                $currentId = $Ctrl.EdLoadCb.Tag
                if (-not $currentId -and $Ctrl.EdLoadCb.SelectedItem) { $currentId = $Ctrl.EdLoadCb.SelectedItem.TemplateId }
                if (-not $currentId) { [System.Windows.MessageBox]::Show("Aucun modèle sélectionné.", "Info", "OK", "Information"); return }
            
                $nom = if ($Ctrl.EdLoadCb.SelectedItem) { $Ctrl.EdLoadCb.SelectedItem.DisplayName } else { "ce modèle" }
            
                if ([System.Windows.MessageBox]::Show("Supprimer définitivement '$nom' ?", "Suppression", "YesNo", "Error") -eq 'Yes') {
                    try {
                        Remove-AppSPTemplate -TemplateId $currentId
                    
                        & $SetStatus -Msg "Modèle '$nom' supprimé." -Type "Normal"
                        & $LoadTemplateList; & $ResetUI
                    }
                    catch { & $SetStatus -Msg "Erreur suppression : $($_.Exception.Message)" -Type "Error" }
                }
            }.GetNewClosure())
    }
}
