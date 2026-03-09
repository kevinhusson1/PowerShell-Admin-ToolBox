# Modules/Database/Functions/Set-AppSPFolderSchema.ps1

function Set-AppSPFolderSchema {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]$SchemaId,
        [Parameter(Mandatory)] [string]$DisplayName,
        [Parameter(Mandatory = $false)] [string]$Description,
        [Parameter(Mandatory)] [string]$ColumnsJson
    )
    process {
        if (-not $Global:AppDatabasePath) { throw "La base de données n'est pas initialisée." }
        
        $DateModified = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

        $query = @"
            INSERT OR REPLACE INTO sp_folder_schemas 
            (SchemaId, DisplayName, Description, ColumnsJson, DateModified) 
            VALUES 
            (@SchemaId, @DisplayName, @Description, @ColumnsJson, @DateModified);
"@
        $sqlParams = @{
            SchemaId      = $SchemaId
            DisplayName   = $DisplayName
            Description   = $Description
            ColumnsJson   = $ColumnsJson
            DateModified  = $DateModified
        }

        try {
            Invoke-SqliteQuery -DataSource $Global:AppDatabasePath -Query $query -SqlParameters $sqlParams -ErrorAction Stop
            Write-Verbose "Modèle de dossier '$DisplayName' ($SchemaId) sauvegardé avec succès."
        } catch {
            throw "Erreur sauvegarde modèle de dossier : $($_.Exception.Message)"
        }
    }
}
