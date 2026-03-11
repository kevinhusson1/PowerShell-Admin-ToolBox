# Scripts/Sharepoint/SharepointBuilderV2/Functions/Logic/Invoke-AppSPDeployExecute.ps1

<#
.SYNOPSIS
    Orchestrateur d'exécution du déploiement SharePoint (Job & Timer).
.DESCRIPTION
    Prépare les arguments du Job, lance l'exécution en arrière-plan et configure 
    le Timer WPF pour assurer le suivi en temps réel dans l'interface.
#>
function Global:Invoke-AppSPDeployExecute {
    param(
        [hashtable]$Ctrl,
        [System.Windows.Window]$Window
    )

    $v = "v4.18"
    Write-Verbose "[$v] Lancement de l'exécution du déploiement..."

    $Ctrl.BtnDeploy.IsEnabled = $false
    $Ctrl.ProgressBar.IsIndeterminate = $true
    $Ctrl.TxtStatus.Text = "Déploiement en cours..."

    Write-AppLog -Message "Démarrage déploiement..." -Level Info -RichTextBox $Ctrl.LogBox

    # --- 1. PRÉPARATION DES DONNÉES ---
    $folderNameParam = if ($Ctrl.ChkCreateFolder.IsChecked) { $Ctrl.TxtPreview.Text } else { "" }

    $formValues = @{}
    $rootMetadata = @{}
    
    if ($Ctrl.PanelForm -and $Ctrl.PanelForm.Children) {
        foreach ($c in $Ctrl.PanelForm.Children) {
            $val = $null
            $key = $null
            $isMeta = $false
            
            if ($c.Tag -is [System.Collections.IDictionary]) {
                $key = $c.Tag.Key
                $isMeta = $c.Tag.IsMeta
                if ($c -is [System.Windows.Controls.TextBox]) { $val = $c.Text }
                elseif ($c -is [System.Windows.Controls.ComboBox]) { $val = $c.SelectedItem }
                elseif ($c -is [System.Windows.Controls.TextBlock]) { $val = $c.Text }
                
                if ($key) {
                    $formValues[$key] = $val
                    if ($isMeta) { 
                        $metaKey = if ($c.Tag.TargetColumn) { $c.Tag.TargetColumn } else { $key }
                        $rootMetadata[$metaKey] = $val 
                    }
                }
            }
        }
    }
    
    if ($Ctrl.ChkApplyMeta.IsChecked -eq $false) { $rootMetadata.Clear() }

    # --- 2. TRACKING ---
    $trackTemplateId = if ($Ctrl.CbTemplates.SelectedItem) { $Ctrl.CbTemplates.SelectedItem.TemplateId } else { "UNKNOWN" }
    $trackRuleId = if ($Ctrl.CbFolderTemplates.SelectedItem) { $Ctrl.CbFolderTemplates.SelectedItem.RuleId } else { "" }
    $trackRuleJson = if ($Ctrl.CbFolderTemplates.SelectedItem) { $Ctrl.CbFolderTemplates.SelectedItem.DefinitionJson } else { "" }
    $trackConfig = if ($Ctrl.CbDeployConfigs.SelectedItem) { $Ctrl.CbDeployConfigs.SelectedItem.ConfigName } else { "" }
    
    $trackUser = "admin"
    if ($Global:AppAzureActiveUser -and $Global:AppAzureActiveUser.DisplayName) { $trackUser = $Global:AppAzureActiveUser.DisplayName }
    elseif ($env:USERNAME) { $trackUser = $env:USERNAME }
    
    $trackingInfo = @{
        TemplateId         = $trackTemplateId
        TemplateVersion    = [DateTime]::Now.ToString("yyyy-MM-dd HH:mm:ss")
        ConfigName         = $trackConfig
        NamingRuleId       = $trackRuleId
        FormDefinitionJson = $trackRuleJson
        DeployedBy         = $trackUser
        FormValues         = $formValues
    }

    # --- 3. SCHEMA ---
    $folderSchemaJson = $null
    $folderSchemaName = $null
    if ($Ctrl.CbFolderSchema -and $Ctrl.CbFolderSchema.SelectedItem -and $Ctrl.CbFolderSchema.SelectedItem.Tag) {
        $folderSchemaJson = $Ctrl.CbFolderSchema.SelectedItem.Tag.ColumnsJson
        $folderSchemaName = $Ctrl.CbFolderSchema.SelectedItem.Tag.DisplayName
    }

    # --- 4. CONFIGURATION JOB ---
    $lang = if ($Global:AppConfig.defaultLanguage) { $Global:AppConfig.defaultLanguage } else { "fr-FR" }
    $locFile = Join-Path $Global:ProjectRoot "Scripts\Sharepoint\SharePointBuilder\Localization\$lang.json"

    $jobArgs = @{
        ModPath          = Join-Path $Global:ProjectRoot "Modules"
        Thumb            = $Global:AppConfig.azure.certThumbprint
        ClientId         = $Global:AppConfig.azure.authentication.userAuth.appId
        Tenant           = $Global:AppConfig.azure.tenantName
        TargetUrl        = $Ctrl.CbSites.SelectedItem.Url
        LibName          = $Ctrl.CbLibs.SelectedItem.Title
        LibRelUrl        = if ($Global:SelectedTargetFolder) { $Global:SelectedTargetFolder.ServerRelativeUrl } else { $Ctrl.CbLibs.SelectedItem.RootFolder.ServerRelativeUrl }
        TargetItemId     = if ($Global:SelectedTargetFolder) { $Global:SelectedTargetFolder.ItemId } else { "root" }
        FolderName       = $folderNameParam 
        StructureJson    = ($Ctrl.CbTemplates.SelectedItem.StructureJson)
        LocFilePath      = $locFile
        FormValues       = $formValues
        RootMetadata     = $rootMetadata
        TrackingInfo     = $trackingInfo
        FolderSchemaJson = $folderSchemaJson
        FolderSchemaName = $folderSchemaName
    }

    # --- 5. EXECUTION JOB ---
    $job = Start-Job -ScriptBlock {
        param($ArgsMap)
        $env:PSModulePath = "$($ArgsMap.ModPath);$($env:PSModulePath)"
        Import-Module "Localization", "Toolbox.SharePoint" -Force
        if ($ArgsMap.LocFilePath -and (Test-Path $ArgsMap.LocFilePath)) { Add-AppLocalizationSource -FilePath $ArgsMap.LocFilePath }

        try {
            New-AppSPStructure `
                -TargetSiteUrl $ArgsMap.TargetUrl `
                -TargetLibraryName $ArgsMap.LibName `
                -RootFolderName $ArgsMap.FolderName `
                -StructureJson $ArgsMap.StructureJson `
                -ClientId $ArgsMap.ClientId `
                -Thumbprint $ArgsMap.Thumb `
                -TenantName $ArgsMap.Tenant `
                -TargetFolderUrl $ArgsMap.LibRelUrl `
                -TargetFolderItemId $ArgsMap.TargetItemId `
                -FormValues $ArgsMap.FormValues `
                -RootMetadata $ArgsMap.RootMetadata `
                -TrackingInfo $ArgsMap.TrackingInfo `
                -FolderSchemaJson $ArgsMap.FolderSchemaJson `
                -FolderSchemaName $ArgsMap.FolderSchemaName

            # Le final HashTable $result est retourné par New-AppSPStructure dans le pipeline.
        }
        catch { throw $_ }
    } -ArgumentList $jobArgs

    # --- 6. SUIVI VIA TIMER ---
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(500)
    $SharedState = @{ FinalResult = $null }

    $timer.Tag = @{
        Job         = $job
        Window      = $Window
        JobArgs     = $jobArgs
        SharedState = $SharedState
    }

    $timerBlock = {
        param($sender, $e)
        try {
            $ctx = $sender.Tag
            $job = $ctx.Job
            $win = $ctx.Window
            $jobArgs = $ctx.JobArgs
            $SharedState = $ctx.SharedState

            function Local-FindNode($w, $name) {
                $n = [System.Windows.LogicalTreeHelper]::FindLogicalNode($w, $name)
                if ($n -is [array]) { return $n[0] }
                return $n
            }

            $fLog = Local-FindNode $win "LogRichTextBox"
            $fProg = Local-FindNode $win "MainProgressBar"
            $fStat = Local-FindNode $win "ProgressStatusText"
            $fBtn = Local-FindNode $win "DeployButton"
            $fCopy = Local-FindNode $win "CopyUrlButton"
            $fOpen = Local-FindNode $win "OpenUrlButton"

            $newItems = Receive-Job -Job $job
            foreach ($item in $newItems) {
                if ($item.PSObject.Properties['LogType'] -and $item.LogType -eq 'AppLog') {
                    if ($fLog) { Write-AppLog -Message $item.Message -Level $item.Level -RichTextBox $fLog }
                    
                    # Mise à jour de la barre de progression selon la phase en cours (V2 API Graph)
                    $msgStr = $item.Message
                    if ($fProg -and $fStat -and $msgStr -match "^Phase ") {
                        if ($fProg.IsIndeterminate) { $fProg.IsIndeterminate = $false }
                        if ($msgStr -match "Phase 1") { $fProg.Value = 20; $fStat.Text = "Création des dossiers..." }
                        elseif ($msgStr -match "Phase 2") { $fProg.Value = 40; $fStat.Text = "Application des permissions..." }
                        elseif ($msgStr -match "Phase 3") { $fProg.Value = 60; $fStat.Text = "Application des métadonnées..." }
                        elseif ($msgStr -match "Phase 4") { $fProg.Value = 80; $fStat.Text = "Création des liens..." }
                        elseif ($msgStr -match "Phase 5") { $fProg.Value = 95; $fStat.Text = "Création des fichiers..." }
                    }
                    elseif ($fProg -and $fStat -and $msgStr -match "Génér.*state\.json") {
                        $fProg.Value = 99; $fStat.Text = "Sauvegarde de la session (In-Situ)..."
                    }
                }
                elseif ($item -is [string]) {
                    $parts = $item -split '\|', 2
                    $lvl = if ($parts.Count -eq 2) { $parts[0] } else { "INFO" }
                    $msg = if ($parts.Count -eq 2) { $parts[1] } else { $item }
                    if (-not [string]::IsNullOrWhiteSpace($msg)) {
                        $color = switch ($lvl) { "DEBUG" { "Debug" } "INFO" { "Info" } "WARNING" { "Warning" } "ERROR" { "Error" } "SUCCESS" { "Success" } Default { "Info" } }
                        if ($fLog) { Write-AppLog -Message $msg -Level $color -RichTextBox $fLog }
                    }
                }
                elseif ($item -is [System.Collections.IDictionary] -or $item -is [PSCustomObject]) {
                    if (-not $item.PSObject.Properties['LogType']) { $SharedState.FinalResult = $item }
                }
            }

            if ($job.State -ne 'Running') {
                $sender.Stop()
                $finalRes = $SharedState.FinalResult
                if ($fProg) { $fProg.IsIndeterminate = $false; $fProg.Value = 100 }

                if ($job.State -eq 'Failed') {
                    $err = $job.ChildJobs[0].Error
                    if ($fLog) { Write-AppLog -Message "CRASH JOB : $err" -Level Error -RichTextBox $fLog }
                    if ($fStat) { $fStat.Text = "Erreur critique." }
                    if ($fBtn) { $fBtn.IsEnabled = $true }
                } 
                else {
                    $success = ($finalRes -and $finalRes.Success)
                    if ($success) {
                        if ($fStat) { $fStat.Text = "Déploiement réussi !" }
                        
                        # Récupération de l'URL finale via le résultat du Job (v4.24)
                        $finalUrl = $finalRes.FinalUrl
                        if ([string]::IsNullOrWhiteSpace($finalUrl)) {
                            # Fallback manuel si non fourni (ex: pas de racine créée)
                            $uriSite = [Uri]$jobArgs.TargetUrl
                            $rootHost = "$($uriSite.Scheme)://$($uriSite.Host)"
                            $pathSuffix = if ($jobArgs.FolderName) { "/$($jobArgs.FolderName)" } else { "" }
                            $finalUrl = "$rootHost$($jobArgs.LibRelUrl)$pathSuffix"
                        }
                        
                        if ($fCopy) { $fCopy.IsEnabled = $true; $fCopy.Tag = $finalUrl }
                        if ($fOpen) { $fOpen.IsEnabled = $true }
                    } 
                    else {
                        if ($fStat) { $fStat.Text = "Terminé avec erreurs." }
                        if ($fBtn) { $fBtn.IsEnabled = $true }
                    }
                }
            }
        }
        catch {
            $sender.Stop()
            Write-Warning "CRASH TIMER DEPLOIEMENT: $($_.Exception.Message)"
        }
    }

    $timer.Add_Tick($timerBlock)
    $timer.Start()
}
