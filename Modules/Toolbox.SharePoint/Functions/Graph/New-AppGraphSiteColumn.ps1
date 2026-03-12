<#
.SYNOPSIS
    Crée ou met à jour une colonne de site SharePoint via Graph API.

.DESCRIPTION
    Utilise l'endpoint Beta de Microsoft Graph pour gérer les colonnes de site.
    Prend en charge les types de colonnes : Text, Choice, Number, DateTime et Boolean.
    Gère la création de nouvelles colonnes ou la mise à jour (PATCH) des colonnes existantes trouvées par leur nom.

.PARAMETER SiteId
    L'identifiant unique (ID) du site SharePoint.

.PARAMETER Name
    Le nom interne (technique) de la colonne.

.PARAMETER DisplayName
    Le nom d'affichage de la colonne.

.PARAMETER Type
    Le type de donnée de la colonne (Text, Choice, Number, DateTime, Boolean).

.PARAMETER Choices
    (Optionnel) Tableau de chaînes pour les choix (si Type est 'Choice').

.PARAMETER AllowMultiple
    (Optionnel) Indique si la colonne (Choice) autorise les sélections multiples.

.EXAMPLE
    New-AppGraphSiteColumn -SiteId "..." -Name "ProjectStatus" -DisplayName "Statut Projet" -Type "Choice" -Choices @("Actif", "Clos")
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
        [switch]$AllowMultiple
    )
    process {
        Write-Verbose "[New-AppGraphSiteColumn] Vérification de la colonne '$Name' (v1.0 base)..."
        # Utilisation de v1.0 pour le GET sans filtre pour éviter les bugs de parsing d'URL
        $colsUrl = "https://graph.microsoft.com/v1.0/sites/$SiteId/columns"
        
        try {
            # On récupère tout et on filtre en PS pour être sûr à 100% de l'URL
            $allCols = Invoke-MgGraphRequest -Method GET -Uri $colsUrl -ErrorAction Stop
            $existingCol = $allCols.value | Where-Object { $_.name -eq $Name }
            
            # Endpoint Beta pour les opérations d'écriture (POST/PATCH)
            $betaUrl = "https://graph.microsoft.com/beta/sites/$SiteId/columns"
            
            $body = @{ 
                name        = $Name
                displayName = $DisplayName
            }
            
            if ($Type -eq "Choice") {
                if (-not $Choices -or $Choices.Count -eq 0) { $Choices = @("Choix 1") }
                $body["choice"] = @{ 
                    choices        = $Choices
                    allowTextEntry = $true
                    displayAs      = if ($AllowMultiple) { "checkBoxes" } else { "dropDownMenu" }
                }
                if ($AllowMultiple) { $body["allowMultipleValues"] = $true }
            }
            elseif ($Type -eq "Number") {
                $body["number"] = @{}
            }
            elseif ($Type -eq "DateTime") {
                $body["dateTime"] = @{}
            }
            elseif ($Type -eq "Boolean") {
                $body["boolean"] = @{}
            }
            else {
                $body["text"] = @{}
            }

            if ($existingCol) {
                Write-Verbose "[New-AppGraphSiteColumn] Mise à jour de la colonne existante '$Name' (Beta)..."
                $patchUrl = "$betaUrl/$($existingCol.id)"
                
                # Payload pour PATCH : on évite de renvoyer le 'name'
                $patchBody = @{ 
                    displayName = $DisplayName
                }
                if ($Type -eq "Choice") {
                    $patchBody["choice"] = $body["choice"]
                    if ($AllowMultiple) { $patchBody["allowMultipleValues"] = $true }
                }
                elseif ($Type -eq "Number") {
                    $patchBody["number"] = @{}
                }
                elseif ($Type -eq "DateTime") {
                    $patchBody["dateTime"] = @{}
                }
                elseif ($Type -eq "Boolean") {
                    $patchBody["boolean"] = @{}
                }

                $updatedCol = Invoke-MgGraphRequest -Method PATCH -Uri $patchUrl -Body $patchBody -ContentType "application/json" -ErrorAction Stop
                return [PSCustomObject]@{ Status = "Updated"; Column = $updatedCol }
            }
            
            Write-Verbose "[New-AppGraphSiteColumn] Création de la colonne '$Name' de type '$Type' (Beta)..."
            $newCol = Invoke-MgGraphRequest -Method POST -Uri $betaUrl -Body $body -ContentType "application/json" -ErrorAction Stop
            return [PSCustomObject]@{ Status = "Created"; Column = $newCol }
            
        }
        catch {
            $errBody = $body | ConvertTo-Json -Depth 10 -Compress
            Write-Error "Échec de l'opération sur la colonne de site '$Name' : $($_.Exception.Message)"
            Write-Error "Payload envoyé : $errBody"
            if ($_.ErrorDetails) { Write-Error "Détails API : $($_.ErrorDetails.Message)" }
            throw $_
        }
    }
}
