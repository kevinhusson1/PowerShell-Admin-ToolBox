# Modules/Logging/Functions/Write-AppLog.ps1

<#
.SYNOPSIS
    Écrit un message de log formaté vers une ou plusieurs destinations.
.DESCRIPTION
    Cette fonction est le point d'entrée unique pour tout le logging de l'application.
    Elle formate un message avec un horodatage and un niveau de sévérité.
    Elle écrit toujours le message dans le flux Verbose pour le débogage en console.
    
    Elle peut également écrire dans une interface graphique (RichTextBox) de deux manières :
    1. En ciblant une RichTextBox spécifique fournie via le paramètre -RichTextBox (pour les scripts enfants).
    2. En demandant une écriture dans l'interface par défaut (le journal du lanceur) via le switch -LogToUI.
.PARAMETER Message
    Le message de log à écrire.
.PARAMETER Level
    Le niveau de sévérité du log ('Debug', 'Info', 'Success', 'Warning', 'Error').
.PARAMETER RichTextBox
    [Optionnel] Une référence à un objet [System.Windows.Controls.RichTextBox] dans lequel écrire le log.
.PARAMETER LogToUI
    [Optionnel] Un switch qui indique que le log doit être écrit dans l'interface par défaut (le journal du lanceur).
.EXAMPLE
    # Écrit un log simple dans la console (si -Verbose est activé)
    Write-AppLog -Message "Initialisation terminée."

.EXAMPLE
    # Écrit un log de succès dans une RichTextBox spécifique
    Write-AppLog -Message "Utilisateur créé !" -Level Success -RichTextBox $myScriptLogRtb

.EXAMPLE
    # Écrit un log d'erreur dans le journal principal du lanceur
    Write-AppLog -Message "La connexion a échoué." -Level Error -LogToUI
.OUTPUTS
    Aucune.
#>
function Write-AppLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('Debug', 'Info', 'Success', 'Warning', 'Error')]
        [string]$Level = 'Info',

        [System.Windows.Controls.RichTextBox]$RichTextBox,

        [switch]$LogToUI
    )

    $timestamp = Get-Date -Format "HH:mm:ss"
    $formattedMessage = "[$timestamp] [$Level] $Message"
    Write-Verbose $formattedMessage

    # Si on a une cible UI spécifique (fournie par un script enfant), on l'utilise.
    if ($null -ne $RichTextBox) {
        Update-AppRichTextBox -RichTextBox $RichTextBox -Message $Message -Level $Level -Timestamp $timestamp
    } 
    # Sinon, si on nous a demandé de logger dans l'UI par défaut (le lanceur).
    elseif ($LogToUI) {
        Update-AppRichTextBox -Message $Message -Level $Level -Timestamp $timestamp
    }
}