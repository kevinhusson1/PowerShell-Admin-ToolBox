function Initialize-ToolBoxLogger {
    <#
    .SYNOPSIS
        Initialise le système de logging ToolBox
    
    .DESCRIPTION
        Configure les répertoires de logging et charge la configuration.
        Appelé automatiquement lors du premier usage ou via Initialize-ToolBoxEnvironment.
    #>
    
    [CmdletBinding()]
    param()
    
    try {
        if ($Script:LoggerInitialized) {
            return
        }
        
        # Utilisation des variables globales si disponibles
        if ($Global:ToolBoxLogsPath) {
            $logsPath = $Global:ToolBoxLogsPath
        } else {
            # Fallback si variables globales pas initialisées
            $scriptRoot = $PSScriptRoot
            if (-not $scriptRoot) {
                $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
            }
            $rootPath = Split-Path -Parent (Split-Path -Parent $scriptRoot)
            $logsPath = Join-Path $rootPath "Logs"
        }
        
        $publicLogsPath = Join-Path $logsPath "Public"
        $privateLogsPath = Join-Path $logsPath "Private"
        
        foreach ($path in @($logsPath, $publicLogsPath, $privateLogsPath)) {
            if (-not (Test-Path $path)) {
                New-Item -Path $path -ItemType Directory -Force | Out-Null
                Write-Verbose "Répertoire de logs créé : $path"
            }
        }
        
        # Stockage des chemins pour usage dans le script
        $Script:ToolBoxLogPaths = @{
            Root = $logsPath
            Public = $publicLogsPath
            Private = $privateLogsPath
        }
        
        $Script:LoggerInitialized = $true
        Write-Verbose "Logger ToolBox initialisé avec succès"
    }
    catch {
        Write-Warning "Erreur lors de l'initialisation du logger : $($_.Exception.Message)"
    }
}