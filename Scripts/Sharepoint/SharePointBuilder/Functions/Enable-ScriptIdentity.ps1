# Scripts/Designer/DefaultUI/Functions/Enable-ScriptIdentity.ps1

<#
.SYNOPSIS
    Active et gère le module d'identité dans l'interface du script.
.DESCRIPTION
    Gère l'affichage (Nom/Macaron), la restauration du contexte (si lancé par le Launcher)
    et les actions de connexion/déconnexion (si mode autonome).
#>
function Enable-ScriptIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.Windows.Window]$Window,
        [string]$LauncherPID,
        [Parameter()] [string]$AuthContext
    )

    # 1. Initialisation de la variable globale si elle n'existe pas (Mode Autonome)
    if ($null -eq $Global:AppAzureAuth) {
        $Global:AppAzureAuth = @{ UserAuth = @{ Connected = $false } }
    }

    # 2. Restauration du contexte (Si fourni par le Launcher)
    if (-not [string]::IsNullOrWhiteSpace($AuthContext)) {
        try {
            $json = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($AuthContext))
            $Global:AppAzureAuth = $json | ConvertFrom-Json
            Write-Verbose "[Identity] Contexte restauré : $($Global:AppAzureAuth.UserAuth.DisplayName)"
        } catch {
            Write-Warning "[Identity] Erreur de décodage du contexte : $($_.Exception.Message)"
        }
    } else {
        Write-Verbose "[Identity] Aucun contexte d'auth reçu (Mode Autonome ou Invité)."
    }

    # 3. Récupération des contrôles UI
    $authBtn = $Window.FindName("ScriptAuthStatusButton")
    $authTxt = $Window.FindName("ScriptAuthTextButton")

    if (-not $authBtn -or -not $authTxt) { return }

    # 4. Logique de mise à jour UI
    $updateAuthUI = {
        # On force le rafraîchissement de l'objet global
        $user = $Global:AppAzureAuth.UserAuth
        
        if ($user.Connected) {
            # CONNECTÉ
            $authBtn.Content = $user.Initials
            $authBtn.ToolTip = $user.DisplayName
            $authBtn.Background = $Window.FindResource('WhiteBrush')
            $authBtn.Foreground = $Window.FindResource('PrimaryBrush')
            
            $authTxt.Content = $user.DisplayName
            $authTxt.ToolTip = "Cliquez pour gérer la connexion"
        } else {
            # DÉCONNECTÉ
            $iconContent = New-Object System.Windows.Controls.TextBlock
            $iconContent.Text = '👤'
            $iconContent.FontFamily = 'Segoe UI Symbol'
            $iconContent.FontSize = 16
            
            $authBtn.Content = $iconContent
            $authBtn.Background = $Window.FindResource('PrimaryLightBrush')
            $authBtn.Foreground = $Window.FindResource('WhiteBrush')
            
            $authTxt.Content = "Se connecter"
            $authTxt.ToolTip = "Cliquez pour vous authentifier"
        }
    }.GetNewClosure()

    # 5. Logique du Clic
    $authClickAction = {
        # CAS A : Mode "Esclave" (Launcher) -> Message informatif
        if (-not [string]::IsNullOrWhiteSpace($LauncherPID)) {
            [System.Windows.MessageBox]::Show(
                "L'authentification est gérée par le Lanceur principal.", 
                "Mode Centralisé", 
                [System.Windows.MessageBoxButton]::OK, 
                [System.Windows.MessageBoxImage]::Information
            )
            return
        }

        # CAS B : Mode Autonome -> Action
        if ($Global:AppAzureAuth.UserAuth.Connected) {
            if ([System.Windows.MessageBox]::Show("Se déconnecter ?", "Déconnexion", 'YesNo', 'Question') -eq 'Yes') {
                Disconnect-AppAzureUser
                $Global:AppAzureAuth.UserAuth = @{ Connected = $false }
                & $updateAuthUI
            }
        } else {
            # Tentative de connexion
            $appId = $Global:AppConfig.azure.authentication.userAuth.appId
            $tenantId = $Global:AppConfig.azure.tenantId
            $scopes = $Global:AppConfig.azure.authentication.userAuth.scopes

            if ([string]::IsNullOrWhiteSpace($appId)) {
                [System.Windows.MessageBox]::Show("Config Azure manquante en BDD.", "Erreur", "OK", "Error")
                return
            }

            $res = Connect-AppAzureWithUser -AppId $appId -TenantId $tenantId -Scopes $scopes
            if ($res.Success) {
                $Global:AppAzureAuth.UserAuth = $res
                & $updateAuthUI
            }
        }
    }.GetNewClosure()

    # Attachement
    $authBtn.Add_Click($authClickAction)
    $authTxt.Add_Click($authClickAction)
    
    # Premier rendu
    & $updateAuthUI
}