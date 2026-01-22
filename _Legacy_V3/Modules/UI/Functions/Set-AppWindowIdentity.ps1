function Set-AppWindowIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.Windows.Window]$Window,
        [Parameter(Mandatory)] [object]$UserSession,
        [string]$LauncherPID,
        [scriptblock]$OnConnect,
        [scriptblock]$OnDisconnect
    )

    # Recherche des contrôles UI selon la convention standard
    # Supporte la nomenclature Legacy (ScriptAuthStatusButton) et Standard (Header_AuthButton)
    
    $btn = $Window.FindName("Header_AuthButton")
    if (-not $btn) { $btn = $Window.FindName("ScriptAuthStatusButton") }

    $txt = $Window.FindName("Header_AuthText")
    if (-not $txt) { $txt = $Window.FindName("ScriptAuthTextButton") }

    if (-not $btn -or -not $txt) {
        Write-Verbose "[Set-AppWindowIdentity] Contrôles d'identité introuvables dans la fenêtre."
        return
    }

    # Mise à jour de l'UI
    if ($UserSession.Connected) {
        # --- CONNECTÉ ---
        $btn.Content = $UserSession.Initials
        $btn.ToolTip = "Connecté en tant que $($UserSession.DisplayName)"
        
        try {
            $btn.Background = $Window.FindResource('WhiteBrush')
            $btn.Foreground = $Window.FindResource('PrimaryBrush')
        }
        catch {}

        $txt.Content = $UserSession.DisplayName
        $txt.ToolTip = $UserSession.UserPrincipalName
    } 
    else {
        # --- DÉCONNECTÉ ---
        $iconFunc = {
            $tb = New-Object System.Windows.Controls.TextBlock
            $tb.Text = '👤'
            $tb.FontFamily = 'Segoe UI Symbol'
            $tb.FontSize = 16
            return $tb
        }
        
        $btn.Content = & $iconFunc
        
        try {
            $btn.Background = $Window.FindResource('PrimaryLightBrush')
            $btn.Foreground = $Window.FindResource('WhiteBrush')
        }
        catch {}

        $txt.Content = "Non connecté"
        $txt.ToolTip = "Authentification requise"
    }

    # --- LOGIQUE DU CLIC (INTERACTIVITÉ) ---
    # --- LOGIQUE DE GESTION D'ÉTAT (via .Tag) ---
    # On stocke tout le contexte nécessaire dans le Tag du bouton pour que l'Event Handler puisse le lire
    $context = @{
        UserSession  = $UserSession
        LauncherPID  = $LauncherPID
        OnConnect    = $OnConnect
        OnDisconnect = $OnDisconnect
    }

    # Est-ce la première fois qu'on configure ce bouton ?
    # On utilise le Tag comme indicateur. Si c'est null ou pas notre hashtable, c'est une init.
    $isFirstInit = ($null -eq $btn.Tag)

    # Mise à jour du contexte (pour que le handler existant utilise les nouvelles données)
    $btn.Tag = $context
    $txt.Tag = $context

    if ($isFirstInit) {
        # --- DÉFINITION DU HANDLER UNIQUE ---
        $actionClick = {
            param($sender, $e)
            
            # On récupère le contexte frais depuis le bouton cliqué
            $ctx = $sender.Tag
            
            # 1. Mode Esclave (Launcher) -> Interdit de toucher
            if (-not [string]::IsNullOrWhiteSpace($ctx.LauncherPID)) {
                [System.Windows.MessageBox]::Show(
                    "L'authentification est gérée par le Lanceur principal.", 
                    "Mode Centralisé", 
                    [System.Windows.MessageBoxButton]::OK, 
                    [System.Windows.MessageBoxImage]::Information
                )
                return
            }

            # 2. Mode Autonome -> Actions
            if ($ctx.UserSession.Connected) {
                # Demande de Déconnexion
                if ([System.Windows.MessageBox]::Show("Se déconnecter ?", "Déconnexion", 'YesNo', 'Question') -eq 'Yes') {
                    if ($ctx.OnDisconnect) { & $ctx.OnDisconnect }
                }
            }
            else {
                # Demande de Connexion
                if ($ctx.OnConnect) { & $ctx.OnConnect }
            }
        }

        # On attache l'événement UNE SEULE FOIS
        $btn.add_Click($actionClick)
        $txt.add_Click($actionClick)
        
        Write-Verbose "[Set-AppWindowIdentity] Event Handler attaché (Init)."
    }
    else {
        Write-Verbose "[Set-AppWindowIdentity] Contexte mis à jour (Refresh)."
    }
}
