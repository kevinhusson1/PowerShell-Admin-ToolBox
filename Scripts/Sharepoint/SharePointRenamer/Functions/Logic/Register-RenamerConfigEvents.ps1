<#
.SYNOPSIS
    Gère le chargement des configurations et l'overlay d'authentification.

.DESCRIPTION
    Ce script gère :
    1. L'affichage ou le masquage de l'overlay de connexion (AuthOverlay).
    2. Le chargement des configurations de déploiement (Get-AppDeployConfigs) avec filtrage par groupe AD.
    3. La gestion de la sélection dans la ListBox (Affichage des détails, Masquage du Placeholder).
    4. La réinitialisation des champs du formulaire lors du changement de sélection.
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
        if ($UserAuth -and $UserAuth.Connected) { 
            if ($Ctrl.AuthOverlay) { $Ctrl.AuthOverlay.Visibility = "Collapsed" }
        }
        else {
            if ($Ctrl.AuthOverlay) { $Ctrl.AuthOverlay.Visibility = "Visible" }
        }

        # 2. Load Configs
        try {
            $allConfigs = Get-AppDeployConfigs
            $filtered = [System.Collections.Generic.List[psobject]]::new()
            
            foreach ($cfg in $allConfigs) {
                $allowed = $false
                if ([string]::IsNullOrWhiteSpace($cfg.AllowedGroups)) {
                    $allowed = $true
                }
                elseif ($UserAuth) {
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
        if ($Ctrl.AuthOverlay) { $Ctrl.AuthOverlay.Visibility = "Visible" }
    }

    # Overlay Button
    if ($Ctrl.OverlayBtn) {
        $Ctrl.OverlayBtn.Add_Click({
                if ($Ctrl.ScriptAuthTextButton) { 
                    $Ctrl.ScriptAuthTextButton.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) 
                }
            }.GetNewClosure())
    }
    
    # Selection Change (Switch Panels)
    if ($Ctrl.ListBox) {
        $Ctrl.ListBox.Add_SelectionChanged({
                param($sender, $e)
                
                # Dynamic Find Attempt (Keep logic as fallback, remove debug msg)
                $dynGrid = $null
                try { $dynGrid = $Window.FindName("DetailGrid") } catch {}
                
                $sel = $Ctrl.ListBox.SelectedItem
                
                if (-not $sel) {
                    # Show Placeholder
                    if ($Ctrl.PlaceholderPanel) { $Ctrl.PlaceholderPanel.Visibility = "Visible" }
                    elseif ($dynPl = $Window.FindName("PlaceholderPanel")) { $dynPl.Visibility = "Visible" }
                    
                    if ($Ctrl.DetailGrid) { $Ctrl.DetailGrid.Visibility = "Collapsed" }
                    elseif ($dynGrid) { $dynGrid.Visibility = "Collapsed" }
                }
                else {
                    # Show Details
                    if ($Ctrl.PlaceholderPanel) { $Ctrl.PlaceholderPanel.Visibility = "Collapsed" }
                    elseif ($dynPl = $Window.FindName("PlaceholderPanel")) { $dynPl.Visibility = "Collapsed" }

                    if ($Ctrl.DetailGrid) { $Ctrl.DetailGrid.Visibility = "Visible" }
                    elseif ($dynGrid) { $dynGrid.Visibility = "Visible" }
                    
                    # Update Title
                    if ($Ctrl.ConfigTitleText) { 
                        $Ctrl.ConfigTitleText.Text = $sel.ConfigName 
                    } 
                    
                    # Reset Target / Form
                    if ($Ctrl.TargetFolderBox) { 
                        $Ctrl.TargetFolderBox.Text = "Aucun dossier sélectionné..."
                        $Ctrl.TargetFolderBox.Tag = $null 
                    }
                    if ($Ctrl.CurrentMetaText) { $Ctrl.CurrentMetaText.Text = "Métadonnées actuelles : -" }
                    if ($Ctrl.FormPanel) { $Ctrl.FormPanel.Visibility = "Collapsed" }
                    if ($Ctrl.DynamicFormPanel) { $Ctrl.DynamicFormPanel.Children.Clear() }
                    
                    # Reset Preview
                    if ($Ctrl.FolderNamePreview) { $Ctrl.FolderNamePreview.Text = "..." }
                }
            }.GetNewClosure())
    }
    else {
    }
}
