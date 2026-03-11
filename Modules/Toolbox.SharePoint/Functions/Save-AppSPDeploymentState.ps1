# Modules/Toolbox.SharePoint/Functions/Save-AppSPDeploymentState.ps1

<#
.SYNOPSIS
    Sauvegarde l'état d'un déploiement (Mapping ID Editor -> ID SharePoint) dans un fichier caché sur le site.
.DESCRIPTION
    Crée un fichier `.state.json` à la racine du dossier fraîchement déployé.
    Ce fichier permet au Builder de retrouver les dossiers originaux, même s'ils ont
    été renommés ou déplacés manuellement par la suite, facilitant la mise à jour/réparation.
#>
function Save-AppSPDeploymentState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SiteId,
        [Parameter(Mandatory = $true)]
        [string]$StateDriveId,
        [Parameter(Mandatory = $true)]
        [string]$TargetDriveId,
        [Parameter(Mandatory = $true)]
        [string]$RootFolderItemId,
        [Parameter(Mandatory = $true)]
        [hashtable]$DeployedNodes,
        [Parameter(Mandatory = $true)]
        [string]$TemplateId,
        [Parameter(Mandatory = $true)]
        [hashtable]$FormValues
    )
    process {
        Write-Verbose "[Save-AppSPDeploymentState] Sauvegarde de l'état In-Situ..."

        try {
            # Construction de l'objet State
            $stateObj = @{
                Timestamp  = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
                TemplateId = $TemplateId
                FormValues = $FormValues
                Nodes      = $DeployedNodes
            }

            $stateJson = $stateObj | ConvertTo-Json -Depth 5 -Compress
            $stateBytes = [System.Text.Encoding]::UTF8.GetBytes($stateJson)

            # Upload (écrasement si existant) via PUT /root:/{filename}:/content
            $fileName = "${TargetDriveId}_${RootFolderItemId}_state.json"
            $uriUpload = "https://graph.microsoft.com/v1.0/sites/$SiteId/drives/$StateDriveId/root:/$fileName`:/content"

            $res = Invoke-MgGraphRequest -Method PUT -Uri $uriUpload -Body $stateBytes -ContentType "application/json" -ErrorAction Stop
            
            Write-Verbose "[Save-AppSPDeploymentState] État sauvegardé avec succès (FileID: $($res.id))"
            return $true
        }
        catch {
            Write-Error "Impossible de sauvegarder l'état du déploiement : $($_.Exception.Message)"
            if ($_.ErrorDetails) { Write-Error "Détails API : $($_.ErrorDetails.Message)" }
            return $false
        }
    }
}
