<#
.SYNOPSIS
    Construit un objet PSCredential pour le compte de service Active Directory.
.DESCRIPTION
    Cette fonction détermine intelligemment la source du mot de passe.
    Si l'utilisateur a modifié le champ dans l'interface, elle utilise cette nouvelle valeur.
    Sinon, elle tente de déchiffrer le mot de passe stocké dans la configuration de l'application.
    Elle gère également la construction d'un UPN complet pour une authentification robuste.
.PARAMETER UsernameControl
    Le contrôle TextBox de l'interface contenant le nom d'utilisateur.
.PARAMETER PasswordControl
    Le contrôle PasswordBox de l'interface contenant le mot de passe.
.PARAMETER DomainControl
    Le contrôle TextBox de l'interface contenant le nom de domaine.
.OUTPUTS
    [System.Management.Automation.PSCredential] - L'objet credential prêt à l'emploi.
#>
function Get-ADServiceCredential {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.TextBox]$UsernameControl,

        [Parameter(Mandatory)]
        [System.Windows.Controls.PasswordBox]$PasswordControl,
        
        [Parameter(Mandatory)]
        [System.Windows.Controls.TextBox]$DomainControl
    )

    Write-Verbose "Début de la récupération des identifiants de service AD..."

    # --- Étape 1 : Validation des entrées de base ---
    $username = $UsernameControl.Text.Trim()
    $domain = $DomainControl.Text.Trim()
    
    if ([string]::IsNullOrWhiteSpace($username)) {
        $UsernameControl.Tag = 'Error'
        throw "Le nom d'utilisateur du compte de service est requis."
    }
    
    if ([string]::IsNullOrWhiteSpace($domain)) {
        $DomainControl.Tag = 'Error'
        throw "Le nom du domaine est requis pour construire l'UPN."
    }

    # --- Étape 2 : Détermination de la source du mot de passe ---
    $finalSecurePassword = $null
    
    if ($Global:ADPasswordManuallyChanged -eq $true) {
        Write-Verbose "Utilisation du mot de passe saisi manuellement dans l'interface."
        $finalSecurePassword = $PasswordControl.SecurePassword
        if ($finalSecurePassword.Length -eq 0) {
            $PasswordControl.Tag = 'Error'
            throw "Le champ mot de passe a été modifié mais est maintenant vide."
        }
    }
    elseif (-not [string]::IsNullOrEmpty($Global:AppConfig.ad.servicePassword)) {
        Write-Verbose "Déchiffrement du mot de passe stocké en base de données..."
        try {
            $encryptedBytes = [System.Convert]::FromBase64String($Global:AppConfig.ad.servicePassword)
            $decryptedBytes = [System.Security.Cryptography.ProtectedData]::Unprotect($encryptedBytes, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
            $decryptedString = [System.Text.Encoding]::UTF8.GetString($decryptedBytes)
            $finalSecurePassword = ConvertTo-SecureString -String $decryptedString -AsPlainText -Force
        } catch {
            $PasswordControl.Tag = 'Error'
            throw "Impossible de déchiffrer le mot de passe stocké. Ressaisissez-le manuellement."
        }
    }
    else {
        $PasswordControl.Tag = 'Error'
        throw "Aucun mot de passe n'est disponible. Veuillez le saisir."
    }
    
    # --- Étape 3 : Construction de l'UPN et de l'objet Credential ---
    $upn = if ($username -like "*@*") { $username } else { "$username@$domain" }
    
    Write-Verbose "Construction de l'objet PSCredential pour l'utilisateur '$upn'."
    $credential = New-Object System.Management.Automation.PSCredential($upn, $finalSecurePassword)
    
    # Nettoyage des variables intermédiaires sensibles
    # CORRECTION : Remplacement des 'isset' par la syntaxe correcte
    if (Test-Path "variable:decryptedString") { Remove-Variable decryptedString -Scope Local }
    if (Test-Path "variable:unmanagedString") { Remove-Variable unmanagedString -Scope Local }
    [System.GC]::Collect()

    Write-Verbose "Retour du SecureString final pour l'authentification."
    return $finalSecurePassword
}