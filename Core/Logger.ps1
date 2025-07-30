<#
.SYNOPSIS
    Framework de logging multi-destinations pour PowerShell Admin ToolBox

.DESCRIPTION
    Fournit un système de logging centralisé avec support pour multiple destinations :
    Console, Fichiers (Public/Private), UI en temps réel.

.NOTES
    Auteur: PowerShell Admin ToolBox Team
    Version: 1.0
    Création: 30 Juillet 2025
#>

# Variables script pour le logging
$Script:ToolBoxLogBuffer = @()
$Script:LoggerInitialized = $false
$Script:ToolBoxLogPaths = $null

function Initialize-ToolBoxLogger {
    <#
    .SYNOPSIS
        Initialise le système de logging
    
    .DESCRIPTION
        Configure les répertoires de logging et charge la configuration.
        Appelé automatiquement lors du premier usage.
    #>
    
    [CmdletBinding()]
    param()
    
    try {
        if ($Script:LoggerInitialized) {
            return
        }
        
        # Chargement de la configuration si pas déjà fait
        if (-not $Global:ToolBoxConfig) {
            # Tentative de chargement de la config via le script parent
            $configLoaderPath = Join-Path $PSScriptRoot "ConfigLoader.ps1"
            if (Test-Path $configLoaderPath) {
                . $configLoaderPath
                Import-ToolBoxConfig
            }
        }
        
        # Détermination du répertoire racine
        $scriptRoot = $PSScriptRoot
        if (-not $scriptRoot) {
            $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
        }
        $rootPath = Split-Path -Parent $scriptRoot
        
        # Création des répertoires de logs
        $logsPath = Join-Path $rootPath "Logs"
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

function Write-ToolBoxLog {
    <#
    .SYNOPSIS
        Écrit un message de log vers les destinations configurées
    
    .DESCRIPTION
        Fonction principale de logging avec support multi-destinations et niveaux.
    
    .PARAMETER Level
        Niveau de log : Debug, Info, Warning, Error, Private
    
    .PARAMETER Message
        Message à logger
    
    .PARAMETER Component
        Composant/Module source du log (ex: UserManagement, SystemInfo)
    
    .PARAMETER Console
        Afficher dans la console (défaut: $true)
    
    .PARAMETER File
        Écrire dans un fichier (défaut: $false)
    
    .PARAMETER UI
        Stocker pour affichage UI (défaut: $false)
    
    .PARAMETER ShowTimestamp
        Inclure l'horodatage dans le message (défaut: $true)
    
    .EXAMPLE
        Write-ToolBoxLog -Level "Info" -Message "Opération terminée" -Component "UserManagement"
        
    .EXAMPLE
        Write-ToolBoxLog -Level "Error" -Message "Échec connexion" -Component "Auth" -File $true
        
    .EXAMPLE
        Write-ToolBoxLog -Level "Private" -Message "Token reçu" -Component "Auth" -File $true
        
    .EXAMPLE
        Write-ToolBoxLog -Level "Debug" -Message "État UI" -Component "Launcher" -UI $true -ShowTimestamp $false
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Debug", "Info", "Warning", "Error", "Private")]
        [string]$Level,
        
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $true)]
        [string]$Component,
        
        [Parameter(Mandatory = $false)]
        [bool]$Console = $true,
        
        [Parameter(Mandatory = $false)]
        [bool]$File = $false,
        
        [Parameter(Mandatory = $false)]
        [bool]$UI = $false,
        
        [Parameter(Mandatory = $false)]
        [bool]$ShowTimestamp = $true
    )
    
    try {
        # Initialisation automatique si nécessaire
        if (-not $Script:LoggerInitialized) {
            Initialize-ToolBoxLogger
        }
        
        # Construction du message
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        
        if ($ShowTimestamp) {
            $logMessage = "[$timestamp] [$($Level.ToUpper())] [$Component] $Message"
        } else {
            $logMessage = "[$($Level.ToUpper())] [$Component] $Message"
        }
        
        # Affichage Console
        if ($Console) {
            Write-LogToConsole -Level $Level -Message $logMessage
        }
        
        # Écriture Fichier
        if ($File) {
            Write-LogToFile -Level $Level -Message $logMessage -Component $Component -Timestamp $timestamp
        }
        
        # Stockage UI
        if ($UI) {
            Add-LogToUIBuffer -Level $Level -Message $Message -Component $Component -Timestamp $timestamp -ShowTimestamp $ShowTimestamp
        }
    }
    catch {
        Write-Warning "Erreur lors de l'écriture du log : $($_.Exception.Message)"
    }
}

function Write-LogToConsole {
    <#
    .SYNOPSIS
        Affiche le log dans la console avec couleurs selon le niveau
    #>
    
    [CmdletBinding()]
    param(
        [string]$Level,
        [string]$Message
    )
    
    switch ($Level) {
        "Debug"   { Write-Host $Message -ForegroundColor Cyan }
        "Info"    { Write-Host $Message -ForegroundColor Green }
        "Warning" { Write-Host $Message -ForegroundColor Yellow }
        "Error"   { Write-Host $Message -ForegroundColor Red }
        "Private" { Write-Host $Message -ForegroundColor Magenta }
    }
}

function Write-LogToFile {
    <#
    .SYNOPSIS
        Écrit le log dans un fichier avec rotation par composant et date
    #>
    
    [CmdletBinding()]
    param(
        [string]$Level,
        [string]$Message,
        [string]$Component,
        [string]$Timestamp
    )
    
    try {
        if (-not $Script:ToolBoxLogPaths) {
            return
        }
        
        # Détermination du répertoire selon le niveau
        $logDirectory = if ($Level -eq "Private") { 
            $Script:ToolBoxLogPaths.Private 
        } else { 
            $Script:ToolBoxLogPaths.Public 
        }
        
        # Construction du nom de fichier
        $dateString = Get-Date -Format "yyyy-MM-dd"
        $fileName = "$Component`_$dateString.log"
        $filePath = Join-Path $logDirectory $fileName
        
        # Écriture dans le fichier
        Add-Content -Path $filePath -Value $Message -Encoding UTF8
        
        # Gestion de la rotation des fichiers (optionnel)
        if ($Global:ToolBoxConfig -and $Global:ToolBoxConfig.Logging.FileRetentionDays) {
            Remove-OldLogFiles -Directory $logDirectory -RetentionDays $Global:ToolBoxConfig.Logging.FileRetentionDays
        }
    }
    catch {
        Write-Warning "Erreur lors de l'écriture du fichier de log : $($_.Exception.Message)"
    }
}

function Add-LogToUIBuffer {
    <#
    .SYNOPSIS
        Ajoute le log au buffer UI pour affichage temps réel
    #>
    
    [CmdletBinding()]
    param(
        [string]$Level,
        [string]$Message,
        [string]$Component,
        [string]$Timestamp,
        [bool]$ShowTimestamp
    )
    
    $logEntry = [PSCustomObject]@{
        Timestamp = $Timestamp
        Level = $Level
        Component = $Component
        Message = $Message
        ShowTimestamp = $ShowTimestamp
        FormattedMessage = if ($ShowTimestamp) { 
            "[$($Level.ToUpper())] [$Component] $Message" 
        } else { 
            "[$($Level.ToUpper())] [$Component] $Message" 
        }
    }
    
    # Ajout au buffer script (limité à 1000 entrées pour éviter la surcharge mémoire)
    $Script:ToolBoxLogBuffer += $logEntry
    if ($Script:ToolBoxLogBuffer.Count -gt 1000) {
        $Script:ToolBoxLogBuffer = $Script:ToolBoxLogBuffer[-900..-1]  # Garde les 900 dernières
    }
}

function Get-ToolBoxLogBuffer {
    <#
    .SYNOPSIS
        Récupère les logs stockés pour l'UI
    
    .PARAMETER Level
        Filtrer par niveau de log
    
    .PARAMETER Component
        Filtrer par composant
    
    .PARAMETER Last
        Récupérer seulement les X dernières entrées
    
    .EXAMPLE
        Get-ToolBoxLogBuffer -Last 50
        
    .EXAMPLE
        Get-ToolBoxLogBuffer -Level "Error" -Component "UserManagement"
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Level,
        
        [Parameter(Mandatory = $false)]
        [string]$Component,
        
        [Parameter(Mandatory = $false)]
        [int]$Last
    )
    
    $logs = $Script:ToolBoxLogBuffer
    
    # Filtrage par niveau
    if ($Level) {
        $logs = $logs | Where-Object { $_.Level -eq $Level }
    }
    
    # Filtrage par composant
    if ($Component) {
        $logs = $logs | Where-Object { $_.Component -eq $Component }
    }
    
    # Limitation du nombre d'entrées
    if ($Last -and $logs.Count -gt $Last) {
        $logs = $logs[-$Last..-1]
    }
    
    return $logs
}

function Clear-ToolBoxLogBuffer {
    <#
    .SYNOPSIS
        Vide le buffer de logs UI
    #>
    
    $Script:ToolBoxLogBuffer = @()
    Write-Verbose "Buffer de logs UI vidé"
}

function Remove-OldLogFiles {
    <#
    .SYNOPSIS
        Supprime les anciens fichiers de log selon la rétention configurée
    #>
    
    [CmdletBinding()]
    param(
        [string]$Directory,
        [int]$RetentionDays
    )
    
    try {
        $cutoffDate = (Get-Date).AddDays(-$RetentionDays)
        $oldFiles = Get-ChildItem -Path $Directory -Filter "*.log" | Where-Object { 
            $_.LastWriteTime -lt $cutoffDate 
        }
        
        foreach ($file in $oldFiles) {
            Remove-Item -Path $file.FullName -Force
            Write-Verbose "Fichier de log supprimé : $($file.Name)"
        }
    }
    catch {
        Write-Warning "Erreur lors de la suppression des anciens logs : $($_.Exception.Message)"
    }
}

function Test-ToolBoxLogger {
    <#
    .SYNOPSIS
        Teste le système de logging avec différents niveaux et destinations
    #>
    
    Write-ToolBoxLog -Level "Debug" -Message "Test de debug" -Component "Logger" -Console $true
    Write-ToolBoxLog -Level "Info" -Message "Test d'information" -Component "Logger" -Console $true -File $true
    Write-ToolBoxLog -Level "Warning" -Message "Test d'avertissement" -Component "Logger" -Console $true
    Write-ToolBoxLog -Level "Error" -Message "Test d'erreur" -Component "Logger" -Console $true -File $true
    Write-ToolBoxLog -Level "Private" -Message "Test de log privé" -Component "Logger" -File $true
    Write-ToolBoxLog -Level "Info" -Message "Test UI sans timestamp" -Component "Logger" -UI $true -ShowTimestamp $false
    
    Write-Host "`n--- Buffer UI (dernières 5 entrées) ---" -ForegroundColor Cyan
    $uiLogs = Get-ToolBoxLogBuffer -Last 5
    $uiLogs | ForEach-Object { Write-Host $_.FormattedMessage }
}

# Les fonctions sont disponibles après dot-sourcing du script