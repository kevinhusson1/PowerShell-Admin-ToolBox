# Modules/LauncherUI/Functions/Update-LauncherAuthButton.ps1

<#
.SYNOPSIS
    Met à jour l'apparence du macaron d'authentification en fonction de l'état de connexion.
.DESCRIPTION
    Cette fonction modifie le contenu, le tooltip et les couleurs du bouton
    d'authentification pour refléter si un utilisateur Azure est connecté
    ou si l'application est en mode "Système".
.PARAMETER AuthButton
    L'objet [System.Windows.Controls.Button] représentant le macaron d'authentification.
.EXAMPLE
    Update-LauncherAuthButton -AuthButton $myProfileButton
.OUTPUTS
    Aucune.
#>
function Update-LauncherAuthButton {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.Button]$AuthButton
    )

    if ($Global:AppAzureAuth.UserAuth.Connected) {
        $AuthButton.Content = $Global:AppAzureAuth.UserAuth.Initials
        
        # On utilise les clés de traduction pour le tooltip
        $tooltipText = "{0} : {1}" -f (Get-AppText 'modules.launcherui.auth_tooltip_connected'), $Global:AppAzureAuth.UserAuth.DisplayName
        $AuthButton.ToolTip = $tooltipText
        
        $AuthButton.Background = $AuthButton.FindResource('AuthButtonUserBackgroundBrush')
        $AuthButton.Foreground = $AuthButton.FindResource('AuthButtonUserForegroundBrush')
    } else {
        $iconContent = New-Object System.Windows.Controls.TextBlock
        $iconContent.Text = '👤'
        $iconContent.FontFamily = 'Segoe UI Symbol'
        $iconContent.FontSize = 16
        
        $AuthButton.Content = $iconContent
        
        # On utilise les clés de traduction pour le tooltip
        $AuthButton.ToolTip = Get-AppText 'modules.launcherui.auth_tooltip_system'
        
        $AuthButton.Background = $AuthButton.FindResource('AuthButtonSystemBackgroundBrush')
        $AuthButton.Foreground = $AuthButton.FindResource('DarkTextBrush')
    }
}