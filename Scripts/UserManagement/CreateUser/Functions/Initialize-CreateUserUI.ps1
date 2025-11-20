<#
.SYNOPSIS
    Récupère tous les contrôles UI de la fenêtre CreateUser et attache les événements.
.DESCRIPTION
    Cette fonction centralise l'initialisation de l'interface après son chargement.
    Elle retourne une hashtable des contrôles pour une utilisation par le script principal.
#>
function Initialize-CreateUserUI {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Window]$Window
    )

    # --- 1. Récupération des contrôles ---
    $controls = @{}
    $controlNames = @(
        "textBoxPrenom", "textBoxNom", "textBoxMatricule", "comboBoxDescription",
        "comboBoxEmploi", "textBoxEmploi", "btnEditEmploi",
        "comboBoxServices", "textBoxServices", "btnEditServices",
        "textBoxManager", "textBoxUserCopie", "radioHorairesFull", "radioHorairesHebdo",
        "checkLicence", "textBoxAlias", "textBoxEmail", "textBoxTelephoneNumber",
        "textBoxTelCourt", "textBoxMobile", "textBoxMobileCourt", "richTextBox",
        "btnReset", "btnVerif", "btnCreate"
    )
    foreach ($name in $controlNames) {
        $controls[$name] = $Window.FindName($name)
    }

    # --- 2. Logique et attachement des événements ---

    # Logique réutilisable pour basculer une ComboBox en TextBox
    $toggleToTextBox = {
        param($comboBox, $textBox, $button)
        
        $textBox.Text = $comboBox.Text
        $comboBox.Visibility = 'Collapsed'
        $textBox.Visibility = 'Visible'
        $button.IsEnabled = $false
        $textBox.Focus()
    } # Note: Pas besoin de GetNewClosure ici car ce bloc ne capture rien d'externe

    # --- CORRECTION : Ajout de .GetNewClosure() sur les événements ---
    
    $controls.btnEditEmploi.Add_Click({
        & $toggleToTextBox $controls.comboBoxEmploi $controls.textBoxEmploi $controls.btnEditEmploi
    }.GetNewClosure()) 

    $controls.btnEditServices.Add_Click({
        & $toggleToTextBox $controls.comboBoxServices $controls.textBoxServices $controls.btnEditServices
    }.GetNewClosure())

    # Logique pour le bouton de réinitialisation
    $controls.btnReset.Add_Click({
        # Réinitialiser les champs de texte simples
        "textBoxPrenom", "textBoxNom", "textBoxMatricule", "textBoxManager", 
        "textBoxUserCopie", "textBoxAlias", "textBoxEmail", "textBoxTelephoneNumber",
        "textBoxTelCourt", "textBoxMobile", "textBoxMobileCourt" | ForEach-Object {
            $controls[$_].Text = ""
        }
        # Réinitialiser les ComboBox
        "comboBoxDescription", "comboBoxEmploi", "comboBoxServices" | ForEach-Object {
            $controls[$_].SelectedIndex = -1
        }
        # Restaurer la visibilité
        $controls.comboBoxEmploi.Visibility = 'Visible'; $controls.textBoxEmploi.Visibility = 'Collapsed'; $controls.btnEditEmploi.IsEnabled = $true
        $controls.comboBoxServices.Visibility = 'Visible'; $controls.textBoxServices.Visibility = 'Collapsed'; $controls.btnEditServices.IsEnabled = $true
        # Réinitialiser les autres contrôles
        $controls.radioHorairesFull.IsChecked = $true
        $controls.checkLicence.IsChecked = $false
        $controls.richTextBox.Document.Blocks.Clear()
        
        $defaultLogParagraph = New-Object System.Windows.Documents.Paragraph
        $defaultLogParagraph.Foreground = $Window.FindResource("TextSecondaryBrush")
        $defaultLogParagraph.Inlines.Add((Get-AppText -Key 'create_user.log_default'))
        $controls.richTextBox.Document.Blocks.Add($defaultLogParagraph)
    }.GetNewClosure()) # Important ici aussi pour capturer $controls, $Window et Get-AppText

    # On retourne la hashtable des contrôles pour que le script principal puisse y accéder
    return $controls
}