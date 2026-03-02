$dbPath = "C:\CLOUD\Github\PowerShell-Admin-ToolBox\Config\database.sqlite"
Import-Module "C:\CLOUD\Github\PowerShell-Admin-ToolBox\Vendor\PSSQLite\PSSQLite.psd1" -Force

$tenant = (Invoke-SqliteQuery -DataSource $dbPath -Query "SELECT Value FROM settings WHERE Key='azure.tenantName'").Value
$appId = (Invoke-SqliteQuery -DataSource $dbPath -Query "SELECT Value FROM settings WHERE Key='azure.auth.user.appId'").Value
$thumb = (Invoke-SqliteQuery -DataSource $dbPath -Query "SELECT Value FROM settings WHERE Key='azure.cert.thumbprint'").Value

Write-Output "Tenant: $tenant, AppId: $appId, Thumb: $thumb"

Import-Module PnP.PowerShell
$cleanTenant = $tenant -replace "\.onmicrosoft\.com$", "" -replace "\.sharepoint\.com$", ""

# Ignore graph auth for now
$conn = Connect-PnPOnline -Url 'https://vosgelis365.sharepoint.com/sites/TEST_PNP' -ClientId $appId -Thumbprint $thumb -Tenant "$cleanTenant.onmicrosoft.com" -ReturnConnection -ErrorAction Stop

$items = Get-PnPListItem -List 'App_DeploymentHistory' -Connection $conn -PageSize 1
if ($items) {
    $json = $items[0]["TemplateJson"]
    $outPath = "C:\CLOUD\Github\PowerShell-Admin-ToolBox\extracted_template.json"
    ($json | ConvertFrom-Json) | ConvertTo-Json -Depth 10 -Compress:$false | Out-File $outPath -Encoding UTF8
    Write-Output "Extrait dans $outPath"
} else { "Rien" }
