# Classe LoggingService pour PowerShell Admin ToolBox
# Fournit un système de logging multi-destinations avec gestion asynchrone
# Supporte : Console, Fichier, RichTextBox WPF

using namespace System.Collections.Concurrent
using namespace System.Threading

class LoggingService {
    # Propriétés principales
    [string] $LogPath
    [string] $LogLevel = "Info"  # Debug, Info, Warning, Error
    [ConcurrentQueue[object]] $LogQueue
    [Timer] $FlushTimer
    [bool] $IsDisposed = $false
    
    # Configuration
    [hashtable] $LogLevels = @{
        "Debug" = 0
        "Info" = 1 
        "Warning" = 2
        "Error" = 3
    }
    
    [hashtable] $ConsoleColors = @{
        "Debug" = "Gray"
        "Info" = "White"
        "Warning" = "Yellow" 
        "Error" = "Red"
    }
    
    # Événements pour intégration UI
    [scriptblock] $OnLogEntryAdded = $null
    
    # Constructeurs
    LoggingService() {
        $this.Initialize(".\logs", "Info")
    }
    
    LoggingService([string] $logPath) {
        $this.Initialize($logPath, "Info")
    }
    
    LoggingService([string] $logPath, [string] $logLevel) {
        $this.Initialize($logPath, $logLevel)
    }
    
    # Initialisation commune
    [void] Initialize([string] $logPath, [string] $logLevel) {
        $this.LogPath = $logPath
        $this.LogLevel = $logLevel
        $this.LogQueue = [ConcurrentQueue[object]]::new()
        
        # Création du dossier de logs
        if (-not (Test-Path $this.LogPath)) {
            try {
                New-Item -Path $this.LogPath -ItemType Directory -Force | Out-Null
            }
            catch {
                Write-Warning "Impossible de créer le dossier de logs: $($_.Exception.Message)"
                $this.LogPath = $env:TEMP
            }
        }
        
        # Timer pour flush périodique (toutes les 5 secondes)
        $this.FlushTimer = [Timer]::new(
            { param($state) $state.FlushLogs() },
            $this,
            [TimeSpan]::FromSeconds(5),
            [TimeSpan]::FromSeconds(5)
        )
        
        # Log d'initialisation
        $this.WriteLog("LoggingService initialisé - Path: $($this.LogPath), Level: $($this.LogLevel)", "Info")
    }
    
    # Méthode principale d'écriture de log
    [void] WriteLog([string] $message, [string] $level = "Info") {
        $this.WriteLog($message, $level, @{})
    }
    
    [void] WriteLog([string] $message, [string] $level, [hashtable] $destinations) {
        # Validation du niveau
        if (-not $this.IsLevelEnabled($level)) {
            return
        }
        
        # Création de l'entrée de log
        $logEntry = [PSCustomObject]@{
            Timestamp = Get-Date
            Level = $level.ToUpper()
            Message = $message
            ProcessId = $PID
            ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
            Module = $this.GetCallerInfo()
        }
        
        # Ajout à la queue pour traitement asynchrone
        $this.LogQueue.Enqueue($logEntry)
        
        # Destinations immédiates si spécifiées
        if ($destinations.ContainsKey("Console") -and $destinations.Console) {
            $this.WriteToConsole($logEntry)
        }
        
        if ($destinations.ContainsKey("RichTextBox") -and $destinations.RichTextBox) {
            $this.WriteToRichTextBox($logEntry, $destinations.RichTextBox)
        }
        
        # Notification événement si handler défini
        if ($this.OnLogEntryAdded) {
            try {
                & $this.OnLogEntryAdded $logEntry
            }
            catch {
                # Éviter boucle infinie en cas d'erreur dans le handler
                Write-Warning "Erreur dans le handler OnLogEntryAdded: $($_.Exception.Message)"
            }
        }
    }
    
    # Vérification si le niveau est activé
    [bool] IsLevelEnabled([string] $level) {
        if (-not $this.LogLevels.ContainsKey($level)) {
            return $false
        }
        
        return $this.LogLevels[$level] -ge $this.LogLevels[$this.LogLevel]
    }
    
    # Obtention des informations sur l'appelant
    [string] GetCallerInfo() {
        try {
            $callStack = Get-PSCallStack
            if ($callStack.Count -gt 2) {
                $caller = $callStack[2]
                return "$($caller.Command):$($caller.ScriptLineNumber)"
            }
        }
        catch {
            # En cas d'erreur, retourner une valeur par défaut
        }
        return "Unknown"
    }
    
    # Écriture console avec colorisation
    [void] WriteToConsole([object] $logEntry) {
        $color = $this.ConsoleColors[$logEntry.Level]
        if (-not $color) { $color = "White" }
        
        $formattedMessage = "[$($logEntry.Timestamp.ToString('HH:mm:ss'))] [$($logEntry.Level)] $($logEntry.Message)"
        
        try {
            Write-Host $formattedMessage -ForegroundColor $color
        }
        catch {
            # Fallback si problème avec les couleurs
            Write-Output $formattedMessage
        }
    }
    
    # Écriture RichTextBox (pour interface WPF)
    [void] WriteToRichTextBox([object] $logEntry, [object] $richTextBox) {
        if (-not $richTextBox -or -not $richTextBox.Dispatcher) {
            return
        }
        
        $dispatcher = $richTextBox.Dispatcher
        
        $dispatcher.BeginInvoke([Action]{
            try {
                $document = $richTextBox.Document
                $paragraph = [System.Windows.Documents.Paragraph]::new()
                
                # Timestamp
                $timestampRun = [System.Windows.Documents.Run]::new("[$($logEntry.Timestamp.ToString('HH:mm:ss'))] ")
                $timestampRun.Foreground = [System.Windows.Media.Brushes]::Gray
                $paragraph.Inlines.Add($timestampRun)
                
                # Level avec couleur
                $levelRun = [System.Windows.Documents.Run]::new("[$($logEntry.Level)] ")
                $levelRun.FontWeight = [System.Windows.FontWeights]::Bold
                
                switch ($logEntry.Level) {
                    "DEBUG" { $levelRun.Foreground = [System.Windows.Media.Brushes]::Gray }
                    "INFO" { $levelRun.Foreground = [System.Windows.Media.Brushes]::Blue }
                    "WARNING" { $levelRun.Foreground = [System.Windows.Media.Brushes]::Orange }
                    "ERROR" { $levelRun.Foreground = [System.Windows.Media.Brushes]::Red }
                }
                $paragraph.Inlines.Add($levelRun)
                
                # Message
                $messageRun = [System.Windows.Documents.Run]::new($logEntry.Message)
                $paragraph.Inlines.Add($messageRun)
                
                $document.Blocks.Add($paragraph)
                
                # Auto-scroll et limitation du nombre de lignes
                $richTextBox.ScrollToEnd()
                while ($document.Blocks.Count -gt 1000) {
                    $document.Blocks.RemoveAt(0)
                }
            }
            catch {
                # En cas d'erreur UI, ne pas bloquer le logging
                Write-Warning "Erreur écriture RichTextBox: $($_.Exception.Message)"
            }
        })
    }
    
    # Flush périodique vers fichiers
    [void] FlushLogs() {
        if ($this.IsDisposed) {
            return
        }
        
        $logEntries = @()
        
        # Vidage de la queue
        while ($this.LogQueue.TryDequeue([ref]$logEntry)) {
            $logEntries += $logEntry
        }
        
        if ($logEntries.Count -gt 0) {
            $this.WriteToFile($logEntries)
        }
    }
    
    # Écriture fichier avec rotation
    [void] WriteToFile([array] $logEntries) {
        try {
            $logFile = Join-Path $this.LogPath "ToolBox_$(Get-Date -Format 'yyyy-MM-dd').log"
            
            $logLines = $logEntries | ForEach-Object {
                "[$($_.Timestamp.ToString('yyyy-MM-dd HH:mm:ss.fff'))] [$($_.Level)] [$($_.Module)] $($_.Message)"
            }
            
            # Écriture avec gestion des erreurs de concurrence
            $retryCount = 0
            $maxRetries = 3
            
            do {
                try {
                    Add-Content -Path $logFile -Value $logLines -Encoding UTF8 -ErrorAction Stop
                    break
                }
                catch {
                    $retryCount++
                    if ($retryCount -ge $maxRetries) {
                        Write-Warning "Impossible d'écrire dans le fichier de log après $maxRetries tentatives: $($_.Exception.Message)"
                        break
                    }
                    Start-Sleep -Milliseconds (100 * $retryCount)
                }
            } while ($retryCount -lt $maxRetries)
            
            # Rotation des logs (garder 30 jours)
            $this.RotateLogs()
        }
        catch {
            Write-Warning "Erreur générale écriture logs: $($_.Exception.Message)"
        }
    }
    
    # Rotation des fichiers de logs
    [void] RotateLogs() {
        try {
            $cutoffDate = (Get-Date).AddDays(-30)
            Get-ChildItem -Path $this.LogPath -Filter "ToolBox_*.log" |
                Where-Object { $_.CreationTime -lt $cutoffDate } |
                Remove-Item -Force -ErrorAction SilentlyContinue
        }
        catch {
            Write-Warning "Erreur rotation logs: $($_.Exception.Message)"
        }
    }
    
    # Méthodes de convenance pour les différents niveaux
    [void] Debug([string] $message) { $this.WriteLog($message, "Debug") }
    [void] Info([string] $message) { $this.WriteLog($message, "Info") }
    [void] Warning([string] $message) { $this.WriteLog($message, "Warning") }
    [void] Error([string] $message) { $this.WriteLog($message, "Error") }
    
    # Configuration du niveau de log
    [void] SetLogLevel([string] $level) {
        if ($this.LogLevels.ContainsKey($level)) {
            $this.LogLevel = $level
            $this.WriteLog("Niveau de log changé vers: $level", "Info")
        } else {
            $this.WriteLog("Niveau de log invalide: $level. Niveaux supportés: $($this.LogLevels.Keys -join ', ')", "Warning")
        }
    }
    
    # Configuration du handler d'événements
    [void] SetLogEntryHandler([scriptblock] $handler) {
        $this.OnLogEntryAdded = $handler
    }
    
    # Obtention des statistiques de logging
    [hashtable] GetStatistics() {
        return @{
            LogPath = $this.LogPath
            CurrentLogLevel = $this.LogLevel
            QueueSize = $this.LogQueue.Count
            IsDisposed = $this.IsDisposed
            SupportedLevels = $this.LogLevels.Keys
        }
    }
    
    # Nettoyage des ressources
    [void] Dispose() {
        if ($this.IsDisposed) {
            return
        }
        
        $this.IsDisposed = $true
        
        # Arrêt du timer
        if ($this.FlushTimer) {
            $this.FlushTimer.Dispose()
        }
        
        # Flush final
        $this.FlushLogs()
        
        $this.WriteLog("LoggingService terminé", "Info")
    }
}