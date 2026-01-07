<#
.SYNOPSIS
    Gère le chargement des configurations et l'overlay d'authentification.

.DESCRIPTION
    Définit la ScriptAction $Global:DeployerLoadAction qui est rappelée lors des changements d'état d'authentification.
    Charge les configurations depuis la BDD SQLite (Get-AppDeployConfigs).
    Filtre les configurations en fonction des groupes Azure AD de l'utilisateur connecté.
    Gère l'affichage/masquage de l'overlay "Connexion Requise".

.PARAMETER Ctrl
    Hashtable contenant les contrôles UI.

.PARAMETER Window
    Fenêtre parente.
#>
function Register-ConfigEvents {
    param(
        [hashtable]$Ctrl,
        [System.Windows.Window]$Window
    )

    # Helper Log local
    $Log = { 
        param($msg, $level = "Info") 
        if ($Ctrl.LogBox) { Write-AppLog -Message $msg -Level $level -RichTextBox $Ctrl.LogBox }
    }.GetNewClosure()

    # --- 1. LOGIQUE DE CHARGEMENT (Appelée par AuthCallback) ---
    $Global:DeployerLoadAction = {
        param($UserAuth)
        try {
            # Check Auth (Use injected parameter preferably, or fallback to global if missing, but we aim for injected)
            $isConnected = if ($UserAuth) { $UserAuth.Connected } else { $false }
            
            if (-not $isConnected) {
                # Mode Déconnecté : Vider la liste
                if ($Ctrl.ListBox) { $Ctrl.ListBox.ItemsSource = $null }
                # Afficher l'overlay
                if ($Ctrl.AuthOverlay) { $Ctrl.AuthOverlay.Visibility = "Visible" }
                
                # Loc check
                $msg = if (Get-Command Get-AppLocalizedString -ErrorAction SilentlyContinue) { Get-AppLocalizedString -Key "sp_deploy.status_disconnected" } else { "Déconnecté" }
                & $Log $msg "Warning"
                return
            }
            
            # Connecté -> Masquer l'overlay
            if ($Ctrl.AuthOverlay) { $Ctrl.AuthOverlay.Visibility = "Collapsed" }

            # Récupération Groupes (Graph)
            $userGroups = @()
            try {
                if (Get-Command Get-AppUserAzureGroups -ErrorAction SilentlyContinue) {
                    $userGroups = Get-AppUserAzureGroups
                }
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
                    # Si l'utilisateur est admin global ou a le rôle, c'est bon.
                    # Ici on check juste si ses groupes contiennent le rôle
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
            }
            
            $msgReady = if (Get-Command Get-AppLocalizedString -ErrorAction SilentlyContinue) { Get-AppLocalizedString -Key "sp_deploy.status_ready" } else { "Prêt." }
            & $Log $msgReady "Success"

        }
        catch {
            & $Log "Erreur chargement : $($_.Exception.Message)" "Error"
        }
    }.GetNewClosure()

    # --- 2. ACTION OVERLAY CONNECT ---
    if ($Ctrl.OverlayBtn) {
        $Ctrl.OverlayBtn.Add_Click({
                # On trouve le bouton de connexion principal et on simule un clic
                if ($Ctrl.ScriptAuthTextButton) { 
                    $Ctrl.ScriptAuthTextButton.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) 
                }
            }.GetNewClosure())
    }
}
