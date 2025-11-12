# Modules/UI/Functions/Update-AppRichTextBox.ps1

# On définit les couleurs et icônes une seule fois au chargement du script pour la performance.
# Ces variables ne sont visibles que dans ce fichier (scope Script).
$script:AppLogColors = @{
    'Debug'   = '#808080' # Gris
    'Info'    = '#000000' # Noir
    'Success' = '#22c55e' # Vert
    'Warning' = '#f97316' # Orange
    'Error'   = '#ef4444' # Rouge
}
$script:AppLogIcons = @{
    'Info'    = 'ℹ️'
    'Success' = '✅'
    'Warning' = '⚠️'
    'Error'   = '❌'
    'Debug'   = '🐞'
}

<#
.SYNOPSIS
    Met à jour une RichTextBox avec un message de log formaté et coloré.
.DESCRIPTION
    Cette fonction est le moteur de rendu pour le logging dans l'interface.
    Elle prend un message et un niveau, et ajoute une ligne formatée (horodatage,
    icône, message coloré) à une RichTextBox cible.

    Elle a une logique de ciblage "intelligente" :
    1. Si une RichTextBox est fournie via -RichTextBox, elle l'utilise.
    2. Sinon, elle tente de trouver et d'utiliser la RichTextBox par défaut du lanceur.
.PARAMETER RichTextBox
    [Optionnel] Une référence à un objet [System.Windows.Controls.RichTextBox] cible.
.PARAMETER Message
    Le message de log à afficher.
.PARAMETER Level
    Le niveau de sévérité du log, qui détermine la couleur et l'icône.
.PARAMETER Timestamp
    L'horodatage du message.
.EXAMPLE
    Update-AppRichTextBox -Message "Opération réussie" -Level Success -Timestamp "14:30:15" -RichTextBox $myRtb
.OUTPUTS
    Aucune.
#>
function Update-AppRichTextBox {
    [CmdletBinding()]
    param(
        [System.Windows.Controls.RichTextBox]$RichTextBox,
        [Parameter(Mandatory)] [string]$Message,
        [Parameter(Mandatory)] [string]$Level,
        [Parameter(Mandatory)] [string]$Timestamp
    )

    $targetRtb = $RichTextBox

    if ($null -eq $targetRtb) {
        if ($Global:AppControls.ContainsKey('launcherLogRichTextBox')) {
            $targetRtb = $Global:AppControls.launcherLogRichTextBox
        }
        if ($null -eq $targetRtb) {
            $targetRtb = $Global:AppControls.mainWindow.FindName('LauncherLogRichTextBox')
            if ($null -ne $targetRtb) {
                $Global:AppControls['launcherLogRichTextBox'] = $targetRtb
            }
        }
    }

    if ($null -eq $targetRtb) {
        $warningMsg = Get-AppText -Key 'modules.ui.rtb_target_not_found'
        Write-Warning $warningMsg
        return
    }

    # On utilise les variables de scope Script définies en haut du fichier
    $colorHex = $script:AppLogColors[$Level]
    $icon = $script:AppLogIcons[$Level]

    $targetRtb.Dispatcher.Invoke([Action]{
        if ($null -eq $targetRtb.Tag) {
            $targetRtb.Document.Blocks.Clear()
            $targetRtb.Tag = "Initialized"
        }

        $paragraph = New-Object System.Windows.Documents.Paragraph
        $paragraph.Margin = [System.Windows.Thickness]::new(0)

        $runTimestamp = New-Object System.Windows.Documents.Run("[$Timestamp] ")
        $runTimestamp.Foreground = [System.Windows.Media.Brushes]::Gray
        $paragraph.Inlines.Add($runTimestamp)
        
        $runIcon = New-Object System.Windows.Documents.Run("$icon ")
        $runIcon.FontFamily = 'Segoe UI Symbol'
        $paragraph.Inlines.Add($runIcon)
        
        $messageColor = [System.Windows.Media.ColorConverter]::ConvertFromString($colorHex)
        $messageBrush = New-Object System.Windows.Media.SolidColorBrush -ArgumentList $messageColor
        
        $runMessage = New-Object System.Windows.Documents.Run($Message)
        $runMessage.Foreground = $messageBrush
        $paragraph.Inlines.Add($runMessage)
        
        $targetRtb.Document.Blocks.Add($paragraph)
        $targetRtb.ScrollToEnd()
    })
}