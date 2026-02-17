# Modules/Toolbox.SharePoint/Functions/New-AppSPTrackingList.ps1

<#
.SYNOPSIS
    Vérifie et provisionne la liste de suivi de déploiement "App_DeploymentHistory".

.DESCRIPTION
    Crée une liste cachée (Hidden) sur le site cible si elle n'existe pas.
    Configure les colonnes nécessaires pour stocker l'historique des déploiements.

.PARAMETER Connection
    La connexion PnP active.

.OUTPUTS
    [bool] $true si succès.
#>
function New-AppSPTrackingList {
    param(
        [Parameter(Mandatory)] $Connection
    )

    $ListName = "App_DeploymentHistory"

    try {
        # 1. Vérification Existence
        $list = Get-PnPList -Identity $ListName -Connection $Connection -ErrorAction SilentlyContinue

        if (-not $list) {
            Write-Host "Création de la liste de suivi '$ListName'..." -ForegroundColor Cyan
            
            # Création Liste (Template GenericList = 100)
            $list = New-PnPList -Title $ListName -Template GenericList -Connection $Connection -ErrorAction Stop
            
            # Masquer la liste
            $list.Hidden = $true
            $list.Update()
            $Connection.ExecuteQuery()
        }

        # 2. Vérification / Création des Champs
        # Note: 'Title' est utilisé pour le DeploymentId (GUID)

        $fields = @(
            @{ Name = "TargetUrl"; Type = "Text" },
            @{ Name = "TemplateId"; Type = "Text" },
            @{ Name = "TemplateVersion"; Type = "Text" },
            @{ Name = "ConfigName"; Type = "Text" },
            @{ Name = "NamingRuleId"; Type = "Text" },
            @{ Name = "DeployedBy"; Type = "Text" },
            @{ Name = "TemplateJson"; Type = "Note" }, # Multi-line
            @{ Name = "FormValuesJson"; Type = "Note" }, # Multi-line
            @{ Name = "FormDefinitionJson"; Type = "Note" } # Multi-line - Form Schema
        )

        foreach ($f in $fields) {
            # Check if exists
            $exField = Get-PnPField -List $ListName -Identity $f.Name -Connection $Connection -ErrorAction SilentlyContinue
            
            if (-not $exField) {
                Write-Host "Ajout colonne '$($f.Name)'..." -ForegroundColor DarkGray
                if ($f.Type -eq "Note") {
                    # XML requis pour Multiline spécifique
                    $fXml = "<Field Type='Note' Name='$($f.Name)' DisplayName='$($f.Name)' NumLines='6' RichText='FALSE' Sortable='FALSE' />"
                    Add-PnPFieldFromXml -List $ListName -FieldXml $fXml -Connection $Connection | Out-Null
                }
                else {
                    # Standard Creation
                    Add-PnPField -List $ListName -DisplayName $f.Name -InternalName $f.Name -Type Text -Connection $Connection | Out-Null
                }
            }
        }
        $list.Update()
        $Connection.ExecuteQuery()

        return $true
    }
    catch {
        Write-Error "Erreur provisionning liste '$ListName' : $($_.Exception.Message)"
        return $false
    }
}
