# Modules/Toolbox.ActiveDirectory/Functions/Test-ADConnection.ps1

<#
.SYNOPSIS
    Exécute une séquence de tests pour valider la configuration Active Directory.
.DESCRIPTION
    Cette fonction exécute trois tests critiques dans l'ordre :
    1. Test de connectivité réseau (Ping) vers le contrôleur de domaine.
    2. Test de résolution DNS du nom de domaine.
    3. Test d'authentification LDAP (bind) avec les identifiants fournis.
    Si un test échoue, la fonction s'arrête et retourne un objet d'erreur détaillé.
.PARAMETER Server
    Le nom court ou le FQDN du contrôleur de domaine à tester.
.PARAMETER Domain
    Le nom de domaine AD (ex: contoso.local).
.PARAMETER Credential
    L'objet PSCredential à utiliser pour le test d'authentification.
.OUTPUTS
    [PSCustomObject] - Un objet avec une propriété 'Success' ($true/$false) et des détails sur l'échec le cas échéant.
#>
function Test-ADConnection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Server,
        [Parameter(Mandatory)] [string]$Domain,
        [Parameter(Mandatory)] [string]$Username,
        [Parameter(Mandatory)] [System.Security.SecureString]$SecurePassword
    )

    $pdcServerFqdn = if ($Server -like "*.*") { $Server } else { "$Server.$Domain" }
    Write-Verbose "Utilisation du FQDN '$pdcServerFqdn' pour les tests."

    # --- Test 1 : Connectivité Réseau ---
    try {
        if (-not (Test-Connection -ComputerName $pdcServerFqdn -Count 1 -Quiet)) {
            return [PSCustomObject]@{ Success = $false; Target = "PDC"; Message = "Serveur '$pdcServerFqdn' injoignable (ping échoué)." }
        }
    } catch {
        return [PSCustomObject]@{ Success = $false; Target = "PDC"; Message = "Erreur réseau vers '$pdcServerFqdn': $($_.Exception.Message)" }
    }
    
    # --- Test 2 : Résolution DNS ---
    try {
        if (-not (Resolve-DnsName -Name $Domain -ErrorAction Stop)) {
            return [PSCustomObject]@{ Success = $false; Target = "Domain"; Message = "Le domaine '$Domain' ne peut pas être résolu par DNS." }
        }
    } catch {
        return [PSCustomObject]@{ Success = $false; Target = "Domain"; Message = "Erreur DNS pour '$Domain': $($_.Exception.Message)" }
    }

    # --- Test 3 : Authentification LDAP ---
    $plainPassword = $null; $bstr = $null
    try {
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword)
        $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        $upn = if ($Username -like "*@*") { $Username } else { "$Username@$Domain" }
        $ldapPath = "LDAP://$pdcServerFqdn"
        $directoryEntry = New-Object System.DirectoryServices.DirectoryEntry($ldapPath, $upn, $plainPassword)
        $null = $directoryEntry.NativeGuid # Force le "bind"
    } catch {
        return [PSCustomObject]@{ Success = $false; Target = "UserPass"; Message = "L'authentification a échoué. Détails : $($_.Exception.Message)" }
    } finally {
        if ($bstr) { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
        if ($plainPassword) { $plainPassword = $null }
        if ($directoryEntry) { $directoryEntry.Dispose() }
        [System.GC]::Collect()
    }

    # Si tous les tests ont réussi
    return [PSCustomObject]@{
        Success = $true
        Message = "Tous les tests ont réussi !"
    }
}