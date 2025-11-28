# Scripts/SharePoint/SharePointBuilder/Functions/Enable-ScriptIdentity.ps1

<#
.SYNOPSIS
    Active et gère le module d'identité (Basé sur le modèle DefaultUI).
    Ajoute la couche de connexion PnP (App-Only) automatique.
#>
function Enable-ScriptIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.Windows.Window]$Window,
        [string]$LauncherPID,
        [Parameter()] [string]$AuthContext
    )

    # 1. Initialisation de la variable globale
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
    }

    # 3. Récupération des contrôles UI
    $authBtn = $Window.FindName("ScriptAuthStatusButton")
    $authTxt = $Window.FindName("ScriptAuthTextButton")
    
    # Spécifique SharePoint Builder : Les labels de statut
    $debugGraph = $Window.FindName("DebugGraphStatus")
    $debugPnP = $Window.FindName("DebugPnPStatus")

    if (-not $authBtn -or -not $authTxt) { return }

    # 4. Logique de mise à jour UI & Connexion Moteur
    $updateAuthUI = {
        # On force le rafraîchissement de l'objet global
        $user = $Global:AppAzureAuth.UserAuth
        
        if ($user.Connected) {
            # --- CONNECTÉ (GRAPH) ---
            $authBtn.Content = $user.Initials
            $authBtn.ToolTip = $user.DisplayName
            $authBtn.Background = $Window.FindResource('WhiteBrush')
            $authBtn.Foreground = $Window.FindResource('PrimaryBrush')
            
            $authTxt.Content = $user.DisplayName
            $authTxt.ToolTip = "Cliquez pour gérer la connexion"

            # Mise à jour Label Graph
            if ($debugGraph) {
                $debugGraph.Text = "CONNECTÉ"
                $debugGraph.Foreground = $Window.FindResource('SuccessBrush')
            }

            # --- DÉCLENCHEMENT PnP (Certificat) ---
            # On lance ça en tâche de fond simple pour ne pas bloquer le rendu du macaron
            $Window.Dispatcher.InvokeAsync([Action]{
                if ($debugPnP) { 
                    $debugPnP.Text = "CONNEXION..."
                    $debugPnP.Foreground = $Window.FindResource('WarningBrush')
                }

                # Récupération Config
                $tenantName = $Global:AppConfig.azure.tenantName
                $appId = $Global:AppConfig.azure.authentication.userAuth.appId
                $thumbprint = $Global:AppConfig.azure.certThumbprint

                # Fallback Tenant Name si vide (déduit de l'UPN)
                if ([string]::IsNullOrWhiteSpace($tenantName)) {
                    $parts = $user.UserPrincipalName.Split('@')
                    if ($parts[1] -eq "vosgelis.fr") { $tenantName = "vosgelis365" }
                    elseif ($parts[1] -like "*.onmicrosoft.com") { $tenantName = $parts[1].Split('.')[0] }
                }

                if ([string]::IsNullOrWhiteSpace($tenantName) -or [string]::IsNullOrWhiteSpace($thumbprint)) {
                    if ($debugPnP) { 
                        $debugPnP.Text = "CONFIG MANQUANTE"
                        $debugPnP.Foreground = $Window.FindResource('DangerBrush') 
                    }
                    return
                }

                # Connexion
                Import-Module "$($Global:ProjectRoot)\Modules\Toolbox.SharePoint" -Force
                $pnpSuccess = Connect-AppSharePoint -TenantName $tenantName -ClientId $appId -Thumbprint $thumbprint
                
                if ($debugPnP) {
                    if ($pnpSuccess) {
                        $debugPnP.Text = "PRÊT ($tenantName)"
                        $debugPnP.Foreground = $Window.FindResource('SuccessBrush')
                    } else {
                        $debugPnP.Text = "ÉCHEC CERTIF"
                        $debugPnP.Foreground = $Window.FindResource('DangerBrush')
                    }
                }
            }, [System.Windows.Threading.DispatcherPriority]::Background) | Out-Null

        } else {
            # --- DÉCONNECTÉ ---
            $iconContent = New-Object System.Windows.Controls.TextBlock
            $iconContent.Text = '👤'
            $iconContent.FontFamily = 'Segoe UI Symbol'
            $iconContent.FontSize = 16
            
            $authBtn.Content = $iconContent
            $authBtn.Background = $Window.FindResource('PrimaryLightBrush')
            $authBtn.Foreground = $Window.FindResource('WhiteBrush')
            
            $authTxt.Content = "Se connecter"
            $authTxt.ToolTip = "Cliquez pour vous authentifier"

            if ($debugGraph) {
                $debugGraph.Text = "NON CONNECTÉ"
                $debugGraph.Foreground = $Window.FindResource('DangerBrush')
            }
            if ($debugPnP) {
                $debugPnP.Text = "EN ATTENTE"
                $debugPnP.Foreground = $Window.FindResource('TextSecondaryBrush')
            }

            # Nettoyage PnP
            if (Get-Module PnP.PowerShell) {
                try { Disconnect-PnPOnline -ErrorAction SilentlyContinue } catch {}
            }
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

            # On utilise la fonction robuste du module Azure qui gère le SSO
            $res = Connect-AppAzureWithUser -AppId $appId -TenantId $tenantId -Scopes $scopes
            if ($res.Success) {
                $Global:AppAzureAuth.UserAuth = $res
                & $updateAuthUI
            }
        }
    }.GetNewClosure()

    # Attachement des événements
    $authBtn.Add_Click($authClickAction)
    $authTxt.Add_Click($authClickAction)
    
    # 6. Démarrage (Récupération SSO au lancement)
    # On ajoute juste cette petite logique auto pour ne pas avoir à cliquer si on est déjà logué dans Windows
    if ($Global:AppAzureAuth.UserAuth.Connected -eq $false -and [string]::IsNullOrWhiteSpace($LauncherPID)) {
        $Window.Dispatcher.InvokeAsync([Action]{
            $appId = $Global:AppConfig.azure.authentication.userAuth.appId
            $tenantId = $Global:AppConfig.azure.tenantId
            $scopes = $Global:AppConfig.azure.authentication.userAuth.scopes
            
            if ($appId) {
                # Tentative silencieuse (utilise le cache WAM si dispo)
                $res = Connect-AppAzureWithUser -AppId $appId -TenantId $tenantId -Scopes $scopes
                if ($res.Success) {
                    $Global:AppAzureAuth.UserAuth = $res
                }
            }
            & $updateAuthUI
        }, [System.Windows.Threading.DispatcherPriority]::Background) | Out-Null
    } else {
        # Sinon mise à jour simple (cas Launcher ou déjà connecté)
        & $updateAuthUI
    }
}