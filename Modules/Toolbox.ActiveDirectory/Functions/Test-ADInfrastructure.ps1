# Modules/Toolbox.ActiveDirectory/Functions/Test-ADInfrastructure.ps1

<#
.SYNOPSIS
    Valide la connectivité et la configuration des serveurs d'infrastructure AD.
.DESCRIPTION
    Cette fonction exécute une série de tests pour s'assurer que les serveurs critiques
    sont accessibles et correctement configurés. Elle utilise les identifiants fournis
    pour se connecter à distance au serveur AD Connect.
.PARAMETER ADConnectServer
    Le nom d'hôte du serveur Azure AD Connect.
.PARAMETER TempServer
    Le nom d'hôte du serveur de fichiers temporaires.
.PARAMETER Credential
    L'objet PSCredential du compte de service à utiliser pour la connexion distante.
.OUTPUTS
    [PSCustomObject] - Un objet de résultat avec une propriété 'Success' et des détails sur l'échec.
#>
function Test-ADInfrastructure {
    [CmdletBinding()]
    param(
        [string]$ADConnectServer,
        [string]$TempServer,
        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$Credential # <--- MODIFICATION : Ajout du paramètre Credential
    )

    # --- Pré-validation des entrées ---
    if ([string]::IsNullOrWhiteSpace($ADConnectServer)) {
        throw (Get-AppText -Key 'settings_validation.infra_adconnect_empty')
    }
    if ([string]::IsNullOrWhiteSpace($TempServer)) {
        throw (Get-AppText -Key 'settings_validation.infra_tempserver_empty')
    }

    # --- Test 1 : Connectivité du serveur AD Connect ---
    try {
        Write-Verbose "Test de connectivité vers le serveur AD Connect '$ADConnectServer'..."
        if (-not (Test-Connection -ComputerName $ADConnectServer -Count 1 -Quiet -ErrorAction Stop)) {
            $msg = (Get-AppText 'settings_validation.infra_adconnect_ping_failed') -f $ADConnectServer
            return [PSCustomObject]@{ Success = $false; Target = "ADConnect"; Message = $msg }
        }
    } catch {
        $msg = (Get-AppText 'settings_validation.infra_adconnect_ping_failed') -f $ADConnectServer
        return [PSCustomObject]@{ Success = $false; Target = "ADConnect"; Message = "$msg. Erreur : $($_.Exception.Message)" }
    }

    # --- Test 2 : Présence du service ADSync via Invoke-Command ---
    try {
        Write-Verbose "Vérification du service 'ADSync' sur '$ADConnectServer' via Invoke-Command..."
        
        $result = Invoke-Command -ComputerName $ADConnectServer -ScriptBlock {
            Get-Service -Name 'ADSync' -ErrorAction SilentlyContinue
        } -Credential $Credential -ErrorAction Stop # <--- MODIFICATION : Utilisation des credentials

        if ($null -eq $result) {
            $msg = (Get-AppText 'settings_validation.infra_adsync_not_found') -f $ADConnectServer
            return [PSCustomObject]@{ Success = $false; Target = "ADConnect"; Message = $msg }
        }
    } catch {
        $msg = (Get-AppText 'settings_validation.infra_adsync_not_found') -f $ADConnectServer
        return [PSCustomObject]@{ Success = $false; Target = "ADConnect"; Message = "$msg. Assurez-vous que WinRM est configuré et que l'utilisateur a les droits. Erreur : $($_.Exception.Message)" }
    }

    # --- Test 3 : Connectivité du serveur de fichiers temporaires ---
    try {
        Write-Verbose "Test de connectivité vers le serveur de fichiers temporaires '$TempServer'..."
        if (-not (Test-Connection -ComputerName $TempServer -Count 1 -Quiet -ErrorAction Stop)) {
            $msg = (Get-AppText 'settings_validation.infra_tempserver_ping_failed') -f $TempServer
            return [PSCustomObject]@{ Success = $false; Target = "TempServer"; Message = $msg }
        }
    } catch {
        $msg = (Get-AppText 'settings_validation.infra_tempserver_ping_failed') -f $TempServer
        return [PSCustomObject]@{ Success = $false; Target = "TempServer"; Message = "$msg. Erreur : $($_.Exception.Message)" }
    }

    # --- Tous les tests ont réussi ---
    return [PSCustomObject]@{
        Success = $true
        Message = (Get-AppText 'settings_validation.infra_success_box_message')
    }
}