<#
.SYNOPSIS
    Gère le chargement des configurations et l'overlay d'authentification.
#>
function Register-RenamerConfigEvents {
    param(
        [hashtable]$Ctrl,
        [System.Windows.Window]$Window
    )

    # Fonction de chargement (appelée par bouton auth ou init)
    $Global:RenamerLoadAction = {
        param($UserAuth)
        
        # 1. Update UI Auth
        if ($Ctrl.UserBadge) {
            if ($UserAuth) { 
                $Ctrl.UserBadge.Text = "Connecté : $($UserAuth.DisplayName)"
                $Ctrl.UserBadge.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#0078D4")
                $Ctrl.AuthOverlay.Visibility = "Collapsed"
            }
            else {
                $Ctrl.UserBadge.Text = "Non connecté"
                $Ctrl.UserBadge.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#CCCCCC")
                $Ctrl.AuthOverlay.Visibility = "Visible"
            }
        }

        # 2. Load Configs
        try {
            # Récupération des configs depuis DB
            # Get-AppDeployConfigs est dans le module Database
            $allConfigs = Get-AppDeployConfigs
            
            # Filtre par groupes (si UserAuth présent)
            $filtered = [System.Collections.Generic.List[psobject]]::new()
            
            foreach ($cfg in $allConfigs) {
                $allowed = $false
                # Si pas de groupe défini -> Public (Autorisé)
                if ([string]::IsNullOrWhiteSpace($cfg.AllowedGroups)) {
                    $allowed = $true
                }
                elseif ($UserAuth) {
                    # Check MemberOf
                    $groups = $cfg.AllowedGroups -split ";"
                    foreach ($g in $groups) {
                        if ($UserAuth.MemberOf -contains $g.Trim()) {
                            $allowed = $true; break
                        }
                    }
                }
                
                if ($allowed) { $filtered.Add($cfg) }
            }
            
            if ($Ctrl.ListBox) {
                # UI Thread Update
                $Ctrl.ListBox.ItemsSource = $filtered
            }
        }
        catch {
            [System.Windows.MessageBox]::Show("Erreur chargement configs : $($_.Exception.Message)")
        }

    }.GetNewClosure()

    # Initial Load
    if ($Global:UserAuthContext) {
        & $Global:RenamerLoadAction $Global:UserAuthContext
    }
    else {
        # Active Overlay
        if ($Ctrl.AuthOverlay) { $Ctrl.AuthOverlay.Visibility = "Visible" }
    }

    # Overlay Button
    if ($Ctrl.OverlayBtn) {
        $Ctrl.OverlayBtn.Add_Click({
                # On trouve le bouton de connexion principal et on simule un clic
                if ($Ctrl.ScriptAuthTextButton) { 
                    $Ctrl.ScriptAuthTextButton.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) 
                }
            }.GetNewClosure())
    }
    
    # Selection Change (Reset Steps)
    if ($Ctrl.ListBox) {
        $Ctrl.ListBox.Add_SelectionChanged({
                param($sender, $e)
                # Reset UI Steps
                $Ctrl.TargetFolderBox.Text = "Aucun dossier sélectionné..."
                $Ctrl.TargetFolderBox.Tag = $null # Clears selected info
                $Ctrl.CurrentMetaText.Text = "Métadonnées actuelles : -"
                $Ctrl.FormPanel.Visibility = "Collapsed"
                $Ctrl.DynamicFormPanel.Children.Clear()
            })
    }
}
