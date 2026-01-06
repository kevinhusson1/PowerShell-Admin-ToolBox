function Initialize-DeployerLogic {
    param(
        [System.Windows.Window]$Window,
        [string]$ScriptRoot
    )

    # 1. RÉFÉRENCES UI
    $Ctrl = @{
        ListBox           = $Window.FindName("ConfigListBox")
        Title             = $Window.FindName("ConfigTitleText")
        Site              = $Window.FindName("BadgeSiteText")
        Lib               = $Window.FindName("BadgeLibText")
        Template          = $Window.FindName("BadgeTemplateText")
        Warning           = $Window.FindName("PermissionWarningBorder")
        DynamicFormPanel  = $Window.FindName("DynamicFormPanel")
        Placeholder       = $Window.FindName("PlaceholderText")
        PlaceholderPanel  = $Window.FindName("PlaceholderPanel")
        DetailGrid        = $Window.FindName("DetailGrid")
        BtnDeploy         = $Window.FindName("DeployButton")
        BtnOpen           = $Window.FindName("OpenTargetButton")
        LogBox            = $Window.FindName("LogRichTextBox")

        ProgressBar       = $Window.FindName("MainProgressBar")
        AuthOverlay       = $Window.FindName("AuthOverlay")
        OverlayBtn        = $Window.FindName("OverlayConnectButton")
        FolderNamePreview = $Window.FindName("FolderNamePreviewText")
    }

    # Helper Log
    $Log = { 
        param($msg, $level = "Info") 
        if ($Ctrl.LogBox) { Write-AppLog -Message $msg -Level $level -RichTextBox $Ctrl.LogBox }
    }.GetNewClosure()

    # --- LOCALISATION (Ensure Load) ---
    # Par sécurité, on recharge le fichier local si Get-AppText échoue ou pour être sûr
    if ($Global:AppConfig.defaultLanguage) {
        $locPath = Join-Path $ScriptRoot "Localization\$($Global:AppConfig.defaultLanguage).json"
        if (Test-Path $locPath) { Add-AppLocalizationSource -FilePath $locPath }
    }
    
    # On utilise directement Get-AppText fourni par le module Localization


    # --- UI INIT ---
    if ($Ctrl.AuthOverlay) {
        # Les textes sont gérés par le XAML via ##loc:..##
        # On ne fait rien ici pour éviter des erreurs de manipulation d'arbre visuel.
    }

    # Les Placeholder et Textes initiaux sont désormais gérés par les tokens ##loc## dans le XAML.
    # if ($Ctrl.Placeholder) { $Ctrl.Placeholder.Text = Get-AppText "sp_deploy.placeholder_msg" }
    # $ConfigTitleText = $Window.FindName("ConfigTitleText")
    # if ($ConfigTitleText) { $ConfigTitleText.Text = Get-AppText "sp_deploy.placeholder_select" }
    # if ($Ctrl.BtnDeploy) { $Ctrl.BtnDeploy.Content = Get-AppText "sp_deploy.btn_deploy" }

    # 2. LOGIQUE DE CHARGEMENT (Appelée par AuthCallback)
    $Global:DeployerLoadAction = {
        try {
            # Check Auth
            if (-not $Global:AppAzureAuth.UserAuth.Connected) {
                # Mode Déconnecté : Vider la liste
                if ($Ctrl.ListBox) { $Ctrl.ListBox.ItemsSource = $null }
                # Afficher l'overlay
                if ($Ctrl.AuthOverlay) { $Ctrl.AuthOverlay.Visibility = "Visible" }
                
                & $Log (Get-AppText "sp_deploy.status_disconnected") "Warning"
                return
            }
            
            # Connecté -> Masquer l'overlay
            if ($Ctrl.AuthOverlay) { $Ctrl.AuthOverlay.Visibility = "Collapsed" }

            # Récupération Groupes (Graph)
            $userGroups = @()
            try {
                $userGroups = Get-AppUserAzureGroups
            }
            catch {
                # & $Log "Erreur récupération groupes : $_" "Error"
            }

            # Récupération Configs
            $allConfigs = Get-AppDeployConfigs
            
            # Filtrage
            $filtered = @()
            foreach ($cfg in $allConfigs) {
                # Format: "Group1, Group2"
                $roles = if ($cfg.AuthorizedRoles) { $cfg.AuthorizedRoles -split "," } else { @() }
                $roles = $roles | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                
                $isAuthorized = $false
                if ($roles.Count -eq 0) { 
                    $isAuthorized = $true 
                }
                else {
                    foreach ($r in $roles) {
                        if ($userGroups -contains $r) { 
                            $isAuthorized = $true; 
                            break 
                        }
                    }
                }
                
                if ($isAuthorized) { $filtered += $cfg }
            }

            if ($Ctrl.ListBox) {
                $Ctrl.ListBox.ItemsSource = $filtered
                # $Ctrl.ListBox.DisplayMemberPath = "ConfigName"  <-- Removed because ItemTemplate is set in XAML
            }
            
            & $Log (Get-AppText "sp_deploy.status_ready") "Success"

        }
        catch {
            & $Log "Erreur chargement : $($_.Exception.Message)" "Error"
        }
    }.GetNewClosure()


    # 2.5 ACTION OVERLAY CONNECT
    if ($Ctrl.OverlayBtn) {
        $Ctrl.OverlayBtn.Add_Click({
                # On trouve le bouton de connexion principal et on simule un clic ou on appelle la logique
                # Le plus simple est de déclencher l'événement du header Auth
                $authBtn = $Window.FindName("ScriptAuthTextButton")
                if ($authBtn) { $authBtn.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) }
            }.GetNewClosure())
    }

    # 3. SÉLECTION CONFIGURATION
    if ($Ctrl.ListBox) {
        $Ctrl.ListBox.Add_SelectionChanged({
                $cfg = $this.SelectedItem
                if (-not $cfg) { return }

                # Toggle UI
                if ($Ctrl.PlaceholderPanel) { $Ctrl.PlaceholderPanel.Visibility = "Collapsed" }
                if ($Ctrl.DetailGrid) { $Ctrl.DetailGrid.Visibility = "Visible" }

                # Update Header
                $Ctrl.Title.Text = $cfg.ConfigName
                $Ctrl.Site.Text = $cfg.SiteUrl
                $Ctrl.Lib.Text = $cfg.LibraryName
            
                # Nom du Template
                # On a juste l'ID, on essaie de trouver le nom si possible, sinon ID
                $tplName = $cfg.TemplateId
                # Optim : on pourrait charger les templates en cache.
                try { 
                    $t = Get-AppSPTemplates | Where-Object { $_.TemplateId -eq $cfg.TemplateId } | Select-Object -First 1
                    if ($t) { $tplName = $t.DisplayName }
                }
                catch {}
                $Ctrl.Template.Text = $tplName

                # Warning Overwrite
                if ($Ctrl.Warning) {
                    $Ctrl.Warning.Visibility = if ($cfg.OverwritePermissions -eq 1) { "Visible" } else { "Collapsed" }
                }

                # GÉNÉRATION FORMULAIRE
                if ($Ctrl.DynamicFormPanel) { $Ctrl.DynamicFormPanel.Children.Clear() }
                $Ctrl.BtnDeploy.IsEnabled = $false # Désactivé tant que non validé (ou au moins généré)

                if ($cfg.TargetFolder) {
                    # Charger la règle
                    try {
                        $rules = Get-AppNamingRules
                        $targetRule = $rules | Where-Object { $_.RuleId -eq $cfg.TargetFolder } | Select-Object -First 1

                        if ($targetRule) {
                            $layout = ($targetRule.DefinitionJson | ConvertFrom-Json).Layout
                            
                            # LOGIQUE PREVIEW (Visual Flow Debugged)
                            $UpdatePreviewAction = {
                                param($s, $e)
                                try {
                                    $root = $null
                                    # 1. Try Sender (Manual Invoke)
                                    if ($s -is [System.Windows.Controls.StackPanel] -and $s.Name -eq "DynamicFormPanel") { 
                                        $root = $s 
                                    }
                                    
                                    # 2. Try Capture
                                    if (-not $root) { 
                                        if ($Ctrl.DynamicFormPanel) { $root = $Ctrl.DynamicFormPanel }
                                    }
                                    
                                    # 3. Try Refetch (Last Resort)
                                    if (-not $root -or $root.Children.Count -eq 0) {
                                        # Write-Host "DEBUG: Root empty or null, refetching..."
                                        if ($Window) { $root = $Window.FindName("DynamicFormPanel") }
                                    }
                                    
                                    # Write-Host "DEBUG: Preview Root Children: $($root.Children.Count)"

                                    # 1. Sous-dossier optionnel (via Tag "OptionalSubFolder")
                                    $optVal = ""
                                    
                                    # Fonction locale pour chercher dans l'arbre logique
                                    function Find-ControlRecursive {
                                        param($parent, $tagName)
                                        if (-not $parent) { return $null }

                                        # 1. Direct match
                                        if ("$($parent.Tag)" -eq $tagName) { return $parent }
                                        
                                        # 2. Children (Panel)
                                        if ($parent -is [System.Windows.Controls.Panel]) {
                                            foreach ($child in $parent.Children) {
                                                $res = Find-ControlRecursive -parent $child -tagName $tagName
                                                if ($res) { return $res }
                                            }
                                        }
                                        # 3. Content (ScrollViewer, ContentControl)
                                        elseif ($parent -is [System.Windows.Controls.ContentControl]) {
                                            if ($parent.Content) {
                                                $res = Find-ControlRecursive -parent $parent.Content -tagName $tagName
                                                if ($res) { return $res }
                                            }
                                        }
                                        # 4. Child (Decorator -> Border)
                                        elseif ($parent -is [System.Windows.Controls.Decorator]) {
                                            if ($parent.Child) {
                                                $res = Find-ControlRecursive -parent $parent.Child -tagName $tagName
                                                if ($res) { return $res }
                                            }
                                        }
                                        return $null
                                    }
                                    
                                    $optCtrl = Find-ControlRecursive -parent $root -tagName "OptionalSubFolder"
                                    if ($optCtrl) { 
                                        $optVal = $optCtrl.Text 
                                    }

                                    # 2. Nom Dynamique (Recherche par Tag "FormDynamicStack")
                                    $dynName = ""
                                    $dynStack = Find-ControlRecursive -parent $root -tagName "FormDynamicStack"

                                    if ($dynStack) {
                                        # On itère sur les enfants LOGIQUES
                                        foreach ($child in $dynStack.Children) {
                                            $part = ""
                                            if ($child -is [System.Windows.Controls.TextBox]) { $part = $child.Text }
                                            elseif ($child -is [System.Windows.Controls.TextBlock]) { $part = $child.Text }
                                            elseif ($child -is [System.Windows.Controls.ComboBox]) { $part = $child.SelectedItem }
                                            
                                            $dynName += $part
                                        }
                                    }
                                    
                                    # 3. Assemblage
                                    $finalText = $dynName
                                    if (-not [string]::IsNullOrWhiteSpace($optVal)) {
                                        if ([string]::IsNullOrWhiteSpace($finalText)) { $finalText = $optVal }
                                        else { $finalText = "$optVal/$finalText" }
                                    }
                                    
                                    # 4. UPDATE UI
                                    $previewRef = $Ctrl.FolderNamePreview 
                                    if (-not $previewRef) {
                                        $previewRef = Find-ControlRecursive -parent $root -tagName "PreviewText"
                                    }
                                    
                                    if ($previewRef) {
                                        $previewRef.Text = if ($finalText) { $finalText } else { " " } 
                                    }
                                }
                                catch {
                                    Write-Host "Preview Error: $_"
                                }
                            }.GetNewClosure()

                            # --- GÉNÉRATION UI ---

                            # 1. OPTIONAL FOLDER
                            $optPanel = New-Object System.Windows.Controls.StackPanel
                            $optPanel.Margin = [System.Windows.Thickness]::new(0, 0, 0, 20)
                            
                            $optLabel = New-Object System.Windows.Controls.TextBlock
                            $optLabel.Text = Get-AppText "sp_deploy.opt_folder"
                            $optLabel.FontWeight = "SemiBold"
                            $optLabel.Margin = [System.Windows.Thickness]::new(0, 0, 0, 5)
                            $optPanel.Children.Add($optLabel)
                            
                            $optTxt = New-Object System.Windows.Controls.TextBox
                            $optTxt.Name = "Field_OptionalSubFolder"
                            $optTxt.Tag = "OptionalSubFolder"
                            $optTxt.Width = 300
                            $optTxt.HorizontalAlignment = "Left"
                            $optTxt.Style = $Window.FindResource("StandardTextBoxStyle")
                            $optTxt.Add_TextChanged($UpdatePreviewAction)
                            $optPanel.Children.Add($optTxt)
                            
                            $Ctrl.DynamicFormPanel.Children.Add($optPanel)

                            # 2. DYNAMIC FORM (Horizontal Scroll)
                            $scroll = New-Object System.Windows.Controls.ScrollViewer
                            $scroll.HorizontalScrollBarVisibility = "Auto"
                            $scroll.VerticalScrollBarVisibility = "Disabled"
                            $scroll.Margin = [System.Windows.Thickness]::new(0, 0, 0, 20)
                            
                            $dynamicStack = New-Object System.Windows.Controls.StackPanel
                            $dynamicStack.Orientation = "Horizontal"
                            $dynamicStack.Tag = "FormDynamicStack" # TAG CRITIQUE POUR LE DEBUG
                            $scroll.Content = $dynamicStack

                            # Helper pour nettoyer les noms
                            function Get-SanitizedName { param($n) return $n -replace '[^a-zA-Z0-9_]', '' }

                            foreach ($elem in $layout) {
                                # Détermination Largeur
                                $width = 200 # Default
                                if ($elem.Width -and $elem.Width -match '^\d+$') { $width = [double]$elem.Width }
                            
                                # Control vs Label (Separator)
                                if ($elem.Type -eq "Label") {
                                    # Séparateur Visuel (ex: -Tr_)
                                    $t = New-Object System.Windows.Controls.TextBlock
                                    $t.Text = $elem.Content
                                    $t.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#00AEEF") # Bleu Style
                                    $t.FontWeight = "Bold"
                                    $t.VerticalAlignment = "Center"
                                    $t.Margin = [System.Windows.Thickness]::new(5, 0, 5, 0)
                                    $dynamicStack.Children.Add($t)
                                }
                                elseif ($elem.Type -eq "TextBox") {
                                    $cleanName = Get-SanitizedName -n "Field_$($elem.Name)"
                                    $t = New-Object System.Windows.Controls.TextBox
                                    $t.Name = $cleanName 
                                    $t.Tag = $elem.Name
                                    $t.Text = $elem.DefaultValue
                                    $t.Width = $width 
                                    $t.VerticalAlignment = "Center"
                                    $t.Style = $Window.FindResource("StandardTextBoxStyle")
                                    if ($elem.IsUppercase) { $t.CharacterCasing = [System.Windows.Controls.CharacterCasing]::Upper }
                                    
                                    $t.Add_TextChanged($UpdatePreviewAction) 
                                    $dynamicStack.Children.Add($t)
                                }
                                elseif ($elem.Type -eq "ComboBox") {
                                    $cleanName = Get-SanitizedName -n "Field_$($elem.Name)"
                                    $c = New-Object System.Windows.Controls.ComboBox
                                    $c.Name = $cleanName
                                    $c.Tag = $elem.Name
                                    $c.Width = $width
                                    $c.VerticalAlignment = "Center"
                                    $c.ItemsSource = $elem.Options
                                    $c.Style = $Window.FindResource("StandardComboBoxStyle")
                                    if ($elem.DefaultValue -and $elem.Options -contains $elem.DefaultValue) { $c.SelectedItem = $elem.DefaultValue }
                                    else { $c.SelectedIndex = 0 }
                                    
                                    $c.Add_SelectionChanged($UpdatePreviewAction)
                                    $dynamicStack.Children.Add($c)
                                }
                            }
                            
                            $Ctrl.DynamicFormPanel.Children.Add($scroll)
                            
                            # 3. PREVIEW (Styled)
                            $previewPanel = New-Object System.Windows.Controls.StackPanel
                            $previewPanel.Orientation = "Horizontal"
                            $previewPanel.Margin = [System.Windows.Thickness]::new(0, 10, 0, 0)
                            
                            $pLabel = New-Object System.Windows.Controls.TextBlock
                            $pLabel.Text = Get-AppText "sp_deploy.preview_label"
                            $pLabel.FontWeight = "SemiBold"
                            $pLabel.VerticalAlignment = "Center"
                            $pLabel.Margin = [System.Windows.Thickness]::new(0, 0, 10, 0)
                            $previewPanel.Children.Add($pLabel)
                            
                            # Border Container
                            $pBorder = New-Object System.Windows.Controls.Border
                            $pBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#F3F3F3")
                            $pBorder.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E0E0E0")
                            $pBorder.BorderThickness = [System.Windows.Thickness]::new(1)
                            $pBorder.CornerRadius = [System.Windows.CornerRadius]::new(4)
                            $pBorder.Padding = [System.Windows.Thickness]::new(10, 5, 10, 5)
                            $pBorder.HorizontalAlignment = "Stretch"
                            
                            $pVal = New-Object System.Windows.Controls.TextBlock
                            $pVal.Tag = "PreviewText" 
                            $pVal.Text = "..."
                            $pVal.FontWeight = "SemiBold"
                            $pVal.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#00AEEF") # Bleu
                            
                            $pBorder.Child = $pVal
                            $previewPanel.Children.Add($pBorder)
                            
                            # Update Ref
                            $Ctrl.FolderNamePreview = $pVal 
                            
                            $Ctrl.DynamicFormPanel.Children.Add($previewPanel)
                        
                            # Init Preview
                            $UpdatePreviewAction.Invoke($Ctrl.DynamicFormPanel, $null)

                            $Ctrl.BtnDeploy.IsEnabled = $true
                        }
                        else {
                            $err = New-Object System.Windows.Controls.TextBlock
                            $err.Text = "Règle de nommage '$($cfg.TargetFolder)' introuvable."
                            $err.Foreground = [System.Windows.Media.Brushes]::Red
                            if ($Ctrl.DynamicFormPanel) { $Ctrl.DynamicFormPanel.Children.Add($err) }
                        }
                    }
                    catch {
                        & $Log "Erreur génération formulaire : $($_.Exception.Message)" "Error"
                    }
                }
                else {
                    # Pas de dossier cible dynamique (Racine ?)
                    $info = New-Object System.Windows.Controls.TextBlock
                    $info.Text = "Aucun dossier dynamique configuré. Déploiement à la racine de la bibliothèque."
                    if ($Ctrl.DynamicFormPanel) { $Ctrl.DynamicFormPanel.Children.Add($info) }
                    if ($Ctrl.BtnDeploy) { $Ctrl.BtnDeploy.IsEnabled = $true }
                }

            }.GetNewClosure())
    }

    # 4. ACTION DEPLOYER
    if ($Ctrl.BtnDeploy) {
        $Ctrl.BtnDeploy.Add_Click({
                $btn = $Ctrl.BtnDeploy
                $logBox = $Ctrl.LogBox
                $btnOpen = $Ctrl.BtnOpen
                $cfg = $Ctrl.ListBox.SelectedItem
                if (-not $cfg) { return }

                # 1. Récupération des données (pour validation)
                $formData = @{}
                
                function Get-FormDataRecursive {
                    param($root)
                    $data = @{}
                    if ($root -is [System.Windows.Controls.Panel]) {
                        foreach ($child in $root.Children) {
                            $childData = Get-FormDataRecursive -root $child
                            foreach ($k in $childData.Keys) { $data[$k] = $childData[$k] }
                        }
                    }
                    elseif ($root -is [System.Windows.Controls.ContentControl] -and $root.Content -is [System.Windows.UIElement]) {
                        $childData = Get-FormDataRecursive -root $root.Content
                        foreach ($k in $childData.Keys) { $data[$k] = $childData[$k] }
                    }
                    elseif ($root -is [System.Windows.Controls.Decorator]) {
                        $childData = Get-FormDataRecursive -root $root.Child
                        foreach ($k in $childData.Keys) { $data[$k] = $childData[$k] }
                    }
                    
                    if ($root -is [System.Windows.UIElement] -and $root.Tag) {
                        $val = $null
                        if ($root -is [System.Windows.Controls.TextBox]) { $val = $root.Text }
                        elseif ($root -is [System.Windows.Controls.ComboBox]) { $val = $root.SelectedItem }
                        if ($val) { $data[$root.Tag] = $val }
                    }
                    return $data
                }
                
                $formData = Get-FormDataRecursive -root $Ctrl.DynamicFormPanel

                # 2. Validation Formulaire Vide (Warning)
                $targetRule = $null
                if ($cfg.TargetFolder) {
                    $rules = Get-AppNamingRules
                    $targetRule = $rules | Where-Object { $_.RuleId -eq $cfg.TargetFolder } | Select-Object -First 1
                   
                    if ($targetRule) {
                        $layout = ($targetRule.DefinitionJson | ConvertFrom-Json).Layout
                       
                        $hasEmptyField = $false
                       
                        foreach ($elem in $layout) {
                            if ($elem.Type -ne "Label") {
                                if ([string]::IsNullOrWhiteSpace($formData[$elem.Name])) {
                                    $hasEmptyField = $true
                                }
                            }
                        }
                       
                        # Si au moins un champ est vide
                        if ($hasEmptyField) {
                            $msg = "Le formulaire n'est pas complètement renseigné.`nCertaines parties du nom du dossier seront manquantes.`n`nVoulez-vous tout de même lancer le déploiement ?"
                            $res = [System.Windows.MessageBox]::Show($msg, "Attention", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
                            if ($res -eq 'No') { return }
                        }
                    }
                }

                # Start Actions
                if ($btnOpen) { $btnOpen.IsEnabled = $false }
                $btn.IsEnabled = $false
                & $Log (Get-AppText "sp_deploy.log_deploy_prep") "Info"

                # 3. Construction Nom Dossier
                $folderName = ""
                if ($targetRule) {
                    $builtName = ""
                    # Layout already parsed above inside targetRule check, but need to re-parse or store?
                    # $layout variable from above might persist? 
                    # PowerShell Scoping: Yes, $layout defined in 'if' blocks persists in function scope.
                    # But safest to re-parse or use carefully.
                    $layout = ($targetRule.DefinitionJson | ConvertFrom-Json).Layout
                    foreach ($elem in $layout) {
                        if ($elem.Type -eq "Label") { $builtName += $elem.Content }
                        elseif ($formData[$elem.Name]) { $builtName += $formData[$elem.Name] }
                    }
                    $folderName = $builtName
                }
                
                # Ajout Sous-Dossier Optionnel
                $optSubFolder = $null
                # On l'a déjà récupéré dans formData si le Tag est bon !
                if ($formData.ContainsKey("OptionalSubFolder")) {
                    $optSubFolder = $formData["OptionalSubFolder"]
                }
                
                if (-not [string]::IsNullOrWhiteSpace($optSubFolder)) {
                    # Si folderName est vide (racine), on utilise juste le subfolder, sinon on join
                    if ([string]::IsNullOrWhiteSpace($folderName)) {
                        $folderName = $optSubFolder
                    }
                    else {
                        $folderName = "$optSubFolder/$folderName"
                    }
                }

                & $Log "Cible : $($cfg.SiteUrl) / $($cfg.LibraryName) / $folderName" "Info"

                # 3. Lancement JOB
                $jobArgs = @{
                    ModPath       = Join-Path $Global:ProjectRoot "Modules\Toolbox.SharePoint"
                    Thumb         = $Global:AppConfig.azure.certThumbprint
                    ClientId      = $Global:AppConfig.azure.authentication.userAuth.appId
                    Tenant        = $Global:AppConfig.azure.tenantName
                    TargetUrl     = $cfg.SiteUrl
                    LibName       = $cfg.LibraryName
                    LibRelUrl     = $cfg.TargetFolderPath # Important ! (ServerRelativeUrl de la racine cible)
                    FolderName    = $folderName 
                    StructureJson = ($null) # Il faut charger le TemplateId
                    TemplateId    = $cfg.TemplateId
                }

                # Chargement Structure JSON
                $tpl = Get-AppSPTemplates | Where-Object { $_.TemplateId -eq $cfg.TemplateId } | Select-Object -First 1
                if ($tpl) { 
                    $jobArgs.StructureJson = $tpl.StructureJson 
                }
                else {
                    & $Log "Erreur : Modèle '$($cfg.TemplateId)' introuvable." "Error"; $Ctrl.BtnDeploy.IsEnabled = $true; return
                }

                # Start Job
                $job = Start-Job -ScriptBlock {
                    param($ArgsMap)
                    Import-Module $ArgsMap.ModPath -Force
                    try {
                        New-AppSPStructure `
                            -TargetSiteUrl $ArgsMap.TargetUrl `
                            -TargetLibraryName $ArgsMap.LibName `
                            -RootFolderName $ArgsMap.FolderName `
                            -StructureJson $ArgsMap.StructureJson `
                            -ClientId $ArgsMap.ClientId `
                            -Thumbprint $ArgsMap.Thumb `
                            -TenantName $ArgsMap.Tenant `
                            -TargetFolderUrl $ArgsMap.LibRelUrl
                    }
                    catch { throw $_ }
                } -ArgumentList $jobArgs

                # Timer Monitor
                $timer = New-Object System.Windows.Threading.DispatcherTimer
                $timer.Interval = [TimeSpan]::FromMilliseconds(500)
            
                $timerBlock = {
                    $newItems = Receive-Job -Job $job
                    foreach ($item in $newItems) {
                        if ($item -is [string]) { 
                            $parts = $item -split '\|', 2; 
                            $msg = if ($parts.Count -eq 2) { $parts[1] } else { $item }
                            Write-AppLog -Message $msg -Level Info -RichTextBox $logBox
                        }
                        elseif ($item.LogType -eq 'AppLog') {
                            Write-AppLog -Message $item.Message -Level $item.Level -RichTextBox $logBox
                        }
                    }

                    if ($job.State -ne 'Running') {
                        $timer.Stop()
                        if ($job.State -eq 'Failed') {
                            Write-AppLog -Message "Erreur critique : $($job.ChildJobs[0].Error)" -Level Error -RichTextBox $logBox
                        }
                        else {
                            # Log handled by Job
                            if ($btnOpen) {
                                try {
                                    $u = [Uri]$cfg.SiteUrl
                                    $base = $u.GetLeftPart([System.UriPartial]::Authority)
                                    $dest = "$base$($jobArgs.LibRelUrl)/$folderName"
                                    $btnOpen.Tag = $dest
                                    $btnOpen.IsEnabled = $true
                                }
                                catch {}
                            }
                        }
                        $btn.IsEnabled = $true
                    }
                }.GetNewClosure()

                $timer.Add_Tick($timerBlock)
                $timer.Start()

            }.GetNewClosure())
    }

    # 5. ACTION OUVRIR
    if ($Ctrl.BtnOpen) {
        $Ctrl.BtnOpen.Add_Click({
                if ($this.Tag) { Start-Process $this.Tag }
            })
    }
}
