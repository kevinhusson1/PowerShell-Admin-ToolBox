function Connect-AppAzureWithUser {
    [CmdletBinding()]
    param(
        [string[]]$Scopes = @("User.Read", "User.Read.All", "GroupMember.Read.All"),
        [Parameter(Mandatory)] [string]$AppId,
        [Parameter(Mandatory)] [string]$TenantId,
        [string]$HintUser # L'email pour le SSO
    )

    try {
        # 1. Est-ce qu'on est déjà connecté DANS CE PROCESSUS ?
        $currentContext = Get-MgContext -ErrorAction SilentlyContinue
        
        # Si on est déjà connecté, on vérifie si c'est le bon user ET si on a les bons droits
        if ($currentContext) {
            # Check Scope Manquant
            if ($currentContext.Scopes -notcontains "User.Read.All") {
                Write-Verbose "[Auth] Scope 'User.Read.All' manquant. Reset de la session."
                Disconnect-MgGraph -ErrorAction SilentlyContinue
                $currentContext = $null
            }
            # On fait un appel léger pour vérifier qui est là
            elseif ($true) {
                # Bloc try/catch original conservé via elseif trucmuche ou juste indentation
                try {
                    $me = Invoke-MgGraphRequest -Uri '/v1.0/me?$select=displayName,userPrincipalName' -Method GET -ErrorAction Stop
                
                    # Si un Hint est fourni et que ça ne matche pas, on doit se déconnecter
                    if (-not [string]::IsNullOrWhiteSpace($HintUser) -and $me.userPrincipalName -ne $HintUser) {
                        Disconnect-MgGraph -ErrorAction SilentlyContinue
                        $currentContext = $null
                    }
                    else {
                        # C'est le bon user (ou on s'en fiche), on garde la session
                    
                        # Fallback DisplayName & Initiales (Code dupliqué pour la robustesse)
                        $displayName = if (-not [string]::IsNullOrWhiteSpace($me.DisplayName)) { $me.DisplayName } else { $me.userPrincipalName }
                        $initials = (($displayName -split ' ' | Where-Object { $_ }) | ForEach-Object { $_.Substring(0, 1) }) -join ''

                        return [PSCustomObject]@{
                            Connected         = $true
                            Success           = $true
                            UserPrincipalName = $me.userPrincipalName
                            DisplayName       = $displayName 
                            Initials          = $initials
                        }
                    }
                }
                catch {
                    # Token expiré ou invalide
                    $currentContext = $null
                }
            }
        }

        # 2. Si pas de contexte valide, ON CONNECTE
        if ($null -eq $currentContext) {
            
            # Paramètres de connexion
            $connectParams = @{
                Scopes      = $Scopes
                AppId       = $AppId
                TenantId    = $TenantId
                NoWelcome   = $true
                ErrorAction = "Stop"
            }

            # Si on a un User Hint (venant du Launcher), on aide MSAL à trouver le token
            # Note: Connect-MgGraph n'a pas de paramètre -Hint direct exposé proprement dans toutes les versions,
            # mais le fait de lancer la commande sur une machine où le token existe suffit généralement.
            
            Connect-MgGraph @connectParams
        }

        # 3. Récupération Infos Utilisateur (Confirmation finale)
        $user = Invoke-MgGraphRequest -Uri '/v1.0/me?$select=displayName,userPrincipalName' -Method GET -ErrorAction Stop

        if (-not $user) { throw "Connexion établie mais impossible de lire le profil." }
        
        Write-Verbose "[Auth] Données brutes reçues : $($user | ConvertTo-Json -Depth 1 -Compress)"

        # Fallback de sécurité : Si le DisplayName est vide (compte technique), on prend l'UPN
        $displayName = if (-not [string]::IsNullOrWhiteSpace($user.DisplayName)) { $user.DisplayName } else { $user.userPrincipalName }

        $initials = (($displayName -split ' ' | Where-Object { $_ }) | ForEach-Object { $_.Substring(0, 1) }) -join ''

        return [PSCustomObject]@{
            Connected         = $true
            Success           = $true
            UserPrincipalName = $user.userPrincipalName
            DisplayName       = $displayName
            Initials          = $initials
        }

    }
    catch {
        return [PSCustomObject]@{ Success = $false; Connected = $false; ErrorMessage = $_.Exception.Message }
    }
}