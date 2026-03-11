$testRoot = "C:\CLOUD\Github\PowerShell-Admin-ToolBox\Scripts\Sharepoint\SharepointTEST\Tests"
. (Join-Path $testRoot "..\Shared\Init-TestEnvironment.ps1")

$tplData = Get-Content (Join-Path $testRoot "..\Data\sp_templates.json") -Raw | ConvertFrom-Json
$schemaData = Get-Content (Join-Path $testRoot "..\Data\sp_folder_schemas.json") -Raw | ConvertFrom-Json
$deployTemplate = $tplData[0]
$deploySchema = $schemaData[0]

$formValues = @{
    "Services"        = "Direction Generale"
    "Rubriques"       = "Administration"
    "DateDeploiement" = (Get-Date).ToString("yyyy-MM-dd")
    "TestBoolean"     = $true
    "Year"            = "2026"
}

Import-Module (Join-Path $testRoot "..\..\..\..\Modules\Toolbox.SharePoint\Toolbox.SharePoint.psd1") -Force

try {
    $res = New-AppSPStructure -TargetSiteUrl $Global:TestTargetSiteUrl `
        -TargetLibraryName $Global:TestTargetLibrary `
        -RootFolderName "E2E_DEBUG_$(Get-Date -Format 'HHmmss')" `
        -StructureJson $deployTemplate.StructureJson `
        -ClientId $Global:TestClientId `
        -Thumbprint $Global:TestThumbprint `
        -TenantName $Global:TestTenantId `
        -FormValues $formValues `
        -FolderSchemaJson $deploySchema.ColumnsJson `
        -FolderSchemaName $deploySchema.DisplayName

    $res.Logs | Out-File (Join-Path $testRoot "e2e_debug_logs.txt")
}
catch {
    $errObj = @{
        Message    = $_.Exception.Message
        Details    = $_.ErrorDetails.Message
        StackTrace = $_.ScriptStackTrace
    } | ConvertTo-Json
    $errObj | Out-File (Join-Path $testRoot "e2e_debug_logs.txt")
}
