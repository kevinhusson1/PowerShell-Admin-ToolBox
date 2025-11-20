# Modules/LauncherUI/Functions/Update-GovernanceTab.ps1

<#
.SYNOPSIS
    Rafraîchit les données de l'onglet Gouvernance (Demandes, Permissions, Membres).
#>
function Update-GovernanceTab {
    [CmdletBinding()]
    param()

    # Vérification de sécurité
    if (-not $Global:IsAppAdmin -or -not $Global:AppAzureAuth.UserAuth.Connected) { return }

    # --- 1. MISE À JOUR DES DEMANDES (SQLite) ---
    $requests = Get-AppPermissionRequests -Status 'Pending'
    
    $Global:AppControls.PermissionRequestsListBox.Dispatcher.Invoke([Action]{
        $Global:AppControls.PermissionRequestsListBox.ItemsSource = $null
        if ($requests) {
            $Global:AppControls.NoRequestsText.Visibility = 'Collapsed'
            # On envoie les données brutes, le XAML s'occupe de l'affichage
            $Global:AppControls.PermissionRequestsListBox.ItemsSource = @($requests)
        } else {
            $Global:AppControls.NoRequestsText.Visibility = 'Visible'
        }
    })

    # --- 2. MISE À JOUR DES PERMISSIONS ACTIVES (Azure) ---
    $appId = $Global:AppConfig.azure.authentication.userAuth.appId
    if (-not [string]::IsNullOrWhiteSpace($appId)) {
        $permissionsObj = Get-AppServicePrincipalPermissions -AppId $appId
        
        $Global:AppControls.CurrentScopesListBox.Dispatcher.Invoke([Action]{
            $Global:AppControls.CurrentScopesListBox.Items.Clear()
            
            foreach ($perm in $permissionsObj) {
                # Création d'un item riche visuellement
                $item = New-Object System.Windows.Controls.ListBoxItem
                $stack = New-Object System.Windows.Controls.StackPanel -Property @{ Orientation = 'Horizontal' }
                
                if ($perm.Status -eq 'Granted') {
                    $icon = New-Object System.Windows.Controls.TextBlock -Property @{ Text = "✅ "; Foreground = [System.Windows.Media.Brushes]::Green }
                    $tooltip = "Consentement accordé"
                } else {
                    $icon = New-Object System.Windows.Controls.TextBlock -Property @{ Text = "⚠ "; Foreground = [System.Windows.Media.Brushes]::Orange }
                    $tooltip = "Consentement administrateur requis"
                }
                
                $text = New-Object System.Windows.Controls.TextBlock -Property @{ Text = $perm.Name; VerticalAlignment = 'Center' }
                
                $stack.Children.Add($icon)
                $stack.Children.Add($text)
                $stack.ToolTip = $tooltip
                
                $item.Content = $stack
                $Global:AppControls.CurrentScopesListBox.Items.Add($item)
            }
        })
    }

    # --- 3. MISE À JOUR DES MEMBRES (Azure) ---
    $adminGroupName = $Global:AppConfig.security.adminGroupName

    # Fonction locale pour peupler proprement une liste
    $populateList = {
        param($listBox, $members)
        $listBox.Dispatcher.Invoke([Action]{
            $listBox.ItemsSource = $null # On délie la source
            $listBox.Items.Clear()       # On vide
            
            if ($members) {
                # On force l'objet en tableau pour gérer le cas unique
                foreach ($m in @($members)) {
                    # On crée un affichage propre : "Nom (Email)"
                    $text = "$($m.DisplayName) ($($m.UserPrincipalName))"
                    $listBox.Items.Add($text)
                }
            }
        })
    }

    # Admins
    if (-not [string]::IsNullOrWhiteSpace($adminGroupName)) {
        $admins = Get-AppAzureGroupMembers -GroupName $adminGroupName
        & $populateList -listBox $Global:AppControls.AdminMembersListBox -members $admins
    }
}