# Modules/Database/Functions/Remove-AppSPFolderSchema.ps1

function Remove-AppSPFolderSchema {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$SchemaId
    )
    process {
        if (-not $Global:AppDatabasePath) { throw "La base de données n'est pas initialisée." }

        $query = "DELETE FROM sp_folder_schemas WHERE SchemaId = @SchemaId"
        $sqlParams = @{ SchemaId = $SchemaId }

        try {
            Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $query -SqlParameters $sqlParams -ErrorAction Stop
            Write-Verbose "Modèle de dossier '$SchemaId' supprimé avec succès."
        } catch {
            throw "Erreur suppression modèle de dossier : $($_.Exception.Message)"
        }
    }
}
