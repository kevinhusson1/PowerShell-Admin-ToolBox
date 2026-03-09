# Modules/Database/Functions/Get-AppSPFolderSchema.ps1

function Get-AppSPFolderSchema {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$SchemaId
    )
    process {
        if (-not $Global:AppDatabasePath) { throw "La base de données n'est pas initialisée." }

        $query = "SELECT * FROM sp_folder_schemas"
        $sqlParams = @{}

        if (-not [string]::IsNullOrWhiteSpace($SchemaId)) {
            $query += " WHERE SchemaId = @SchemaId"
            $sqlParams.SchemaId = $SchemaId
        }

        try {
            if ($sqlParams.Count -gt 0) {
                return Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $query -SqlParameters $sqlParams -ErrorAction Stop
            } else {
                return Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $query -ErrorAction Stop
            }
        } catch {
            Write-Warning "Erreur lecture modèles de dossiers : $($_.Exception.Message)"
            return $null
        }
    }
}
