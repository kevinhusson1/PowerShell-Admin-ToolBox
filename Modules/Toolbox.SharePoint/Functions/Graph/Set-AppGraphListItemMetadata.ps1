function Set-AppGraphListItemMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SiteId,
        [Parameter(Mandatory = $true)]
        [string]$ListId,
        [Parameter(Mandatory = $true)]
        [string]$ListItemId,
        [Parameter(Mandatory = $false)]
        [string]$ContentTypeId,
        [Parameter(Mandatory = $false)]
        [hashtable]$Fields
    )
    process {
        Write-Verbose "[Set-AppGraphListItemMetadata] Mise à jour des métadonnées pour l'élément ListItem $ListItemId..."
        
        try {
            # 1. Mise à jour du ContentType (Graph V1.0 Standard)
            if ($ContentTypeId) {
                Write-Verbose "[Set-AppGraphListItemMetadata] Application du Content Type '$ContentTypeId' (V1.0)..."
                $itemUrl = "https://graph.microsoft.com/v1.0/sites/$SiteId/lists/$ListId/items/$ListItemId"
                $itemBody = @{
                    contentType = @{ id = $ContentTypeId }
                } | ConvertTo-Json -Compress
                Invoke-MgGraphRequest -Method PATCH -Uri $itemUrl -Body $itemBody -ContentType "application/json" -ErrorAction Stop | Out-Null
            }
            
            # 2. Mise à jour des champs personnalisés (Graph Beta)
            if ($Fields -and $Fields.keys.Count -gt 0) {
                Write-Verbose "[Set-AppGraphListItemMetadata] Application de $($Fields.keys.Count) champ(s) (Beta)..."
                $fieldsUrl = "https://graph.microsoft.com/beta/sites/$SiteId/lists/$ListId/items/$ListItemId/fields"
                Invoke-MgGraphRequest -Method PATCH -Uri $fieldsUrl -Body $Fields -ContentType "application/json" -ErrorAction Stop | Out-Null
            }
            
            return $true
        }
        catch {
            $errFields = if ($Fields) { $Fields | ConvertTo-Json -Compress } else { "Aucun" }
            Write-Error "Échec de la mise à jour des métadonnées (Champs: $errFields) : $($_.Exception.Message)"
            if ($_.ErrorDetails) { Write-Error "Détails API : $($_.ErrorDetails.Message)" }
            throw $_
        }
    }
}
