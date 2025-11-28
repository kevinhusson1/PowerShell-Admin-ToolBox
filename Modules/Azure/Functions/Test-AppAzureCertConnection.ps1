# Modules/Azure/Functions/Test-AppAzureCertConnection.ps1

<#
.SYNOPSIS
    Teste la validité d'une connexion App-Only (Certificat) via Microsoft Graph.
.DESCRIPTION
    Cette fonction lance un Job indépendant pour tenter une connexion au Tenant
    avec le certificat fourni. Cela permet de valider la configuration sans
    perturber la session utilisateur en cours dans le Launcher.
.PARAMETER TenantId
    L'ID du locataire Azure AD.
.PARAMETER ClientId
    L'App ID de l'application.
.PARAMETER Thumbprint
    L'empreinte du certificat installé dans le magasin courant.
#>
function Test-AppAzureCertConnection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$TenantId,
        [Parameter(Mandatory)] [string]$ClientId,
        [Parameter(Mandatory)] [string]$Thumbprint
    )

    # On utilise un Job pour isoler le contexte de connexion (App-Only) du contexte utilisateur du Launcher
    $job = Start-Job -ScriptBlock {
        param($t, $c, $th)
        try {
            # On tente la connexion Graph en mode App-Only
            Connect-MgGraph -TenantId $t -ClientId $c -CertificateThumbprint $th -NoWelcome -ErrorAction Stop
            
            # On tente une lecture simple pour valider les droits (ex: lire l'info de l'org ou du service principal)
            # Un simple Get-MgContext suffit souvent à valider l'auth, mais un appel API valide les droits
            $context = Get-MgContext
            if ($context) { return $true }
            return $false
        } catch {
            throw $_.Exception.Message
        }
    } -ArgumentList $TenantId, $ClientId, $Thumbprint

    # Attente du résultat (Synchrone pour l'UI car c'est un test ponctuel)
    # On met un timeout de 10s pour ne pas geler l'UI trop longtemps
    $result = $job | Wait-Job -Timeout 10

    if (-not $result) {
        Stop-Job $job
        Remove-Job $job
        return [PSCustomObject]@{ Success = $false; Message = "Délai d'attente dépassé (Timeout)." }
    }

    $output = Receive-Job -Job $job
    $hasError = $job.State -eq 'Failed' -or ($job.ChildJobs[0].Error.Count -gt 0)
    
    # Récupération de l'erreur si existante
    $errorMsg = ""
    if ($hasError) {
        $errorMsg = $job.ChildJobs[0].Error[0].Exception.Message
    }

    Remove-Job $job

    if ($output -eq $true) {
        return [PSCustomObject]@{ Success = $true; Message = "Connexion Certificat (Graph) réussie." }
    } else {
        return [PSCustomObject]@{ Success = $false; Message = "Échec de connexion : $errorMsg" }
    }
}