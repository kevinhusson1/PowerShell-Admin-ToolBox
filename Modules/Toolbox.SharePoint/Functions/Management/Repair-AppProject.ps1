function Repair-AppProject {
    <#
    .SYNOPSIS
        Répare les éléments divergents d'un projet SharePoint (Métadonnées et Structure)
        en relançant le moteur de déploiement idempotent (New-AppSPStructure).
    
    .PARAMETER TargetUrl
        URL relative du dossier racine du projet.
    
    .PARAMETER Connection
        Connexion PnP PowerShell active.
        
    .PARAMETER TemplateJson
        Le modèle JSON du projet (complet).
        
    .PARAMETER FormValuesJson
        Le JSON des valeurs du formulaire (pour résolution des tags dynamiques et nom racine).
        
    .PARAMETER FormDefinitionJson
        Le JSON de définition du formulaire (pour mapper les champs IsMetadata).
        
    .PARAMETER ClientId
        (Optionnel) ID Client Azure AD.
        
    .PARAMETER Thumbprint
        (Optionnel) Empreinte certificat Azure AD.
        
    .PARAMETER TenantName
        (Optionnel) Nom du tenant.

    .PARAMETER RepairItems
        (Obsolète/Ignoré) Consolidé pour la rétrocompatibilité de l'appel.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetUrl,

        [Parameter(Mandatory = $true)]
        [PnP.PowerShell.Commands.Base.PnPConnection]$Connection,

        [Parameter(Mandatory = $true)]
        [string]$TemplateJson,

        [Parameter(Mandatory = $true)]
        [string]$FormValuesJson,

        [Parameter(Mandatory = $false)]
        [string]$FormDefinitionJson,

        [Parameter(Mandatory = $false)]
        [string]$ClientId,

        [Parameter(Mandatory = $false)]
        [string]$Thumbprint,

        [Parameter(Mandatory = $false)]
        [string]$TenantName,

        [Parameter(Mandatory = $false)]
        $RepairItems # Placeholder for backward-compatibility
    )

    $LogsList = [System.Collections.Generic.List[string]]::new()
    $Errors = @()

    $TargetUrl = [uri]::UnescapeDataString($TargetUrl)

    $ProjectModelName = ""
    $RootMetadataHash = @{}
    $FormValuesHash = @{}

    function Log { 
        param($m, $l = "Info") 
        $LogsList.Add("AppLog: [$l] $m")
        Write-Output "[LOG] AppLog: [$l] $m"
        Write-Verbose "[$l] $m" 
    }

    try {
        Log "Préparation de la réparation globale sur : $TargetUrl"

        if ([string]::IsNullOrWhiteSpace($TemplateJson)) {
            throw "Impossible de réparer le projet : TemplateJson manquant."
        }

        # Conversion des données de formulaire
        try {
            if (-not [string]::IsNullOrWhiteSpace($FormValuesJson)) {
                $fv = $FormValuesJson | ConvertFrom-Json
                $FormValuesHash = $FormValuesJson | ConvertFrom-Json -AsHashtable
                
                if ($fv.PreviewText) { $ProjectModelName = $fv.PreviewText }

                if (-not [string]::IsNullOrWhiteSpace($FormDefinitionJson)) {
                    $fd = $FormDefinitionJson | ConvertFrom-Json
                    foreach ($field in $fd.Layout) {
                        if ($field.IsMetadata -and $null -ne $fv."$($field.Name)" -and $fv."$($field.Name)" -ne "") {
                            $RootMetadataHash[$field.Name] = $fv."$($field.Name)"
                        }
                    }
                }
            }
        }
        catch {
            Log "Erreur parsing JSON de formulaire : $($_.Exception.Message)" "Warning"
        }

        if ([string]::IsNullOrWhiteSpace($ProjectModelName)) {
            $ProjectModelName = $TargetUrl.TrimEnd('/').Split('/')[-1]
            Log "Nom du projet déduit de l'URL : $ProjectModelName" "Warning"
        }

        # Récupération bibliothèque cible
        $allLists = Get-PnPList -Connection $Connection -Includes RootFolder.ServerRelativeUrl, Title
        $list = $allLists | Where-Object { $TargetUrl.StartsWith($_.RootFolder.ServerRelativeUrl, [System.StringComparison]::InvariantCultureIgnoreCase) } | Sort-Object { $_.RootFolder.ServerRelativeUrl.Length } -Descending | Select-Object -First 1

        if (-not $list) {
            throw "Impossible de déterminer la bibliothèque SharePoint (List) pour l'URL cible."
        }

        $TargetLibraryName = $list.Title
        $baseFolderParent = $TargetUrl.Substring(0, $TargetUrl.LastIndexOf('/'))
        if ([string]::IsNullOrWhiteSpace($baseFolderParent)) { $baseFolderParent = "/" }

        $baseTemplateObj = $TemplateJson | ConvertFrom-Json
        $rootFolderNameTemplate = if ($baseTemplateObj.Name) { $baseTemplateObj.Name } else { $ProjectModelName }

        # Paramètres pour New-AppSPStructure
        $deployArgs = @{
            TargetSiteUrl      = $Connection.Url
            TargetLibraryName  = $TargetLibraryName
            TargetFolderUrl    = $baseFolderParent
            RootFolderName     = $rootFolderNameTemplate
            StructureJson      = $TemplateJson
            ClientId           = $ClientId
            Thumbprint         = $Thumbprint
            TenantName         = $TenantName
            FormValues         = $FormValuesHash
            IdMapReferenceJson = $TemplateJson
            ProjectModelName   = $ProjectModelName
            ProjectRootUrl     = $TargetUrl
            RootMetadata       = $RootMetadataHash
        }

        Log "Lancement de New-AppSPStructure (Réparation Idempotente complète) sur $TargetUrl..."
        
        $resDeploy = New-AppSPStructure @deployArgs

        if ($resDeploy.Success) {
            foreach ($logMsg in $resDeploy.Logs) { 
                $txt = if ($logMsg -is [string]) { $logMsg } else { $logMsg.Message }
                Log "(StructureBuilder) $txt" "Info" 
            }
            Log "Réparation effectuée avec succès via le moteur centralisé." "Success"
        }
        else {
            foreach ($err in $resDeploy.Errors) { 
                $Errors += "StructureBuilder Error: $err"
                Log "Erreur Builder : $err" "Error"
            }
            throw "Le déploiement de réparation a rencontré des erreurs."
        }

    }
    catch {
        $Errors += $_.Exception.Message
        Log "Erreur globale réparation : $($_.Exception.Message)" "Error"
    }

    return [PSCustomObject]@{
        Success = ($Errors.Count -eq 0)
        Logs    = $LogsList.ToArray()
        Errors  = $Errors
    }
}
