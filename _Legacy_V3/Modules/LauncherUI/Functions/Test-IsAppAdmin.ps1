# Modules/LauncherUI/Functions/Test-IsAppAdmin.ps1

<#
.SYNOPSIS
    Vérifie si l'utilisateur actuel a les droits d'administrateur de l'application.
.DESCRIPTION
    Cette fonction détermine le statut d'administrateur selon les règles suivantes :
    1. Si aucun groupe administrateur n'est défini (première installation), l'accès est accordé.
    2. Si un groupe est défini, l'utilisateur doit être connecté ET membre de ce groupe.
.EXAMPLE
    $isAdmin = Test-IsAppAdmin
.OUTPUTS
    [bool]
#>
function Test-IsAppAdmin {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    Write-Verbose (Get-AppText -Key 'modules.launcherui.admin_check_start')

    try {
        # 1. Récupération des paramètres critiques de sécurité
        $adminGroup = Get-AppSetting -Key 'security.adminGroupName'
        $appId = Get-AppSetting -Key 'azure.auth.user.appId'

        # --- CAS SPÉCIAL : PREMIÈRE CONFIGURATION (BOOTSTRAP) ---
        # Si le groupe admin n'est pas défini OU si l'App ID (nécessaire pour se connecter) manque,
        # on considère que l'application n'est pas encore configurée.
        # On donne les droits admin pour permettre de remplir les paramètres.
        if ([string]::IsNullOrWhiteSpace($adminGroup) -or [string]::IsNullOrWhiteSpace($appId)) {
            Write-Verbose "Configuration incomplète (Groupe Admin ou App ID manquant) : Mode 'Bootstrap' activé (Accès Admin accordé)."
            return $true
        }

        # 2. Si la config est complète, la sécurité s'applique strictement
        if (-not $Global:AppAzureAuth.UserAuth.Connected) {
            Write-Verbose "Configuration présente mais aucun utilisateur connecté : Accès Admin refusé."
            return $false
        }
        
        # 3. Vérification de l'appartenance au groupe
        $userGroups = if ($Global:CurrentUserGroups) { $Global:CurrentUserGroups } else { Get-AppUserAzureGroups }
        if ($userGroups -contains $adminGroup) {
            Write-Verbose (Get-AppText -Key 'modules.launcherui.admin_check_success')
            return $true
        } else {
            Write-Verbose (Get-AppText -Key 'modules.launcherui.admin_check_failure')
            return $false
        }
    } catch {
        $warningMsg = "{0} : $($_.Exception.Message)" -f (Get-AppText 'modules.launcherui.admin_check_error')
        Write-Warning $warningMsg
        return $false
    }
}