function Connect-AppChildSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$AuthUPN,
        [Parameter(Mandatory)] [string]$TenantId,
        [Parameter(Mandatory)] [string]$ClientId
    )

    Write-Verbose "[AppChildSession] Tentative de reprise de session silencieuse pour : $AuthUPN"

    try {
        if ([string]::IsNullOrWhiteSpace($AuthUPN)) {
            Write-Warning "[AppChildSession] Aucun UPN fourni."
            return [PSCustomObject]@{ Connected = $false; Error = "No UPN provided" }
        }

        # 1. Connexion via Cache MSAL
        # On utilise le scope 'CurrentUser' explicitement pour taper dans le cache partagé du Launcher
        $scopes = @("User.Read", "User.Read.All", "GroupMember.Read.All")
        
        # Le Launcher s'est connecté, donc le Refresh Token est dans le cache utilisateur Windows.
        # On réutilise ce token pour obtenir un AccessToken valide pour ce nouveau process.
        
        # VERIFICATION PREALABLE : Si on est déjà connecté mais qu'il manque le scope, on sort pour forcer la reco
        $ctx = Get-MgContext -ErrorAction SilentlyContinue
        if ($ctx -and ($ctx.Scopes -notcontains "User.Read.All")) {
            Write-Verbose "[AppChildSession] Scope 'User.Read.All' manquant dans la session active. Déconnexion forcée pour mise à jour."
            Disconnect-MgGraph -ErrorAction SilentlyContinue
        }

        Connect-MgGraph -ClientId $ClientId -TenantId $TenantId -Scopes $scopes -ContextScope CurrentUser -ErrorAction Stop | Out-Null
        
        # 2. Vérification de l'identité réelle (Au cas où le cache contiendrait un autre compte par défaut)
        $context = Get-MgContext
        
        if ($context.Account -ne $AuthUPN) {
            # Déconnexion préventive si ce n'est pas le bon user
            Disconnect-MgGraph -ContextScope CurrentUser -ErrorAction SilentlyContinue
            throw "Mismatch d'identité : Le cache a retourné $($context.Account) alors qu'on attendait $AuthUPN"
        }

        # 3. Récupération du profil frais (Vérifie que le token est bien vivant l'API Graph)
        $me = Invoke-MgGraphRequest -Uri '/v1.0/me?$select=displayName,userPrincipalName' -Method GET -ErrorAction Stop
        
        Write-Verbose "[AppChildSession] Données brutes : $($me | ConvertTo-Json -Depth 1 -Compress)"

        # Fallback si DisplayName vide
        $displayName = if (-not [string]::IsNullOrWhiteSpace($me.DisplayName)) { $me.DisplayName } else { $me.userPrincipalName }

        $initials = "??"
        if ($displayName) {
            $parts = $displayName -split ' ' | Where-Object { $_ }
            if ($parts.Count -gt 0) {
                # On prend max 2 lettres pour les initiales
                $initials = ($parts | Select-Object -First 2 | ForEach-Object { $_.Substring(0, 1) }) -join ''
            }
        }

        Write-Verbose "[AppChildSession] Session validée avec succès pour $($me.userPrincipalName)."

        return [PSCustomObject]@{
            Connected         = $true
            Success           = $true
            UserPrincipalName = $me.userPrincipalName
            DisplayName       = $displayName
            Initials          = $initials
            # On pourrait ajouter ici les groupes si nécessaire
        }

    }
    catch {
        Write-Warning "[AppChildSession] Échec de l'authentification silencieuse : $($_.Exception.Message)"
        return [PSCustomObject]@{
            Connected = $false
            Success   = $false
            Error     = $_.Exception.Message
        }
    }
}
