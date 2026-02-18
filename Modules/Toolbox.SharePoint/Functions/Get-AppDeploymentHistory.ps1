<#
.SYNOPSIS
    Récupère l'historique des déploiements depuis la liste 'App_DeploymentHistory'.

.DESCRIPTION
    Interroge la liste cachée 'App_DeploymentHistory' sur le site racine configuré.
    Retourne des objets personnalisés contenant les détails du projet et son statut (calculé à la volée ou stocké).

.PARAMETER SiteUrl
    URL du site SharePoint racine où se trouve la liste d'historique.

.EXAMPLE
    Get-AppDeploymentHistory -SiteUrl "https://contoso.sharepoint.com/sites/Intranet"
#>
function Get-AppDeploymentHistory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SiteUrl
    )

    try {
        # Connexion (suppose déjà connectée ou utilise context)
        # Note: Dans le Job Renamer, la connexion est gérée avant
        
        $listName = "App_DeploymentHistory"
        
        # Vérif existence liste
        $list = Get-PnPList -Identity $listName -ErrorAction SilentlyContinue
        if (-not $list) {
            Write-Warning "La liste d'historique '$listName' n'existe pas sur $SiteUrl."
            return @()
        }

        # Query CAML (Tri par Date Décroissante)
        $caml = @"
        <View>
            <Query>
                <OrderBy>
                    <FieldRef Name='DeployedDate' Ascending='FALSE'/>
                </OrderBy>
            </Query>
            <RowLimit>100</RowLimit>
        </View>
"@

        $items = Get-PnPListItem -List $listName -Query $caml

        $results = @()

        foreach ($item in $items) {
            # Mapping des propriétés
            # Note: Les noms internes peuvent différer, on utilise les noms standards créés par New-AppSPTrackingList
            
            $status = "OK" # Par défaut
            $icon = "✅"
            
            # Simple logique de statut (à améliorer avec Test-AppSPDrift)
            # Pour l'instant on se base sur une propriété 'LastStatus' si elle existe, sinon OK
            if ($item["AppStatus"]) { 
                $status = $item["AppStatus"] 
                if ($status -eq 'DRIFT') { $icon = "⚠️" }
                if ($status -eq 'ERROR') { $icon = "❌" }
            }

            $obj = [PSCustomObject]@{
                Title           = $item["Title"] # GUID DeploymentId
                ProjectName     = $item["ProjectName"] # Si colonne ajoutée, sinon extraire de URL ?
                TargetUrl       = $item["TargetUrl"]
                TemplateId      = $item["TemplateId"]
                TemplateVersion = $item["TemplateVersion"]
                ConfigName      = $item["ConfigName"]
                DeployedDate    = $item["DeployedDate"]
                DeployedBy      = $item["DeployedBy"]
                Status          = $status
                StatusIcon      = $icon
                # Meta Data (JSON) pour usage futur
                TemplateJson    = $item["TemplateJson"]
                FormValuesJson  = $item["FormValuesJson"]
            }
            
            # Fallback ProjectName si vide (extraction du dernier segment URL)
            if (-not $obj.ProjectName -and $obj.TargetUrl) {
                $obj.ProjectName = ($obj.TargetUrl -split '/')[-1]
            }

            $results += $obj
        }

        return $results

    }
    catch {
        Write-Error "Erreur lors de la récupération de l'historique : $_"
        return @()
    }
}
