# PSToolBox.Core.psm1
# Module central contenant les fonctions utilitaires partagées par tous les outils.

#region Fonctions
#=============================================================================

function Load-WpfXaml {
    <#
    .SYNOPSIS
        Charge un fichier XAML et retourne un objet WPF.
    .DESCRIPTION
        Cette fonction est une version améliorée de Load-File. Elle charge un fichier XAML, 
        y fusionne un dictionnaire de styles optionnel, et retourne l'objet fenêtre prêt à l'emploi.
        Elle inclut une gestion d'erreurs détaillée.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,

        [System.Windows.ResourceDictionary]$Styles
    )
    
    # ... Logique améliorée de chargement XAML ...
    if (-not (Test-Path $Path)) { throw "Fichier XAML introuvable: $Path" }
    
    try {
        $reader = [System.Xml.XmlReader]::Create((New-Object System.IO.StringReader(Get-Content -Path $Path -Raw)))
        $window = [Windows.Markup.XamlReader]::Load($reader)

        if ($Styles -and $window.Resources) {
            $window.Resources.MergedDictionaries.Add($Styles)
        }
        
        return $window
    } catch {
        # Améliorer le message d'erreur pour inclure le numéro de ligne si possible
        $errorMessage = "Erreur lors du parsing de '$Path' : $($_.Exception.Message)"
        if ($_.Exception -is [System.Windows.Markup.XamlParseException]) {
            $errorMessage += "`nLigne: $($_.Exception.LineNumber), Position: $($_.Exception.LinePosition)"
        }
        throw $errorMessage
    }
}

function Show-EnhancedMessageBox {
    # ... Logique de votre Show-MessageBox, peut-être avec un paramètre -OwnerWindow pour un meilleur affichage modal ...
}

# ... Autres fonctions (Add-RichText, etc.) ...

#endregion Fonctions
#=============================================================================


#region Exports
#=============================================================================
# Exposer publiquement les fonctions que les autres scripts peuvent utiliser.
Export-ModuleMember -Function 'Load-WpfXaml', 'Show-EnhancedMessageBox'
#=============================================================================
#endregion Exports