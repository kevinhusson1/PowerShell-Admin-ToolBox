# Modules/Azure/Functions/Test-AppAzureUserConnection.ps1

<#
.SYNOPSIS
    Teste la connexion Azure dans un processus ISOLÉ avec Timeout et Fichiers Temp.
.DESCRIPTION
    Version Anti-Freeze : Utilise des fichiers pour la communication et tue le processus
    si celui-ci met trop de temps à répondre ou si la fenêtre est fermée.
#>
function Test-AppAzureUserConnection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)][string]$TenantId,
        [Parameter(Mandatory)][string[]]$Scopes
    )

    # 1. Préparation
    $scopesString = $Scopes -join ','
    $tempErrorFile = [System.IO.Path]::GetTempFileName()
    
    # 2. Script Sandbox : Écrit dans un fichier au lieu de la console pour éviter le blocage
    $sandboxScriptText = @"
        `$ErrorActionPreference = 'Stop'
        try {
            # Injection
            `$appId = '$AppId'
            `$tenantId = '$TenantId'
            `$scopesStr = '$scopesString'
            `$scopes = `$scopesStr -split ','

            # Connexion
            Connect-MgGraph -AppId `$appId -TenantId `$tenantId -Scopes `$scopes | Out-Null
            Invoke-MgGraphRequest -Uri '/v1.0/me?`$select=id' -Method GET | Out-Null
            
            exit 0
        } catch {
            # On écrit l'erreur dans le fichier temporaire
            `$_.Exception.Message | Set-Content -Path '$tempErrorFile' -Force
            exit 1
        }
"@

    $commandEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($sandboxScriptText))
    
    try {
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = "pwsh.exe"
        $processInfo.Arguments = "-NoProfile -WindowStyle Hidden -EncodedCommand $commandEncoded"
        $processInfo.RedirectStandardError = $false # IMPORTANT : On désactive la redirection standard
        $processInfo.RedirectStandardOutput = $false
        $processInfo.UseShellExecute = $false
        $processInfo.CreateNoWindow = $true

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $processInfo
        $process.Start() | Out-Null
        
        # 3. ATTENTE INTELLIGENTE (Loop avec Timeout)
        # Au lieu de WaitForExit() qui bloque tout, on attend par petits paquets
        $timeoutSeconds = 60
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        while (-not $process.HasExited) {
            # On rend la main au système 100ms pour ne pas geler l'UI
            Start-Sleep -Milliseconds 100
            
            # Sécurité : Si ça dure plus de 60s, on tue tout
            if ($stopwatch.Elapsed.TotalSeconds -gt $timeoutSeconds) {
                $process.Kill()
                return [PSCustomObject]@{ Success = $false; Message = "Délai d'attente dépassé (Timeout). Le test a été annulé." }
            }
        }

        # 4. Analyse
        if ($process.ExitCode -eq 0) {
            if (Test-Path $tempErrorFile) { Remove-Item $tempErrorFile -Force -ErrorAction SilentlyContinue }
            return [PSCustomObject]@{ Success = $true; Message = (Get-AppText 'settings_validation.azure_user_test_success') }
        } else {
            # Lecture du fichier d'erreur
            $errMessage = "Erreur inconnue"
            if (Test-Path $tempErrorFile) {
                $errMessage = Get-Content -Path $tempErrorFile -Raw
                Remove-Item $tempErrorFile -Force -ErrorAction SilentlyContinue
            }
            
            # Nettoyage du message
            $cleanError = $errMessage -replace "[\r\n]", " "
            
            if ($cleanError -match "AADSTS700016" -or $cleanError -match "was not found") {
                $cleanError = "L'Application ID est introuvable dans ce Tenant."
            } elseif ($cleanError -match "User canceled") {
                $cleanError = "La fenêtre de connexion a été fermée."
            }

            return [PSCustomObject]@{ Success = $false; Message = (Get-AppText 'settings_validation.azure_user_test_failure') + "`n`nDétail : $cleanError" }
        }
    } catch {
        return [PSCustomObject]@{ Success = $false; Message = "Erreur interne : $($_.Exception.Message)" }
    }
}