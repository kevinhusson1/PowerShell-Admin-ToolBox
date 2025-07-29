function Write-ToolBoxLog {
    <#
    .SYNOPSIS
        Écrit une entrée de log dans le système de logging PowerShell Admin ToolBox
    
    .DESCRIPTION
        Cette fonction est le point d'entrée principal pour l'écriture de logs dans l'application.
        Elle utilise le service de logging global et supporte plusieurs destinations simultanément.
    
    .PARAMETER Message
        Le message à enregistrer dans les logs
    
    .PARAMETER Level
        Le niveau de log : Debug, Info, Warning, Error (par défaut : Info)
    
    .PARAMETER Destinations
        Hashtable spécifiant les destinations immédiates pour ce log
        Clés supportées : Console, RichTextBox
    
    .PARAMETER ModuleName
        Nom du module émetteur (optionnel, détecté automatiquement si non spécifié)
    
    .EXAMPLE
        Write-ToolBoxLog -Message "Application démarrée" -Level "Info"
        
        Écrit un log d'information standard
    
    .EXAMPLE
        Write-ToolBoxLog -Message "Erreur critique détectée" -Level "Error" -Destinations @{ Console = $true }
        
        Écrit un log d'erreur avec affichage immédiat en console
    
    .EXAMPLE
        Write-ToolBoxLog -Message "Debug: Variable = $value" -Level "Debug" -ModuleName "UserManagement"
        
        Écrit un log de debug avec nom de module spécifique
    
    .NOTES
        Auteur: PowerShell Admin ToolBox Team
        Date: 01/01/2025
        Version: 1.0.0
        
        Cette fonction nécessite que le module Core soit initialisé avec un LoggingService actif.
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string] $Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("Debug", "Info", "Warning", "Error")]
        [string] $Level = "Info",
        
        [Parameter(Mandatory = $false)]
        [hashtable] $Destinations = @{},
        
        [Parameter(Mandatory = $false)]
        [string] $ModuleName = ""
    )
    
    # Récupération du service de logging global
    $loggingService = $script:LoggingService
    
    if (-not $loggingService) {
        # Fallback en cas de service non initialisé
        $fallbackMessage = "[$((Get-Date).ToString('HH:mm:ss'))] [$Level] $Message"
        
        switch ($Level) {
            "Debug" { Write-Verbose $fallbackMessage }
            "Info" { Write-Information $fallbackMessage -InformationAction Continue }
            "Warning" { Write-Warning $fallbackMessage }
            "Error" { Write-Error $fallbackMessage }
            default { Write-Output $fallbackMessage }
        }
        return
    }
    
    # Ajout du nom de module si spécifié
    $logMessage = $Message
    if (-not [string]::IsNullOrWhiteSpace($ModuleName)) {
        $logMessage = "[$ModuleName] $Message"
    }
    
    # Délégation vers le service de logging
    try {
        $loggingService.WriteLog($logMessage, $Level, $Destinations)
    }
    catch {
        # En cas d'erreur dans le service, fallback vers les cmdlets PowerShell natifs
        $errorMsg = "Erreur service logging: $($_.Exception.Message). Message original: $logMessage"
        Write-Warning $errorMsg
    }
}

function Initialize-ToolBoxLogging {
    <#
    .SYNOPSIS
        Initialise ou reconfigure le système de logging de l'application
    
    .DESCRIPTION
        Cette fonction permet d'initialiser le service de logging avec des paramètres spécifiques
        ou de reconfigurer un service existant.
    
    .PARAMETER LogPath
        Chemin vers le dossier de stockage des fichiers de logs (par défaut : .\logs)
    
    .PARAMETER LogLevel
        Niveau de log minimum : Debug, Info, Warning, Error (par défaut : Info)
    
    .PARAMETER Force
        Force la réinitialisation même si un service existe déjà
    
    .EXAMPLE
        Initialize-ToolBoxLogging -LogPath "C:\MyApp\Logs" -LogLevel "Debug"
        
        Initialise le logging vers un dossier spécifique en mode debug
    
    .EXAMPLE
        Initialize-ToolBoxLogging -Force
        
        Force la réinitialisation du service de logging
    
    .NOTES
        Auteur: PowerShell Admin ToolBox Team
        Date: 01/01/2025
        Version: 1.0.0
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string] $LogPath = ".\logs",
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("Debug", "Info", "Warning", "Error")]
        [string] $LogLevel = "Info",
        
        [Parameter(Mandatory = $false)]
        [switch] $Force
    )
    
    # Vérification si un service existe déjà
    if ($script:LoggingService -and -not $Force) {
        Write-Verbose "Service de logging déjà initialisé. Utilisez -Force pour réinitialiser."
        return $script:LoggingService
    }
    
    # Nettoyage du service existant si présent
    if ($script:LoggingService) {
        try {
            $script:LoggingService.Dispose()
            Write-Verbose "Ancien service de logging nettoyé"
        }
        catch {
            Write-Warning "Erreur nettoyage ancien service: $($_.Exception.Message)"
        }
    }
    
    # Création du nouveau service
    try {
        $script:LoggingService = [LoggingService]::new($LogPath, $LogLevel)
        
        Write-ToolBoxLog -Message "Service de logging initialisé - Path: $LogPath, Level: $LogLevel" -Level "Info"
        
        return $script:LoggingService
    }
    catch {
        Write-Error "Erreur initialisation service de logging: $($_.Exception.Message)"
        return $null
    }
}

function Get-ToolBoxLogPath {
    <#
    .SYNOPSIS
        Obtient le chemin actuel des fichiers de logs
    
    .DESCRIPTION
        Cette fonction retourne le chemin où sont stockés les fichiers de logs
        ou $null si le service n'est pas initialisé.
    
    .EXAMPLE
        $logPath = Get-ToolBoxLogPath
        
        Récupère le chemin des logs actuel
    
    .NOTES
        Auteur: PowerShell Admin ToolBox Team
        Date: 01/01/2025
        Version: 1.0.0
    #>
    
    [CmdletBinding()]
    param()
    
    if ($script:LoggingService) {
        return $script:LoggingService.LogPath
    }
    
    return $null
}

function Set-ToolBoxLogLevel {
    <#
    .SYNOPSIS
        Modifie le niveau de log du service actuel
    
    .DESCRIPTION
        Cette fonction permet de changer dynamiquement le niveau de log
        sans redémarrer l'application.
    
    .PARAMETER Level
        Le nouveau niveau de log : Debug, Info, Warning, Error
    
    .EXAMPLE
        Set-ToolBoxLogLevel -Level "Debug"
        
        Active les logs de debug
    
    .NOTES
        Auteur: PowerShell Admin ToolBox Team
        Date: 01/01/2025
        Version: 1.0.0
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Debug", "Info", "Warning", "Error")]
        [string] $Level
    )
    
    if (-not $script:LoggingService) {
        Write-Error "Service de logging non initialisé. Utilisez Initialize-ToolBoxLogging d'abord."
        return
    }
    
    $script:LoggingService.SetLogLevel($Level)
}

function Get-ToolBoxLogStatistics {
    <#
    .SYNOPSIS
        Obtient les statistiques du service de logging
    
    .DESCRIPTION
        Cette fonction retourne des informations sur l'état actuel du service de logging.
    
    .EXAMPLE
        $stats = Get-ToolBoxLogStatistics
        Write-Host "Queue size: $($stats.QueueSize)"
        
        Affiche la taille de la queue de logs
    
    .NOTES
        Auteur: PowerShell Admin ToolBox Team
        Date: 01/01/2025
        Version: 1.0.0
    #>
    
    [CmdletBinding()]
    param()
    
    if (-not $script:LoggingService) {
        return @{
            Status = "Not Initialized"
            LogPath = $null
            CurrentLogLevel = $null
            QueueSize = 0
            IsDisposed = $true
            SupportedLevels = @("Debug", "Info", "Warning", "Error")
        }
    }
    
    return $script:LoggingService.GetStatistics()
}