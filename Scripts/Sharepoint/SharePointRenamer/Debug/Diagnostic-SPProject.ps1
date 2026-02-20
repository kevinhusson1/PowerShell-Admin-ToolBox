param(
    [string]$SiteUrl = "https://vosgelis365.sharepoint.com/sites/TEST_PNP",
    [string]$FolderUrl = "/sites/TEST_PNP/Shared Documents/General/Nouveau nom"
)

# Résolution automatique de ProjectRoot depuis le nouvel emplacement
# Scripts\Sharepoint\SharePointRenamer\Debug\Diagnostic-SPProject.ps1 -> Racine
$ProjectRoot = (Resolve-Path "$PSScriptRoot\..\..\..\..").Path

# On reproduit le chargement de base de Launcher.ps1 pour avoir la config
$env:PSModulePath = "$($ProjectRoot)\Modules;$($ProjectRoot)\Vendor;$($env:PSModulePath)"

Import-Module "$ProjectRoot\Vendor\PSSQLite" -Force
Import-Module "$ProjectRoot\Modules\Core" -Force
Import-Module "$ProjectRoot\Modules\Database" -Force
Import-Module PnP.PowerShell -Force

# On source directement les fonctions SP
. "$ProjectRoot\Modules\Toolbox.SharePoint\Functions\Connect-AppSharePoint.ps1"
. "$ProjectRoot\Modules\Toolbox.SharePoint\Functions\Logic\Test-AppSPDrift.ps1"
. "$ProjectRoot\Modules\Toolbox.SharePoint\Functions\Logic\Get-AppProjectStatus.ps1"

# BDD et Config
Initialize-AppDatabase -ProjectRoot $ProjectRoot
$Global:AppConfig = Get-AppConfiguration

$ClientId = $Global:AppConfig.azure.authentication.userAuth.appId
$Thumbprint = $Global:AppConfig.azure.certThumbprint
$TenantName = $Global:AppConfig.azure.tenantName

Write-Host "-> Connexion a SharePoint..."
$conn = Connect-AppSharePoint -SiteUrl $SiteUrl -ClientId $ClientId -Thumbprint $Thumbprint -TenantName $TenantName 

# Les fichiers s'enregistrent dans le dossier du script courant
$outDir = $PSScriptRoot

Write-Host "-> Lancement Get-AppProjectStatus pour détecter le Drift..."
$status = Get-AppProjectStatus -SiteUrl $SiteUrl -FolderUrl $FolderUrl -ClientId $ClientId -Thumbprint $Thumbprint -TenantName $TenantName

if (-not $status.IsTracked) {
    Write-Host "ERROR: Dossier non tracké ou erreur : $($status.Error)"
    $status | ConvertTo-Json -Depth 5 | Set-Content "$outDir\StatusError.json" -Encoding UTF8
    exit
}

$history = $status.HistoryItem
$history | ConvertTo-Json -Depth 10 | Set-Content "$outDir\RawHistory.json" -Encoding UTF8
$struct = $history.TemplateJson | ConvertFrom-Json
$form = $history.FormValuesJson | ConvertFrom-Json -AsHashtable

Write-Host "-> Generation du rapport theorique..."
$TheoricLog = [System.Collections.Generic.List[string]]::new()
$TheoricLog.Add("=========================================")
$TheoricLog.Add("RAPPORT THEORIQUE DE DEPLOIEMENT")
$TheoricLog.Add("Deployment ID: $($history.Title)")
$TheoricLog.Add("Date: $($history.DeployedDate)")
$TheoricLog.Add("Config: $($history.ConfigName) (v$($history.TemplateVersion))")
$TheoricLog.Add("")
$TheoricLog.Add("Form Values (Issues de l'UI):")
foreach ($k in $form.Keys) { $TheoricLog.Add(" - $k = $($form[$k])") }
$TheoricLog.Add("=========================================`n")

function Parse-Struct {
    param($node, $path)
    
    if (-not $node) { return }
    if ($node -is [System.Array]) { foreach ($n in $node) { Parse-Struct $n $path }; return }

    if (-not [string]::IsNullOrWhiteSpace($node.Name)) {
        $nodePath = "$path/$($node.Name)"
        $type = if ($node.Type) { $node.Type } else { "Folder" }
        $TheoricLog.Add("[$type] $nodePath")
        
        if ($node.Tags) {
            foreach ($t in $node.Tags) {
                # Resolution tags dynamiques
                $val = "???"
                $varStatus = ""
                if ($t.IsDynamic) {
                    if ($form.ContainsKey($t.SourceVar)) {
                        $val = $form[$t.SourceVar]
                        $varStatus = "(Dynamic -> $($t.SourceVar))"
                    }
                    else {
                        $val = "NULL/MISSING"
                        $varStatus = "(Dynamic -> $($t.SourceVar) INTROUVABLE)"
                    }
                }
                elseif ($t.Value) { $val = $t.Value; $varStatus = "(Static Value)" }
                elseif ($t.Term) { $val = $t.Term; $varStatus = "(Taxonomy Term)" }
                
                $TheoricLog.Add("  -> [TAG] $($t.Name) = '$val' $varStatus")
            }
        }
        
        if ($node.Folders) {
            $TheoricLog.Add("")
            Parse-Struct $node.Folders $nodePath
        }
    }
}

if ($struct.Folders) {
    Parse-Struct $struct.Folders ""
}
else {
    Parse-Struct $struct ""
}

$TheoricLog | Set-Content "$outDir\TheoricDeployment.txt" -Encoding UTF8


Write-Host "-> Export du résultat d'Analyse (Drift)..."
# Conversion en tableau lisible
$actualStatus = [System.Collections.Generic.List[string]]::new()
$actualStatus.Add("=========================================")
$actualStatus.Add("ETAT REEL ET DIVERGENCES (DRIFT)")
$actualStatus.Add("MetaStatus : $($status.Drift.MetaStatus)")
$actualStatus.Add("StructStatus : $($status.Drift.StructureStatus)")
$actualStatus.Add("=========================================`n")

if ($status.Drift.MetaDrifts) {
    $actualStatus.Add("--- METADATA DRIFTS ---")
    foreach ($d in $status.Drift.MetaDrifts) { $actualStatus.Add($d) }
    $actualStatus.Add("")
}
if ($status.Drift.StructureMisses) {
    $actualStatus.Add("--- STRUCTURE MISSES ---")
    foreach ($m in $status.Drift.StructureMisses) { $actualStatus.Add($m) }
    $actualStatus.Add("")
}

if ($status.Drift.AuditLog) {
    $actualStatus.Add("--- AUDIT LOG (PARCOURS) ---")
    foreach ($l in $status.Drift.AuditLog) { $actualStatus.Add($l) }
}

$actualStatus | Set-Content "$outDir\ActualDriftStatus.txt" -Encoding UTF8

Write-Host "-> Termine ! Logs enregistres dans $outDir"
