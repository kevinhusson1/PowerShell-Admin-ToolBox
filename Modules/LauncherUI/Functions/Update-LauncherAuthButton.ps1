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

    # On récupère le bouton texte via la variable globale
    $textButton = $Global:AppControls.AuthTextButton

    if ($Global:AppAzureAuth.UserAuth.Connected) {
        # --- ETAT : CONNECTÉ ---
        
        # 1. Macaron (Initiales)
        $AuthButton.Content = $Global:AppAzureAuth.UserAuth.Initials
        $tooltipText = "{0} : {1}" -f (Get-AppText 'modules.launcherui.auth_tooltip_connected'), $Global:AppAzureAuth.UserAuth.DisplayName
        $AuthButton.ToolTip = $tooltipText
        $AuthButton.Background = $AuthButton.FindResource('AuthButtonUserBackgroundBrush')
        $AuthButton.Foreground = $AuthButton.FindResource('AuthButtonUserForegroundBrush')

        # 2. Texte
        if ($textButton) {
            $textButton.Content = "Se déconnecter"
            $textButton.ToolTip = "Cliquez pour fermer la session"
            # Optionnel : Changer la couleur du texte en rouge léger au survol pour indiquer la déconnexion
        }

    } else {
        # --- ETAT : DÉCONNECTÉ ---

        # 1. Macaron (Icône fantôme)
        $iconContent = New-Object System.Windows.Controls.TextBlock
        $iconContent.Text = '👤'
        $iconContent.FontFamily = 'Segoe UI Symbol'
        $iconContent.FontSize = 16
        $AuthButton.Content = $iconContent
        $AuthButton.ToolTip = Get-AppText 'modules.launcherui.auth_tooltip_system'
        $AuthButton.Background = $AuthButton.FindResource('AuthButtonSystemBackgroundBrush')
        $AuthButton.Foreground = $AuthButton.FindResource('DarkTextBrush')

        # 2. Texte
        if ($textButton) {
            $textButton.Content = "Se connecter"
            $textButton.ToolTip = "Cliquez pour accéder aux fonctionnalités d'administration"
        }
    }
}
