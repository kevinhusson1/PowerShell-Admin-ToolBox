# Scripts/SharePoint/SharePointBuilder/Functions/Logic/Get-PreviewLogic.ps1

function Get-PreviewLogic {
    param($Ctrl)

    # On retourne un ScriptBlock qui capture $Ctrl via une Closure
    return {
        param($sender, $e)
        
        $finalName = ""
        # On utilise $Ctrl.PanelForm directement car capturé
        if ($Ctrl.PanelForm.Children) {
            foreach ($c in $Ctrl.PanelForm.Children) {
                if ($c -is [System.Windows.Controls.TextBox]) { $finalName += $c.Text }
                elseif ($c -is [System.Windows.Controls.TextBlock] -and $c.Tag -eq "Static") { $finalName += $c.Text }
                elseif ($c -is [System.Windows.Controls.ComboBox]) { $finalName += $c.SelectedItem }
            }
        }
        
        $Ctrl.TxtPreview.Text = if ($finalName) { $finalName } else { "..." }
        
        # Validation
        $isValid = (-not [string]::IsNullOrWhiteSpace($finalName)) -and 
                   ($null -ne $Ctrl.CbSites.SelectedItem) -and 
                   ($null -ne $Ctrl.CbLibs.SelectedItem)
        
        $Ctrl.BtnDeploy.IsEnabled = $isValid

    }.GetNewClosure()
}