# Scripts/SharePoint/SharePointBuilder/Functions/Logic/Register-DeployEvents.ps1

function Register-DeployEvents {
    param(
        [hashtable]$Ctrl,
        [System.Windows.Window]$Window
    )

    $Ctrl.BtnDeploy.Add_Click({
            $Ctrl.BtnDeploy.IsEnabled = $false
            $Ctrl.ProgressBar.IsIndeterminate = $true
            $Ctrl.TxtStatus.Text = "Déploiement en cours..."
            $Ctrl.LogBox.Document.Blocks.Clear()
        
            $cbLevel = $Window.FindName("LogLevelComboBox")
            $logLevel = "Normal"
            if ($cbLevel.SelectedItem) { $logLevel = $cbLevel.SelectedItem.Tag }
        
            Write-AppLog -Message "Démarrage déploiement (Niveau: $logLevel)..." -Level Info -RichTextBox $Ctrl.LogBox

            # --- LOGIQUE CRITIQUE ---
            # Si on ne crée pas de dossier, on passe une chaîne vide pour le nom du dossier
            $folderNameParam = if ($Ctrl.ChkCreateFolder.IsChecked) { $Ctrl.TxtPreview.Text } else { "" }

            $jobArgs = @{
                ModPath       = Join-Path $Global:ProjectRoot "Modules\Toolbox.SharePoint"
                Thumb         = $Global:AppConfig.azure.certThumbprint
                ClientId      = $Global:AppConfig.azure.authentication.userAuth.appId
                Tenant        = $Global:AppConfig.azure.tenantName
                TargetUrl     = $Ctrl.CbSites.SelectedItem.Url
                LibName       = $Ctrl.CbLibs.SelectedItem.Title
                LibRelUrl     = $Ctrl.CbLibs.SelectedItem.RootFolder.ServerRelativeUrl
                FolderName    = $folderNameParam # <--- Utilisation de la variable conditionnelle
                StructureJson = ($Ctrl.CbTemplates.SelectedItem.StructureJson)
            }

            # ... (Reste du fichier identique au précédent, Job + Timer)
            # Copiez-collez le bloc Job + Timer de la réponse précédente, il est correct.
            # Juste s'assurer que $jobArgs utilise bien $folderNameParam
        
            # Pour être sûr, voici le bloc Job à remettre :
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
                }
                catch { throw $_ }
            } -ArgumentList $jobArgs
        
            # ... Timer ... (idem précédent)
            # N'oubliez pas de mettre à jour l'URL de copie si FolderName est vide
            # Dans le Timer, bloc Success :
            # $finalUrl = if ($jobArgs.FolderName) { "$rootHost$($jobArgs.LibRelUrl)/$($jobArgs.FolderName)" } else { "$rootHost$($jobArgs.LibRelUrl)" }

            # Je remets le Timer complet pour éviter les erreurs de copier-coller
            $timer = New-Object System.Windows.Threading.DispatcherTimer
            $timer.Interval = [TimeSpan]::FromMilliseconds(500)
        
            $timerBlock = {
                if ($job.State -ne 'Running') {
                    $timer.Stop()
                
                    $fLog = $Window.FindName("LogRichTextBox")
                    $fProg = $Window.FindName("MainProgressBar")
                    $fStat = $Window.FindName("ProgressStatusText")
                    $fBtn = $Window.FindName("DeployButton")
                    $fCopy = $Window.FindName("CopyUrlButton")
                    $fOpen = $Window.FindName("OpenUrlButton")

                    $result = Receive-Job $job -Wait -AutoRemoveJob
                
                    if ($fProg) { $fProg.IsIndeterminate = $false; $fProg.Value = 100 }

                    if ($job.State -eq 'Failed') {
                        $err = $job.ChildJobs[0].Error
                        if ($fLog) { Write-AppLog -Message "CRASH JOB : $err" -Level Error -RichTextBox $fLog }
                        if ($fStat) { $fStat.Text = "Erreur critique." }
                        if ($fBtn) { $fBtn.IsEnabled = $true }
                    } 
                    else {
                        if ($result.Success) {
                            if ($fStat) { $fStat.Text = "Déploiement réussi !" }
                            if ($fLog) { Write-AppLog -Message "Terminé avec succès." -Level Success -RichTextBox $fLog }
                        
                            # URL Finale
                            $uriSite = [Uri]$jobArgs.TargetUrl
                            $rootHost = "$($uriSite.Scheme)://$($uriSite.Host)"
                            # Si dossier vide, URL = Lib, sinon URL = Lib/Dossier
                            $pathSuffix = if ($jobArgs.FolderName) { "/$($jobArgs.FolderName)" } else { "" }
                            $finalUrl = "$rootHost$($jobArgs.LibRelUrl)$pathSuffix"
                        
                            if ($fCopy) { 
                                $fCopy.IsEnabled = $true 
                                $fCopy.Tag = $finalUrl
                            }
                            if ($fOpen) { $fOpen.IsEnabled = $true }
                            if ($fBtn) { $fBtn.IsEnabled = $false }
                        } 
                        else {
                            if ($fStat) { $fStat.Text = "Terminé avec erreurs." }
                            if ($fBtn) { $fBtn.IsEnabled = $true }
                        }

                        if ($result.Logs) {
                            foreach ($line in $result.Logs) {
                                $parts = $line -split '\|', 2
                                $lvl = if ($parts.Count -eq 2) { $parts[0] } else { "INFO" }
                                $msg = if ($parts.Count -eq 2) { $parts[1] } else { $line }

                                $show = $false
                                switch ($logLevel) {
                                    "Light" { if ($lvl -in "SUCCESS", "ERROR", "WARNING") { $show = $true } }
                                    "Normal" { if ($lvl -in "SUCCESS", "ERROR", "WARNING", "INFO") { $show = $true } }
                                    "Hard" { $show = $true }
                                }

                                if ($show -and $fLog) {
                                    $color = switch ($lvl) { "DEBUG" { "Debug" } "INFO" { "Info" } "WARNING" { "Warning" } "ERROR" { "Error" } "SUCCESS" { "Success" } Default { "Info" } }
                                    Write-AppLog -Message $msg -Level $color -RichTextBox $fLog
                                }
                            }
                        }
                    }
                }
            }.GetNewClosure()

            $timer.Add_Tick($timerBlock)
            $timer.Start()

        }.GetNewClosure())
    
    # ... (Boutons Copy/Open inchangés)
    $Ctrl.BtnCopyUrl.Add_Click({
            if ($this.Tag) { Set-Clipboard -Value $this.Tag; Write-AppLog -Message "URL copiée : $($this.Tag)" -Level Info -RichTextBox $Ctrl.LogBox }
        }.GetNewClosure())

    $Ctrl.BtnOpenUrl.Add_Click({
            $copyBtn = $Window.FindName("CopyUrlButton")
            if ($copyBtn -and $copyBtn.Tag) { Start-Process $copyBtn.Tag }
        }.GetNewClosure())
}