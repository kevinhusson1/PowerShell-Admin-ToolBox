# Modules/LauncherUI/Functions/Update-GovernanceTab.ps1

<#
.SYNOPSIS
    Rafraîchit les données de l'onglet Gouvernance (Demandes, Permissions, Membres).
#>
function Update-GovernanceTab {
    [CmdletBinding()]
    param()

    if (-not $Global:IsAppAdmin -or -not $Global:AppAzureAuth.UserAuth.Connected) { return }

    # 1. DEMANDES
    $requests = Get-AppPermissionRequests -Status 'Pending'
    $Global:AppControls.PermissionRequestsListBox.Dispatcher.Invoke([Action]{
        $Global:AppControls.PermissionRequestsListBox.ItemsSource = $null
        if ($requests) {
            $Global:AppControls.NoRequestsText.Visibility = 'Collapsed'
            $Global:AppControls.PermissionRequestsListBox.ItemsSource = @($requests)
        } else {
            $Global:AppControls.NoRequestsText.Visibility = 'Visible'
        }
    })

    # 2. PERMISSIONS ACTIVES
    $appId = $Global:AppConfig.azure.authentication.userAuth.appId
    $tenantId = $Global:AppConfig.azure.tenantId

    if (-not [string]::IsNullOrWhiteSpace($appId)) {
        # On sécurise l'appel
        $permissionsObj = Get-AppServicePrincipalPermissions -AppId $appId
        if ($null -eq $permissionsObj) { $permissionsObj = @() }
        
        $mainWindow = $Global:AppControls.mainWindow

        $Global:AppControls.CurrentScopesListBox.Dispatcher.Invoke([Action]{
            $Global:AppControls.CurrentScopesListBox.Items.Clear()
            
            foreach ($perm in $permissionsObj) {
                if (-not $perm) { continue }

                # Border Container
                $border = New-Object System.Windows.Controls.Border
                $border.CornerRadius = [System.Windows.CornerRadius]::new(6)
                $border.BorderThickness = [System.Windows.Thickness]::new(1)
                # Utilisation de ressources sûres
                $border.Background = $mainWindow.FindResource('WhiteBrush') 
                $border.BorderBrush = $mainWindow.FindResource('BorderLightBrush')
                $border.Padding = [System.Windows.Thickness]::new(10, 8, 10, 8)
                $border.Margin = [System.Windows.Thickness]::new(0, 0, 0, 5)

                $grid = New-Object System.Windows.Controls.Grid
                $col1 = New-Object System.Windows.Controls.ColumnDefinition; $col1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
                $col2 = New-Object System.Windows.Controls.ColumnDefinition; $col2.Width = [System.Windows.GridLength]::Auto
                $grid.ColumnDefinitions.Add($col1); $grid.ColumnDefinitions.Add($col2)

                # Nom + Type
                $nameStack = New-Object System.Windows.Controls.StackPanel
                [System.Windows.Controls.Grid]::SetColumn($nameStack, 0)
                $nameStack.VerticalAlignment = 'Center'

                $textBlock = New-Object System.Windows.Controls.TextBlock
                $textBlock.Text = "$($perm.Name)"
                $textBlock.FontWeight = 'SemiBold'
                $textBlock.FontSize = 12
                $nameStack.Children.Add($textBlock)

                $typeBlock = New-Object System.Windows.Controls.TextBlock
                $typeText = if ($perm.ConsentType -eq "Admin") { "Admin Requis" } else { "Standard" }
                $typeBlock.Text = $typeText
                $typeBlock.FontSize = 10
                $typeBlock.Foreground = $mainWindow.FindResource('TextSecondaryBrush')
                $nameStack.Children.Add($typeBlock)

                $grid.Children.Add($nameStack)

                # Badge
                $badge = New-Object System.Windows.Controls.Border
                $badge.CornerRadius = [System.Windows.CornerRadius]::new(4)
                $badge.Padding = [System.Windows.Thickness]::new(6, 2, 6, 2)
                $badgeText = New-Object System.Windows.Controls.TextBlock
                $badgeText.FontSize = 10
                $badgeText.FontWeight = 'Bold'
                $badge.Child = $badgeText
                [System.Windows.Controls.Grid]::SetColumn($badge, 1)

                if ($perm.Status -eq 'Granted') {
                    # VERT - Non Cliquable
                    $badge.Background = $mainWindow.FindResource('SuccessBackgroundBrush')
                    $badgeText.Text = "ACCORDÉ"
                    $badgeText.Foreground = $mainWindow.FindResource('SuccessBrush')
                    $badge.Cursor = [System.Windows.Input.Cursors]::Arrow
                } else {
                    # ORANGE - Cliquable
                    $badge.Background = $mainWindow.FindResource('WarningBackgroundBrush')
                    $badgeText.Text = "CONSENTEMENT REQUIS"
                    $badgeText.Foreground = $mainWindow.FindResource('WarningBrush')
                    $badge.Cursor = [System.Windows.Input.Cursors]::Hand
                    $badge.ToolTip = "Cliquez pour ouvrir la page de consentement Azure"
                    
                    $badge.Add_MouseLeftButtonUp({
                        try {
                            $url = "https://login.microsoftonline.com/$tenantId/adminconsent?client_id=$appId&redirect_uri=http://localhost"
                            Start-Process $url
                        } catch { }
                    })
                }
                
                $grid.Children.Add($badge)
                $border.Child = $grid
                $Global:AppControls.CurrentScopesListBox.Items.Add($border)
            }
        })
    }

    # 3. MEMBRES
    $adminGroupName = $Global:AppConfig.security.adminGroupName
    $populateList = {
        param($listBox, $members)
        $listBox.Dispatcher.Invoke([Action]{
            $listBox.ItemsSource = $null; $listBox.Items.Clear()
            if ($members) {
                foreach ($m in @($members)) {
                    $text = "$($m.DisplayName) ($($m.UserPrincipalName))"
                    $listBox.Items.Add($text)
                }
            }
        })
    }
    if (-not [string]::IsNullOrWhiteSpace($adminGroupName)) {
        $admins = Get-AppAzureGroupMembers -GroupName $adminGroupName
        & $populateList -listBox $Global:AppControls.AdminMembersListBox -members $admins
    }
}