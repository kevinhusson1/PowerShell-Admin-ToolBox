# Modules/LauncherUI/Functions/Test-IsAppAdmin.ps1

<#
.SYNOPSIS
    Vérifie si l'utilisateur actuel a les droits d'administrateur de l'application.
.DESCRIPTION
    Cette fonction détermine le statut d'administrateur selon deux règles :
    1. Si l'application est en mode "Système" (aucun utilisateur Azure connecté),
        les droits d'administrateur sont accordés par défaut.
    2. Si un utilisateur Azure est connecté, la fonction vérifie son appartenance
        au groupe d'administration défini dans la base de données.
.EXAMPLE
    $isAdmin = Test-IsAppAdmin
.OUTPUTS
    [bool] - Retourne $true si l'utilisateur est considéré comme un administrateur, $false sinon.
#>
function Test-IsAppAdmin {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    Write-Verbose (Get-AppText -Key 'modules.launcherui.admin_check_start')

    if (-not $Global:AppAzureAuth.UserAuth.Connected) {
        Write-Verbose (Get-AppText -Key 'modules.launcherui.admin_check_system_mode')
        return $true
    }

    $logMsg = "{0} '{1}'" -f (Get-AppText 'modules.launcherui.admin_check_user_connected'), $Global:AppAzureAuth.UserAuth.UserPrincipalName
    Write-Verbose $logMsg

    try {
        $adminGroup = Get-AppSetting -Key 'security.adminGroupName'
        if ([string]::IsNullOrWhiteSpace($adminGroup)) {
            Write-Verbose (Get-AppText -Key 'modules.launcherui.admin_check_no_group')
            return $false
        }
        $logMsg = "{0} '{1}'" -f (Get-AppText 'modules.launcherui.admin_check_group_required'), $adminGroup
        Write-Verbose $logMsg

        $userGroups = Get-AppUserAzureGroups
        
        if ($userGroups -contains $adminGroup) {
            Write-Verbose (Get-AppText -Key 'modules.launcherui.admin_check_success')
            return $true
        } else {
            Write-Verbose (Get-AppText -Key 'modules.launcherui.admin_check_failure')
            return $false
        }
    } catch {
        # Une erreur ici est plus grave qu'un simple verbose, on utilise Write-Warning
        $warningMsg = "{0} : $($_.Exception.Message)" -f (Get-AppText 'modules.launcherui.admin_check_error')
        Write-Warning $warningMsg
        return $false
    }
}