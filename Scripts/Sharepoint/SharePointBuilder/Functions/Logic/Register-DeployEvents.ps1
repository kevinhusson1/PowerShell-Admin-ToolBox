# Scripts/SharePoint/SharePointBuilder/Functions/Logic/Register-DeployEvents.ps1

function Register-DeployEvents {
    param(
        [hashtable]$Ctrl,
        [System.Windows.Window]$Window
    )

    $Ctrl.BtnDeploy.Add_Click({
        # 1. UI Verrouillage
        $Ctrl.BtnDeploy.IsEnabled = $false
        $Ctrl.ProgressBar.IsIndeterminate = $true
        $Ctrl.TxtStatus.Text = "Déploiement en cours..."
        $Ctrl.LogBox.Document.Blocks.Clear() # On vide les logs précédents
        
        # 2. Récupération du niveau de log
        $cbLevel = $Window.FindName("LogLevelComboBox")
        $logLevel = "Normal"
        if ($cbLevel.SelectedItem) { $logLevel = $cbLevel.SelectedItem.Tag }
        
        Write-AppLog -Message "Démarrage déploiement (Niveau: $logLevel)..." -Level Info -RichTextBox $Ctrl.LogBox

        # 3. Arguments Job
        $jobArgs = @{
            ModPath       = Join-Path $Global:ProjectRoot "Modules\Toolbox.SharePoint"
            Thumb         = $Global:AppConfig.azure.certThumbprint
            ClientId      = $Global:AppConfig.azure.authentication.userAuth.appId
            Tenant        = $Global:AppConfig.azure.tenantName
            TargetUrl     = $Ctrl.CbSites.SelectedItem.Url
            LibName       = $Ctrl.CbLibs.SelectedItem.Title
            FolderName    = $Ctrl.TxtPreview.Text
            StructureJson = ($Ctrl.CbTemplates.SelectedItem.StructureJson)
        }

        # 4. Lancement Job
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
                    -TenantName $ArgsMap.Tenant
            } catch { throw $_ }
        } -ArgumentList $jobArgs

        # 5. Timer Surveillance
        $timer = New-Object System.Windows.Threading.DispatcherTimer
        $timer.Interval = [TimeSpan]::FromMilliseconds(500)
        
        $timerBlock = {
            if ($job.State -ne 'Running') {
                $timer.Stop()
                
                # Récupération sécurisée
                $fLog = $Window.FindName("LogRichTextBox")
                $fProg = $Window.FindName("MainProgressBar")
                $fStat = $Window.FindName("ProgressStatusText")
                $fBtn = $Window.FindName("DeployButton")

                $result = Receive-Job $job -Wait -AutoRemoveJob
                
                if ($fProg) { $fProg.IsIndeterminate = $false; $fProg.Value = 100 }
                if ($fBtn) { $fBtn.IsEnabled = $true }

                # Gestion Crash Job
                if ($job.State -eq 'Failed') {
                    $err = $job.ChildJobs[0].Error
                    if ($fLog) { Write-AppLog -Message "CRASH JOB : $err" -Level Error -RichTextBox $fLog }
                    if ($fStat) { $fStat.Text = "Erreur critique." }
                    return
                }

                # Gestion Résultat
                if ($result) {
                    # A. Affichage des Logs Filtrés
                    if ($result.Logs) {
                        foreach ($line in $result.Logs) {
                            # Format attendu : "LEVEL|Message"
                            $parts = $line -split '\|', 2
                            $lvl = if($parts.Count -eq 2){ $parts[0] } else { "INFO" }
                            $msg = if($parts.Count -eq 2){ $parts[1] } else { $line }

                            $show = $false
                            
                            # FILTRE LOGIQUE
                            switch ($logLevel) {
                                "Light"  { if ($lvl -in "SUCCESS", "ERROR", "WARNING") { $show = $true } }
                                "Normal" { if ($lvl -in "SUCCESS", "ERROR", "WARNING", "INFO") { $show = $true } }
                                "Hard"   { $show = $true } # Tout afficher (DEBUG inclus)
                            }

                            if ($show -and $fLog) {
                                # Mapping couleurs
                                $color = switch($lvl) {
                                    "DEBUG" { "Debug" }
                                    "INFO" { "Info" }
                                    "WARNING" { "Warning" }
                                    "ERROR" { "Error" }
                                    "SUCCESS" { "Success" }
                                    Default { "Info" }
                                }
                                Write-AppLog -Message $msg -Level $color -RichTextBox $fLog
                            }
                        }
                    }

                    # B. Statut Final
                    if ($fStat) { 
                        $fStat.Text = if ($result.Success) { "Terminé avec succès." } else { "Terminé avec erreurs." }
                    }
                }
            }
        }.GetNewClosure()

        $timer.Add_Tick($timerBlock)
        $timer.Start()

    }.GetNewClosure())
}