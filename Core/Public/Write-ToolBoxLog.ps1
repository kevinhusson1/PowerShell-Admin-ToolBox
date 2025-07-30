function Write-ToolBoxLog {
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
        [bool]$Console = $false,  # Changé : par défaut FALSE
        
        [Parameter(Mandatory = $false)]
        [bool]$File = $false,
        
        [Parameter(Mandatory = $false)]
        [bool]$UI = $false,
        
        [Parameter(Mandatory = $false)]
        [bool]$ShowTimestamp = $true
    )
    
    try {
        # Vérification du niveau de log global
        $shouldLog = $true
        $shouldDisplay = $false
        
        if ($Global:ToolBoxLogLevel) {
            $levelPriority = @{
                "Debug" = 0
                "Info" = 1  
                "Warning" = 2
                "Error" = 3
                "Private" = 1  # Même niveau que Info
            }
            
            $currentPriority = $levelPriority[$Level]
            $configuredPriority = $levelPriority[$Global:ToolBoxLogLevel]
            
            # Ne logger que si le niveau est >= au niveau configuré
            $shouldLog = ($currentPriority -ge $configuredPriority)
            
            # Pour la console, afficher seulement Warning et Error en production
            if ($Global:ToolBoxLogLevel -eq "Warning" -or $Global:ToolBoxLogLevel -eq "Error") {
                $shouldDisplay = ($Level -eq "Warning" -or $Level -eq "Error")
            } else {
                $shouldDisplay = $shouldLog
            }
        }
        
        if (-not $shouldLog) {
            return  # Ne pas logger du tout
        }
        
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
        
        # Affichage Console (contrôlé par le niveau)
        if ($Console -or $shouldDisplay) {
            # Write-LogToConsole intégré
            switch ($Level) {
                "Debug"   { Write-Host $logMessage -ForegroundColor Cyan }
                "Info"    { Write-Host $logMessage -ForegroundColor Green }
                "Warning" { Write-Host $logMessage -ForegroundColor Yellow }
                "Error"   { Write-Host $logMessage -ForegroundColor Red }
                "Private" { Write-Host $logMessage -ForegroundColor Magenta }
            }
        }
        
        # Écriture Fichier
        if ($File -or ($Level -eq "Error" -or $Level -eq "Warning")) {
            # Write-LogToFile intégré
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
                Add-Content -Path $filePath -Value $logMessage -Encoding UTF8
            }
            catch {
                Write-Warning "Erreur lors de l'écriture du fichier de log : $($_.Exception.Message)"
            }
        }
        
        # Stockage UI
        if ($UI) {
            # Add-LogToUIBuffer intégré
            $logEntry = [PSCustomObject]@{
                Timestamp = $timestamp
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
            
            # Initialiser le buffer si nécessaire
            if (-not $Script:ToolBoxLogBuffer) {
                $Script:ToolBoxLogBuffer = @()
            }
            
            # Ajout au buffer script (limité à 1000 entrées)
            $Script:ToolBoxLogBuffer += $logEntry
            if ($Script:ToolBoxLogBuffer.Count -gt 1000) {
                $Script:ToolBoxLogBuffer = $Script:ToolBoxLogBuffer[-900..-1]
            }
        }
    }
    catch {
        Write-Warning "Erreur lors de l'écriture du log : $($_.Exception.Message)"
    }
}