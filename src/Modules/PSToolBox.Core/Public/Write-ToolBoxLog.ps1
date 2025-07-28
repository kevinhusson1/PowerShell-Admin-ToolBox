<#
.SYNOPSIS
    Écrit un message de log formaté vers une ou plusieurs destinations.
.DESCRIPTION
    Cette fonction centralise la journalisation pour la ToolBox. Elle permet d'écrire
    des messages avec différents niveaux de sévérité (INFO, WARNING, ERROR) et de
    les diriger vers la console, un fichier de log, ou une collection d'objets pour
    l'affichage en temps réel dans une interface graphique.
.PARAMETER Message
    Le message de log à écrire.
.PARAMETER Level
    Le niveau de sévérité du message.
.PARAMETER FilePath
    Chemin optionnel vers un fichier de log. Si fourni, le message sera ajouté à ce fichier.
.PARAMETER Collection
    Collection d'objets optionnelle (comme un ObservableCollection). Si fournie, un objet log
    sera ajouté à cette collection.
.EXAMPLE
    Write-ToolBoxLog -Message "Initialisation de l'outil terminée."
.EXAMPLE
    Write-ToolBoxLog -Message "Impossible de contacter le serveur." -Level ERROR -FilePath "C:\logs\toolbox.log"
#>
function Write-ToolBoxLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('INFO', 'WARNING', 'ERROR', 'DEBUG')]
        [string]$Level = 'INFO',

        [Parameter(Mandatory = $false)]
        [string]$FilePath,

        [Parameter(Mandatory = $false)]
        [object]$Collection
    )

    # --- Étape 1 : Formater le message ---
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $formattedMessage = "[$timestamp] [$Level] - $Message"

    # --- Étape 2 : Écrire vers la Console (Host) ---
    # Utiliser les flux PowerShell standards pour une meilleure intégration
    switch ($Level) {
        'INFO'    { Write-Host $formattedMessage -ForegroundColor Green }
        'WARNING' { Write-Warning $formattedMessage }
        'ERROR'   { Write-Error $formattedMessage }
        'DEBUG'   { Write-Verbose $formattedMessage }
    }

    # --- Étape 3 : Écrire vers un Fichier ---
    if (-not ([string]::IsNullOrWhiteSpace($FilePath))) {
        try {
            # S'assurer que le répertoire du fichier de log existe
            $directory = [System.IO.Path]::GetDirectoryName($FilePath)
            if (-not (Test-Path $directory)) {
                New-Item -Path $directory -ItemType Directory -Force | Out-Null
            }
            Add-Content -Path $FilePath -Value $formattedMessage
        }
        catch {
            # Éviter une boucle infinie de logging d'erreur de log
            Write-Error "Échec de l'écriture dans le fichier de log '$FilePath': $($_.Exception.Message)"
        }
    }

    # --- Étape 4 : Ajouter à une Collection (pour l'UI) ---
    if ($null -ne $Collection) {
        # On crée un objet structuré, plus facile à manipuler dans l'UI (ex: pour colorer les lignes)
        $logObject = [PSCustomObject]@{
            Timestamp = $timestamp
            Level     = $Level
            Message   = $Message
        }
        # La collection doit avoir une méthode .Add() (ex: List, ObservableCollection)
        try {
            $Collection.Add($logObject)
        }
        catch {
            Write-Error "Échec de l'ajout à la collection de logs : $($_.Exception.Message)"
        }
    }
}