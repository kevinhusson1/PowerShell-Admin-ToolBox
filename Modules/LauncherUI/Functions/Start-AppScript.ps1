# Modules/LauncherUI/Functions/Start-AppScript.ps1

<#
.SYNOPSIS
    Gère le processus de lancement sécurisé d'un script enfant.
.DESCRIPTION
    Cette fonction est le point d'entrée pour démarrer un nouveau script. Elle effectue
    les opérations critiques suivantes dans l'ordre :
    1. Vérifie si le script a le droit de s'exécuter en interrogeant le système de verrouillage.
    2. Si autorisé, lance le script dans un nouveau processus PowerShell invisible.
    3. Enregistre le verrou dans la base de données avec le PID du nouveau processus.
    4. Met à jour l'état interne du lanceur (listes, objets) et son interface (boutons, tuiles).
.PARAMETER SelectedScript
    L'objet script complet (enrichi) que l'utilisateur a demandé de lancer.
.PARAMETER ProjectRoot
    Le chemin racine du projet (nécessaire pour construire les chemins).
.OUTPUTS
    [System.Diagnostics.Process] - L'objet du processus qui a été démarré, ou $null en cas d'échec.
#>
function Start-AppScript {
    [CmdletBinding()]
    [OutputType([System.Diagnostics.Process])]
    param(
        [Parameter(Mandatory)]
        [psobject]$SelectedScript,
        [Parameter(Mandatory)]
        [string]$ProjectRoot
    )

    
    try {
        # --- ÉTAPE 1 : Réinitialisation de l'état de progression de l'objet de données ---
        $SelectedScript.LoadingProgress = 0
        $SelectedScript.LoadingStatus = "Démarrage..." # Message initial

        # 1. On VÉRIFIE d'abord si on a le droit de se lancer.
        if (-not (Test-AppScriptLock -Script $SelectedScript)) {
            $title = Get-AppText -Key 'messages.execution_forbidden_title'
            $message = Get-AppText -Key 'messages.execution_limit_reached'
            [System.Windows.MessageBox]::Show("$message '$($SelectedScript.name)'.", $title, "OK", "Warning")
            return $null
        }
    
        $process = $null

        # 2. On LANCE le processus enfant.
        $scriptFileName = $SelectedScript.scriptFile
        $fullScriptPath = Join-Path -Path $SelectedScript.ScriptPath -ChildPath $scriptFileName
        if (-not (Test-Path $fullScriptPath)) {
            $errorMsg = Get-AppText -Key 'messages.script_file_not_found'
            throw "$errorMsg : $fullScriptPath"
        }

        # --- AJOUT : Basculement de l'UI en mode chargement ---
        $SelectedScript.IsLoading = $true
        if ($Global:AppControls.scriptsListBox.SelectedItem -eq $SelectedScript) {
            $Global:AppControls.scriptDetailPanel.Visibility = 'Collapsed'
            $Global:AppControls.scriptLoadingPanel.Visibility = 'Visible'
            $Global:AppControls.loadingScriptName.Text = $SelectedScript.name

            # On force la mise à jour des contrôles visuels au moment où ils deviennent visibles.
            $Global:AppControls.loadingProgressBar.Value = 0
            $Global:AppControls.loadingProgressText.Text = "0%"
            $Global:AppControls.loadingStatusText.Text = $SelectedScript.LoadingStatus

            $Global:AppControls.bringToFrontButton.Visibility = 'Visible'
        }
        $Global:AppControls.scriptsListBox.Items.Refresh()
        # --------------------------------------------------------

        # --- AJOUT : Démarrage du timer de progression ---
        if (-not $Global:progressTimer.IsEnabled) {
            Write-Verbose "[TIMER] Le suivi de progression est démarré."
            $Global:progressTimer.Start()
        }

        # --- PRÉPARATION DU CONTEXTE D'AUTHENTIFICATION ---
        # On force une profondeur de 5 pour être sûr de capturer toute la structure de l'objet
        $authJson = $Global:AppAzureAuth | ConvertTo-Json -Depth 5 -Compress
        $authContextEncoded = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($authJson))

        # 2. On LANCE le processus enfant.
        $process = Start-Process pwsh.exe -ArgumentList @(
            "-NoProfile", 
            "-ExecutionPolicy", "Bypass", 
            "-File", $fullScriptPath, 
            "-LauncherPID", $PID,
            "-AuthContext", $authContextEncoded # <-- Vérifiez que cette ligne est bien là
        ) -PassThru -WindowStyle Hidden
        
        # 3. On ENREGISTRE le verrou avec le PID de l'enfant qu'on vient d'obtenir.
        # Add-AppScriptLock -Script $SelectedScript -OwnerPID $process.Id

        # 4. On met à jour l'état interne et l'UI du lanceur.
        $SelectedScript.pid = $process.Id
        $SelectedScript.IsRunning = $true
        
        $Global:AppActiveScripts.Add($process)

        # --- AJOUT CRUCIAL : On ajoute le PID à la liste de surveillance ---
        $Global:PIDsToMonitor.Add($process.Id)

        $Global:AppControls.executeButton.Content = Get-AppText -Key 'launcher.stop_button'
        $Global:AppControls.executeButton.Style = $Global:AppControls.executeButton.FindResource('RedButtonStyle')
        $Global:AppControls.scriptsListBox.Items.Refresh()

        $logMessage = "{0} '{1}' (PID: {2})." -f (Get-AppText 'launcherLog.launchScriptSuccess'), $SelectedScript.name, $process.Id
        Write-LauncherLog -Message $logMessage -Level Info

        return $process
    } catch {
        # Si une erreur se produit (ex: le script n'est pas trouvé) APRES que le processus a été créé,
        # on s'assure de ne pas laisser de verrou orphelin.
        if ($process) {
            Unlock-AppScriptLock -OwnerPID $process.Id
        }
        $errorMsg = Get-AppText -Key 'messages.script_launch_error'
        [System.Windows.MessageBox]::Show("$errorMsg :`n$($_.Exception.Message)", "Erreur de Lancement", "OK", "Error")
        return $null
    }
}