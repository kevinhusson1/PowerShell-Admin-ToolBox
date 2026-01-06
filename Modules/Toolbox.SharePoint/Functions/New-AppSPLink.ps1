function New-AppSPLink {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)] [string]$Name,
        [Parameter(Mandatory)] [string]$TargetUrl,
        [Parameter(Mandatory)] [string]$Folder,
        [Parameter(Mandatory = $false)] [PnP.PowerShell.Commands.Base.PnPConnection]$Connection
    )

    begin {
        $result = @{ Success = $true; Message = ""; File = $null }
    }

    process {
        try {
            # 1. Préparation du nom
            $fileName = $Name
            if (-not $fileName.EndsWith(".url")) { $fileName += ".url" }

            Write-Verbose "Création du lien '$fileName' vers '$TargetUrl' dans '$Folder'"

            # 2. Création fichier local temporaire
            # Utilisation de l'encodage ASCII pour compatibilité maximale des raccourcis Internet
            $tempFile = [System.IO.Path]::GetTempFileName()
            # On renomme pour avoir l'extension .url locale (Add-PnPFile préfère ça parfois)
            $tempUrlFile = $tempFile + ".url"
            
            $content = "[InternetShortcut]`r`nURL=$TargetUrl"
            Set-Content -Path $tempUrlFile -Value $content -Encoding ASCII -Force

            # 3. Upload SharePoint
            $params = @{
                Path        = $tempUrlFile
                Folder      = $Folder
                NewFileName = $fileName
                ErrorAction = "Stop"
            }
            if ($Connection) { $params.Connection = $Connection }

            $uploadedFile = Add-PnPFile @params

            # 4. Nettoyage
            if (Test-Path $tempUrlFile) { Remove-Item $tempUrlFile -Force }
            if (Test-Path $tempFile) { Remove-Item $tempFile -Force }

            $result.Message = "Lien créé avec succès."
            $result.File = $uploadedFile
            Write-Verbose $result.Message
        }
        catch {
            $result.Success = $false
            $result.Message = "Erreur création lien : $($_.Exception.Message)"
            Write-Error $result.Message
        }
    }

    end {
        return $result
    }
}
