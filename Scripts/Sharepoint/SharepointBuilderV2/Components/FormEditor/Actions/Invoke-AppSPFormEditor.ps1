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
            $uiComponent = New-Object System.Windows.Controls.TextBlock
            $uiComponent.Text = $data.Content
            $uiComponent.VerticalAlignment = "Center"
            $uiComponent.FontWeight = "Bold"
            $uiComponent.Margin = "0,0,5,0"
            $uiComponent.Foreground = $Window.FindResource("TextPrimaryBrush")
            $panel.Children.Add($uiComponent) | Out-Null
        }
        elseif ($data.Type -eq "TextBox") {
            $uiComponent = New-Object System.Windows.Controls.TextBox
            $uiComponent.Text = $data.DefaultValue
            $uiComponent.Width = $finalWidth
            $uiComponent.Margin = "0,0,5,0"
            $uiComponent.Style = $Window.FindResource("StandardTextBoxStyle")
            
            # Event temps réel (TextChanged)
            $uiComponent.add_TextChanged($recalculateSb)

            # Gestion Majuscules
            if ($data.IsUppercase) {
                $uiComponent.CharacterCasing = [System.Windows.Controls.CharacterCasing]::Upper
            }
            
            $panel.Children.Add($uiComponent) | Out-Null
        }
        elseif ($data.Type -eq "ComboBox") {
            $uiComponent = New-Object System.Windows.Controls.ComboBox
            $uiComponent.Width = $finalWidth
            $uiComponent.Margin = "0,0,5,0"
            $uiComponent.Style = $Window.FindResource("StandardComboBoxStyle")
            if ($data.Options) {
                $uiComponent.ItemsSource = $data.Options
                # Sélection par défaut
                if ($data.DefaultValue -and $data.Options -contains $data.DefaultValue) {
                    $uiComponent.SelectedItem = $data.DefaultValue
                }
                elseif ($data.Options.Count -gt 0) {
                    $uiComponent.SelectedIndex = 0
                }
            }
            
            # Event temps réel (SelectionChanged)
            $uiComponent.add_SelectionChanged($recalculateSb)
            
            $panel.Children.Add($uiComponent) | Out-Null
        }
    }
    
    # Calcul initial
    Invoke-AppSPFormRecalculate -Ctrl $Ctrl
}
