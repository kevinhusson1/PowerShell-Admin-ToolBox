<#
.SYNOPSIS
    Crée ou met à jour une colonne de site SharePoint via Graph API (v1.0).
.DESCRIPTION
    Utilise l'endpoint v1.0 de Microsoft Graph pour gérer les colonnes de site.
    Prend en charge les types de colonnes : Text, Choice, Number, DateTime et Boolean.
#>
function New-AppGraphSiteColumn {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SiteId,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$DisplayName,
        [Parameter(Mandatory = $true)]
        [ValidateSet("Text", "Choice", "Number", "DateTime", "Boolean")]
        [string]$Type,
        [Parameter(Mandatory = $false)]
        [string[]]$Choices,
        [Parameter(Mandatory = $false)]
        [switch]$AllowMultiple,
        [Parameter(Mandatory = $false)]
        [switch]$Indexed,
        [Parameter(Mandatory = $false)]
        [PSCustomObject]$ColumnCache
    )
    process {
        Write-Verbose "[New-AppGraphSiteColumn] Début pour '$Name' ($Type, Multi: $($AllowMultiple.IsPresent), Indexed: $($Indexed.IsPresent))"
        # On utilise une construction d'URL très explicite pour éviter tout problème d'interpolation
        $AbsoluteBaseUrl = "https://graph.microsoft.com/v1.0/sites/$SiteId/columns"
        
        try {
            $existingCol = $null
            if ($ColumnCache -and $ColumnCache.value) {
                # Recherche dans le cache
                $existingCol = $ColumnCache.value | Where-Object { $_.name -eq $Name -or ($_.displayName -eq $DisplayName -and $_.columnGroup -ne "Built-in") }
            }
            else {
                # Récupération en direct
                $diagUrl = $AbsoluteBaseUrl + "?`$select=id,name,displayName,columnGroup,indexed,choice"
                $allCols = Invoke-MgGraphRequest -Method GET -Uri $diagUrl -ErrorAction Stop
                $existingCol = $allCols.value | Where-Object { $_.name -eq $Name -or ($_.displayName -eq $DisplayName -and $_.columnGroup -ne "Built-in") }
            }
            
            # Construction du corps (POST)
            $body = @{ 
                name        = $Name
                displayName = $DisplayName
                indexed     = $Indexed.IsPresent
            }
            
            if ($Type -eq "Choice") {
                if (-not $Choices -or $Choices.Count -eq 0) { $Choices = @("Choix 1") }
                $body["choice"] = @{ 
                    choices        = $Choices
                    allowTextEntry = $true
                    displayAs      = if ($AllowMultiple) { "checkBoxes" } else { "dropDownMenu" }
                }
                # Pour Graph v1.0, allowMultipleValues est à la racine
                if ($AllowMultiple) { $body["allowMultipleValues"] = $true }
            }
            elseif ($Type -eq "Number") { $body["number"] = @{} }
            elseif ($Type -eq "DateTime") { $body["dateTime"] = @{} }
            elseif ($Type -eq "Boolean") { $body["boolean"] = @{} }
            else { $body["text"] = @{} }

            if ($existingCol) {
                Write-Verbose "[New-AppGraphSiteColumn] Mise à jour de la colonne '$Name' (v1.0)..."
                $patchUrl = $AbsoluteBaseUrl + "/" + $existingCol.id
                
                # Payload pour PATCH : pas de 'name'
                $patchBody = @{ 
                    displayName = $DisplayName
                    indexed     = $Indexed.IsPresent
                }
                if ($Type -eq "Choice") {
                    $patchBody["choice"] = $body["choice"]
                    if ($AllowMultiple) { $patchBody["allowMultipleValues"] = $true }
                }
                elseif ($Type -eq "Number") { $patchBody["number"] = @{} }
                elseif ($Type -eq "DateTime") { $patchBody["dateTime"] = @{} }
                elseif ($Type -eq "Boolean") { $patchBody["boolean"] = @{} }
                else { $patchBody["text"] = @{} }

                $jsonBody = $patchBody | ConvertTo-Json -Depth 10 -Compress
                $updatedCol = Invoke-MgGraphRequest -Method PATCH -Uri $patchUrl -Body $jsonBody -ContentType "application/json" -ErrorAction Stop
                return [PSCustomObject]@{ Status = "Updated"; Column = $updatedCol }
            }
            else {
                Write-Verbose "[New-AppGraphSiteColumn] Création de la colonne '$Name' (v1.0)..."
                $jsonBody = $body | ConvertTo-Json -Depth 10 -Compress
                $newCol = Invoke-MgGraphRequest -Method POST -Uri $AbsoluteBaseUrl -Body $jsonBody -ContentType "application/json" -ErrorAction Stop
                return [PSCustomObject]@{ Status = "Created"; Column = $newCol }
            }
        }
        catch {
            Write-Error "Échec de l'opération sur la colonne de site '$Name' : $($_.Exception.Message)"
            if ($_.ErrorDetails) { Write-Error "Détails API : $($_.ErrorDetails.Message)" }
            throw $_
        }
    }
}
