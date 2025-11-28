function Connect-AppAzureWithUser {
    [CmdletBinding()]
    param(
        [string[]]$Scopes = @("User.Read", "GroupMember.Read.All"),
        [Parameter(Mandatory)] [string]$AppId,
        [Parameter(Mandatory)] [string]$TenantId,
        [string]$HintUser # L'email pour le SSO
    )

    try {
        # 1. Est-ce qu'on est déjà connecté DANS CE PROCESSUS ?
        $currentContext = Get-MgContext -ErrorAction SilentlyContinue
        
        # Si on est déjà connecté, on vérifie si c'est le bon user
        if ($currentContext) {
            # On fait un appel léger pour vérifier qui est là
            try {
                $me = Invoke-MgGraphRequest -Uri '/v1.0/me?$select=userPrincipalName' -Method GET -ErrorAction Stop
                
                # Si un Hint est fourni et que ça ne matche pas, on doit se déconnecter
                if (-not [string]::IsNullOrWhiteSpace($HintUser) -and $me.userPrincipalName -ne $HintUser) {
                    Disconnect-MgGraph -ErrorAction SilentlyContinue
                    $currentContext = $null
                } else {
                    # C'est le bon user (ou on s'en fiche), on garde la session
                    # On construit l'objet de retour directement
                    return [PSCustomObject]@{
                        Connected         = $true
                        Success           = $true
                        UserPrincipalName = $me.userPrincipalName
                        # On ne peut pas récupérer le DisplayName facilement ici sans refaire un appel, mais ce n'est pas critique pour le check technique
                        DisplayName       = $me.userPrincipalName 
                        Initials          = "??" 
                    }
                }
            } catch {
                # Token expiré ou invalide
                $currentContext = $null
            }
        }

        # 2. Si pas de contexte valide, ON CONNECTE
        if ($null -eq $currentContext) {
            
            # Paramètres de connexion
            $connectParams = @{
                Scopes = $Scopes
                AppId = $AppId
                TenantId = $TenantId
                NoWelcome = $true
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

        $initials = (($user.DisplayName -split ' ' | Where-Object { $_ }) | ForEach-Object { $_.Substring(0,1) }) -join ''

        return [PSCustomObject]@{
            Connected         = $true
            Success           = $true
            UserPrincipalName = $user.userPrincipalName
            DisplayName       = $user.DisplayName
            Initials          = $initials
        }

    } catch {
        return [PSCustomObject]@{ Success = $false; Connected = $false; ErrorMessage = $_.Exception.Message }
    }
}