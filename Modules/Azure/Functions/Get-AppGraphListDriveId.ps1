function Get-AppGraphListDriveId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$SiteId,
        
        [Parameter(Mandatory=$true)]
        [string]$ListDisplayName
    )
    process {
        Write-Verbose "[Get-AppGraphListDriveId] Recherche de la liste '$ListDisplayName'"
        
        # Etape 1 : Obtenir le ListId
        $listId = $null
        try {
            $listRequestUrl = "https://graph.microsoft.com/v1.0/sites/$SiteId/lists?`$select=id,name,displayName"
            $listsRes = Invoke-MgGraphRequest -Method GET -Uri $listRequestUrl -ErrorAction Stop
            
            foreach ($list in $listsRes.value) {
                if ($list.displayName -eq $ListDisplayName -or $list.name -eq $ListDisplayName) {
                    $listId = $list.id
                    break
                }
            }
        } catch {
            Write-Error "Échec de la récupération des listes du site : $($_.Exception.Message)"
            throw $_
        }
        
        if (-not $listId) {
            throw "Impossible de trouver la liste SharePoint '$ListDisplayName' sur le site spécifié."
        }
        
        Write-Verbose "[Get-AppGraphListDriveId] ListId trouvé : $listId. Obtention du DriveId associé..."
        
        # Etape 2 : Obtenir le DriveId (fallback inclus)
        $driveId = $null
        try {
            $driveReqUrl = "https://graph.microsoft.com/v1.0/sites/$SiteId/lists/$listId/drive"
            $driveRes = Invoke-MgGraphRequest -Method GET -Uri $driveReqUrl -ErrorAction Stop
            $driveId = $driveRes.id
        } catch {
            Write-Verbose "[Get-AppGraphListDriveId] Stratégie /drive échouée, fallback sur /drives?`$expand=list"
            try {
                $driveReqUrlFallback = "https://graph.microsoft.com/v1.0/sites/$SiteId/drives?`$expand=list"
                $drivesResFallback = Invoke-MgGraphRequest -Method GET -Uri $driveReqUrlFallback -ErrorAction Stop
                foreach ($drive in $drivesResFallback.value) {
                    if ($drive.list.id -eq $listId) { 
                        $driveId = $drive.id 
                        break
                    }
                }
            } catch {
                Write-Error "Échec du fallback de récupération du DriveId : $($_.Exception.Message)"
                throw $_
            }
        }
        
        if (-not $driveId) {
            throw "Impossible de trouver le Drive ID pour la liste '$ListDisplayName'."
        }
        
        return [PSCustomObject]@{
            ListId  = $listId
            DriveId = $driveId
        }
    }
}
