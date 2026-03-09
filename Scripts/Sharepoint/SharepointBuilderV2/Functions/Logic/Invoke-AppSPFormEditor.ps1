# Scripts/Sharepoint/SharepointBuilderV2/Functions/Logic/Invoke-AppSPFormEditor.ps1

<#
.SYNOPSIS
    Moteurs de rendu et de calcul pour l'éditeur de formulaires SharePoint.
.DESCRIPTION
    Contient les fonctions globales permettant de mettre à jour la prévisualisation en temps réel
    et de recalculer le résultat concaténé des champs du formulaire.
#>

<#
.SYNOPSIS
    Recalcule la chaîne de caractères résultante basée sur les valeurs saisies dans la prévisualisation.
#>
function Global:Invoke-AppSPFormRecalculate {
    param(
        [hashtable]$Ctrl
    )

    if (-not $Ctrl.FormLivePreview) { return }

    try {
        $txt = ""
        $children = $Ctrl.FormLivePreview.Children
        foreach ($child in $children) {
            if ($child -is [System.Windows.Controls.TextBlock]) {
                $txt += $child.Text
            }
            elseif ($child -is [System.Windows.Controls.TextBox]) {
                $val = $child.Text
                if ([string]::IsNullOrWhiteSpace($val)) { $val = "..." }
                $txt += $val
            }
            elseif ($child -is [System.Windows.Controls.ComboBox]) {
                if ($child.SelectedItem) {
                    $txt += $child.SelectedItem.ToString()
                }
                elseif (-not [string]::IsNullOrWhiteSpace($child.Text)) {
                    $txt += $child.Text
                }
            }
        }
        if ($Ctrl.FormResultText) { 
            $Ctrl.FormResultText.Text = if ([string]::IsNullOrWhiteSpace($txt)) { "..." } else { $txt } 
        }
    }
    catch {
        # Silencieux pour ne pas crasher l'UI en cas d'erreur de thread ou autre
        Write-Verbose "[FormEditor] Erreur Recalculate: $_"
    }
}

<#
.SYNOPSIS
    Génère les contrôles WPF dans le panneau de prévisualisation à partir de la liste des champs.
#>
function Global:Invoke-AppSPFormUpdatePreview {
    param(
        [hashtable]$Ctrl,
        [System.Windows.Window]$Window
    )

    if (-not $Ctrl.FormLivePreview) { return }
    
    $panel = $Ctrl.FormLivePreview
    $panel.Children.Clear()

    # Création d'un scriptblock local pour le branchement des événements de reculcul
    # On repasse par la fonction globale pour la persistance
    $recalculateSb = {
        param($s, $e)
        Invoke-AppSPFormRecalculate -Ctrl $Ctrl
    }.GetNewClosure()

    foreach ($item in $Ctrl.FormList.Items) {
        $data = $item.Tag
        if (-not $data) { continue }
        
        $widthVal = 100
        if ($data.Width -and [int]::TryParse($data.Width, [ref]$widthVal)) { }
        $finalWidth = [double]$widthVal
        
        if ($data.Type -eq "Label") {
            $ctrl = New-Object System.Windows.Controls.TextBlock
            $ctrl.Text = $data.Content
            $ctrl.VerticalAlignment = "Center"
            $ctrl.FontWeight = "Bold"
            $ctrl.Margin = "0,0,5,0"
            $ctrl.Foreground = $Window.FindResource("TextPrimaryBrush")
            $panel.Children.Add($ctrl) | Out-Null
        }
        elseif ($data.Type -eq "TextBox") {
            $ctrl = New-Object System.Windows.Controls.TextBox
            $ctrl.Text = $data.DefaultValue
            $ctrl.Width = $finalWidth
            $ctrl.Margin = "0,0,5,0"
            $ctrl.Style = $Window.FindResource("StandardTextBoxStyle")
            
            # Event temps réel (TextChanged)
            $ctrl.add_TextChanged($recalculateSb)

            # Gestion Majuscules
            if ($data.IsUppercase) {
                $ctrl.CharacterCasing = [System.Windows.Controls.CharacterCasing]::Upper
            }
            
            $panel.Children.Add($ctrl) | Out-Null
        }
        elseif ($data.Type -eq "ComboBox") {
            $ctrl = New-Object System.Windows.Controls.ComboBox
            $ctrl.Width = $finalWidth
            $ctrl.Margin = "0,0,5,0"
            $ctrl.Style = $Window.FindResource("StandardComboBoxStyle")
            if ($data.Options) {
                $ctrl.ItemsSource = $data.Options
                # Sélection par défaut
                if ($data.DefaultValue -and $data.Options -contains $data.DefaultValue) {
                    $ctrl.SelectedItem = $data.DefaultValue
                }
                elseif ($data.Options.Count -gt 0) {
                    $ctrl.SelectedIndex = 0
                }
            }
            
            # Event temps réel (SelectionChanged)
            $ctrl.add_SelectionChanged($recalculateSb)
            
            $panel.Children.Add($ctrl) | Out-Null
        }
    }
    
    # Calcul initial
    Invoke-AppSPFormRecalculate -Ctrl $Ctrl
}
