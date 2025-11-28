# Scripts/SharePoint/SharePointBuilder/Functions/Initialize-BuilderLogic.ps1

function Initialize-BuilderLogic {
    param($Context)

    $Window = $Context.Window
    
    # ==============================================================================
    # 1. DÉFINITION DES HELPERS (VARIABLES LOCALES POUR CLOSURE)
    # ==============================================================================
    
    # On définit la logique de preview ici, DANS la fonction, pour qu'elle soit capturée.
    $UpdatePreview = {
        param($Panel, $Output)
        try {
            $name = ""
            if ($Panel -and $Panel.Children) {
                foreach ($ctrl in $Panel.Children) {
                    if ($ctrl -is [System.Windows.Controls.TextBox]) { $name += $ctrl.Text }
                    elseif ($ctrl -is [System.Windows.Controls.TextBlock]) { $name += $ctrl.Text }
                    elseif ($ctrl -is [System.Windows.Controls.ComboBox]) { $name += $ctrl.SelectedItem }
                }
            }
            if ($Output) { $Output.Text = $name }
        } catch {
            Write-Verbose "Erreur Preview : $_"
        }
    }

    # ==============================================================================
    # 2. RÉCUPÉRATION DES CONTRÔLES
    # ==============================================================================
    $cbSites = $Window.FindName("SiteComboBox")
    $cbLibs  = $Window.FindName("LibraryComboBox")
    $cbTpl   = $Window.FindName("TemplateComboBox")
    $panelForm = $Window.FindName("DynamicFormPanel")
    $txtPreview = $Window.FindName("FolderNamePreviewText")
    $txtDesc = $Window.FindName("TemplateDescText")

    # ==============================================================================
    # 3. CHARGEMENT DES DONNÉES (TEMPLATES)
    # ==============================================================================
    try {
        $templates = @(Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query "SELECT * FROM sp_templates ORDER BY DisplayName")
        $cbTpl.ItemsSource = $templates
        $cbTpl.DisplayMemberPath = "DisplayName"
    } catch {
        Write-Warning "Erreur chargement templates : $_"
    }

    # ==============================================================================
    # 4. DÉFINITION DES ÉVÉNEMENTS
    # ==============================================================================

    # --- A. Sélection Template ---
    $cbTpl.Add_SelectionChanged({
        try {
            $selectedTpl = $cbTpl.SelectedItem
            if (-not $selectedTpl) { return }

            $txtDesc.Text = $selectedTpl.Description
            $panelForm.Children.Clear()

            if ($selectedTpl.NamingRuleId) {
                $rule = Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query "SELECT * FROM sp_naming_rules WHERE RuleId = '$($selectedTpl.NamingRuleId)'"
                
                if ($rule) {
                    $definition = $rule.DefinitionJson | ConvertFrom-Json
                    
                    foreach ($item in $definition.Layout) {
                        # Label
                        if ($item.Type -eq "Label") {
                            $lbl = New-Object System.Windows.Controls.TextBlock
                            $lbl.Text = $item.Content
                            $lbl.VerticalAlignment = "Center"; $lbl.Margin = "0,0,5,0"
                            $panelForm.Children.Add($lbl) | Out-Null
                        }
                        
                        # Gestion Valeur
                        $valueToUse = $item.DefaultValue
                        # Vérification stricte avant d'utiliser ContainsKey
                        if ($Context.AutoFormData -and -not [string]::IsNullOrWhiteSpace($item.Name)) {
                            if ($Context.AutoFormData.ContainsKey($item.Name)) {
                                $valueToUse = $Context.AutoFormData[$item.Name]
                            }
                        }

                        # TextBox
                        if ($item.Type -eq "TextBox") {
                            $txt = New-Object System.Windows.Controls.TextBox
                            $txt.Name = "Input_" + $item.Name
                            $txt.Text = $valueToUse
                            $txt.Width = 100; $txt.Style = $Window.FindResource("StandardTextBoxStyle"); $txt.Margin = "0,0,5,0"
                            
                            # Appel via & $UpdatePreview
                            $txt.Add_TextChanged({ & $UpdatePreview -Panel $panelForm -Output $txtPreview }.GetNewClosure())
                            $panelForm.Children.Add($txt) | Out-Null
                        }
                        # ComboBox
                        elseif ($item.Type -eq "ComboBox") {
                            $cb = New-Object System.Windows.Controls.ComboBox
                            $cb.Name = "Input_" + $item.Name
                            $cb.ItemsSource = $item.Options
                            $cb.Width = 120; $cb.Style = $Window.FindResource("StandardComboBoxStyle"); $cb.Margin = "0,0,5,0"
                            
                            if ($valueToUse -and $item.Options -contains $valueToUse) { $cb.SelectedItem = $valueToUse } 
                            else { $cb.SelectedIndex = 0 }
                            
                            # Appel via & $UpdatePreview
                            $cb.Add_SelectionChanged({ & $UpdatePreview -Panel $panelForm -Output $txtPreview }.GetNewClosure())
                            $panelForm.Children.Add($cb) | Out-Null
                        }
                    }
                    # Appel initial via & $UpdatePreview
                    & $UpdatePreview -Panel $panelForm -Output $txtPreview
                }
            }
        } catch {
            [System.Windows.MessageBox]::Show("Erreur interne Template : $_", "Erreur", "OK", "Error")
        }
    }.GetNewClosure())

    # --- B. Chargement Sites (Async Job) ---
    $cbSites.Add_DropDownOpened({
        try {
            # On ne charge que si vide et pas déjà en cours (Tag != Loading)
            if ($cbSites.Items.Count -eq 0 -and -not $cbSites.IsReadOnly -and ($cbSites.Tag -ne "Loading")) {
                
                $cbSites.Tag = "Loading"
                $cbSites.ItemsSource = @("Chargement des sites...")
                
                # Récupération sécurisée des variables
                $modulePath = Join-Path $Global:ProjectRoot "Modules\Toolbox.SharePoint"
                
                # Sécurisation Auth
                $appId = $null
                $tenantName = $null
                
                if ($Global:AppConfig -and $Global:AppConfig.azure) {
                    $appId = $Global:AppConfig.azure.authentication.userAuth.appId
                    $tenantName = $Global:AppConfig.azure.tenantName
                }

                # Fallback Tenant
                if ([string]::IsNullOrWhiteSpace($tenantName) -and $Global:AppAzureAuth.UserAuth.Connected) {
                     $parts = $Global:AppAzureAuth.UserAuth.UserPrincipalName.Split('@')
                     if ($parts[1] -eq "vosgelis.fr") { $tenantName = "vosgelis365" }
                     else { $tenantName = $parts[1].Split('.')[0] }
                }

                # Si pas d'auth, on arrête là pour éviter le crash
                if ([string]::IsNullOrWhiteSpace($appId) -or [string]::IsNullOrWhiteSpace($tenantName)) {
                    $cbSites.ItemsSource = @("Veuillez vous connecter d'abord")
                    $cbSites.Tag = $null
                    return
                }

                # Lancement Job
                $loadJob = Start-Job -ScriptBlock {
                    param($modPath, $tName, $cId)
                    try {
                        Import-Module PnP.PowerShell
                        Import-Module $modPath -Force
                        $url = "https://$tName.sharepoint.com"
                        Connect-PnPOnline -Url $url -ClientId $cId -Interactive -ErrorAction Stop
                        return Get-AppSPSites
                    } catch {
                        return @()
                    }
                } -ArgumentList $modulePath, $tenantName, $appId

                # Timer
                $timer = New-Object System.Windows.Threading.DispatcherTimer
                $timer.Interval = [TimeSpan]::FromMilliseconds(500)
                
                # On capture le Job ID car l'objet Job peut être perdu
                $jobId = $loadJob.Id
                
                $timer.Add_Tick({
                    try {
                        $j = Get-Job -Id $jobId -ErrorAction SilentlyContinue
                        if ($j -and $j.State -ne 'Running') {
                            $timer.Stop()
                            $sites = Receive-Job -Job $j -Wait -AutoRemoveJob
                            
                            if ($sites -and $sites.Count -gt 0) {
                                $cbSites.ItemsSource = $sites
                                $cbSites.DisplayMemberPath = "Title"
                            } else {
                                $cbSites.ItemsSource = @("Aucun site trouvé")
                            }
                            $cbSites.Tag = $null
                        }
                    } catch {
                        $timer.Stop()
                        $cbSites.Tag = $null
                    }
                }.GetNewClosure())
                
                $timer.Start()
            }
        } catch {
            [System.Windows.MessageBox]::Show("Erreur chargement sites : $_", "Erreur", "OK", "Error")
            $cbSites.Tag = $null
        }
    }.GetNewClosure())

    # --- C. Sélection Site -> Chargement Libs ---
    $cbSites.Add_SelectionChanged({
        try {
            $site = $cbSites.SelectedItem
            # Vérification de type pour ne pas traiter le string "Chargement..."
            if ($site -is [System.Management.Automation.PSCustomObject] -and $cbLibs.Items.Count -eq 0) {
                
                $cbLibs.ItemsSource = @("Chargement...")
                
                # Job simple pour les libs (copier/coller logique précédente simplifié)
                # Note: Dans un vrai projet on factoriserait cette logique de Job
                $libs = @(Get-AppSPLibraries -SiteUrl $site.Url) # Version synchrone rapide pour l'instant
                
                if ($libs.Count -gt 0) {
                    $cbLibs.ItemsSource = $libs
                    $cbLibs.DisplayMemberPath = "Title"
                } else {
                    $cbLibs.ItemsSource = @("Aucune bibliothèque")
                }
            }
        } catch {}
    }.GetNewClosure())

    # ==============================================================================
    # 5. EXÉCUTION AUTOPILOT
    # ==============================================================================
    
    # A. Template
    $targetTemplate = $null
    if ($Context.AutoTemplateId) {
        $targetTemplate = $templates | Where-Object { $_.TemplateId -eq $Context.AutoTemplateId } | Select-Object -First 1
    }
    if (-not $targetTemplate -and $Global:CurrentUserGroups) {
        foreach ($tpl in $templates) {
            if ($tpl.AutoSelectGroup -and $Global:CurrentUserGroups -contains $tpl.AutoSelectGroup) {
                $targetTemplate = $tpl; break 
            }
        }
    }
    if ($targetTemplate) { $cbTpl.SelectedItem = $targetTemplate }

    # B. Site/Lib
    if ($Context.AutoSiteUrl) {
        $dummySite = [PSCustomObject]@{ Title = "Site Ciblé (Autopilot)"; Url = $Context.AutoSiteUrl; Id = "Auto" }
        $cbSites.ItemsSource = @($dummySite)
        $cbSites.SelectedItem = $dummySite
        $cbSites.IsEnabled = $false 
        
        # On force les libs ici
        $libs = @(Get-AppSPLibraries -SiteUrl $Context.AutoSiteUrl)
        $cbLibs.ItemsSource = $libs
        $cbLibs.DisplayMemberPath = "Title"
        
        if ($Context.AutoLibraryName) {
            $targetLib = $libs | Where-Object { $_.Title -eq $Context.AutoLibraryName } | Select-Object -First 1
            if ($targetLib) {
                $cbLibs.SelectedItem = $targetLib
                $cbLibs.IsEnabled = $false
            }
        }
    }
}