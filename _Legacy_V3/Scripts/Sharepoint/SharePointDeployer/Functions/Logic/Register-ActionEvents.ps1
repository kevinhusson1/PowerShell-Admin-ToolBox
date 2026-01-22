<#
.SYNOPSIS
    Gère les actions principales : Déploiement et Ouverture.

.DESCRIPTION
    Câble le bouton "Déployer" et "Ouvrir".
    Valide le formulaire avant lancement.
    Lance le Job asynchrone (Start-Job) qui exécute New-AppSPStructure.
    Instancie un DispatcherTimer pour monitorer les logs du Job et mettre à jour la RichTextBox en temps réel.
    Gère la localisation du context Job via passage de paramètres Arguments.

.PARAMETER Ctrl
    Hashtable contenant les contrôles UI.

.PARAMETER Window
    Fenêtre parente.
#>
function Register-ActionEvents {
    param(
        [hashtable]$Ctrl,
        [System.Windows.Window]$Window
    )

    # Helper Log local
    $Log = { 
        param($msg, $level = "Info") 
        if ($Ctrl.LogBox) { Write-AppLog -Message $msg -Level $level -RichTextBox $Ctrl.LogBox }
    }.GetNewClosure()

    # Helper Localisation
    $Loc = { param($k) if (Get-Command Get-AppLocalizedString -ErrorAction SilentlyContinue) { Get-AppLocalizedString -Key $k } else { $k } }.GetNewClosure()

    # 4. ACTION DEPLOYER
    if ($Ctrl.BtnDeploy) {
        $Ctrl.BtnDeploy.Add_Click({
                $btn = $Ctrl.BtnDeploy
                $logBox = $Ctrl.LogBox
                $btnOpen = $Ctrl.BtnOpen
                $cfg = $Ctrl.ListBox.SelectedItem
                if (-not $cfg) { return }

                # 1. Récupération des données
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
                & $Log (& $Loc "sp_deploy.log_deploy_prep") "Info"

                # 3. Construction Nom Dossier
                $folderName = ""
                if ($targetRule) {
                    $builtName = ""
                    $layout = ($targetRule.DefinitionJson | ConvertFrom-Json).Layout
                    foreach ($elem in $layout) {
                        if ($elem.Type -eq "Label") { $builtName += $elem.Content }
                        elseif ($formData[$elem.Name]) { $builtName += $formData[$elem.Name] }
                    }
                    $folderName = $builtName
                }
                
                # Ajout Sous-Dossier Optionnel
                $optSubFolder = $null
                if ($formData.ContainsKey("OptionalSubFolder")) {
                    $optSubFolder = $formData["OptionalSubFolder"]
                }
                
                if (-not [string]::IsNullOrWhiteSpace($optSubFolder)) {
                    if ([string]::IsNullOrWhiteSpace($folderName)) { $folderName = $optSubFolder }
                    else { $folderName = "$optSubFolder/$folderName" }
                }

                & $Log "Cible : $($cfg.SiteUrl) / $($cfg.LibraryName) / $folderName" "Info"

                # 3. Lancement JOB
                # Définition du fichier de langue pour le Job
                $locFile = Join-Path $Global:ProjectRoot "Scripts\Sharepoint\SharePointDeployer\Localization\$($Global:AppConfig.defaultLanguage).json"

                $jobArgs = @{
                    ModPath       = Join-Path $Global:ProjectRoot "Modules" # Racine des modules
                    Thumb         = $Global:AppConfig.azure.certThumbprint
                    ClientId      = $Global:AppConfig.azure.authentication.userAuth.appId
                    Tenant        = $Global:AppConfig.azure.tenantName
                    TargetUrl     = $cfg.SiteUrl
                    LibName       = $cfg.LibraryName
                    LibRelUrl     = $cfg.TargetFolderPath 
                    FolderName    = $folderName 
                    StructureJson = ($null)
                    TemplateId    = $cfg.TemplateId
                    LocFilePath   = $locFile
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
                    
                    # Configuration Environnement Job
                    $env:PSModulePath = "$($ArgsMap.ModPath);$($env:PSModulePath)"
                    
                    # Import Modules
                    Import-Module "Localization" -Force
                    Import-Module "Toolbox.SharePoint" -Force
                    
                    # Chargement Langue
                    if ($ArgsMap.LocFilePath -and (Test-Path $ArgsMap.LocFilePath)) {
                        Add-AppLocalizationSource -FilePath $ArgsMap.LocFilePath
                    }

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
                            if ($btnOpen) {
                                try {
                                    $u = [Uri]$cfg.SiteUrl
                                    $base = $u.GetLeftPart([System.UriPartial]::Authority)
                                    $dest = "$base$($jobArgs.LibRelUrl)/$folderName"
                                    # Fix: LibRelUrl might or might not have leading slash. Usually "Shared Documents" is without.
                                    # PnP ensures paths. 
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
