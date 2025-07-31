function Import-ToolBoxGlobalStyles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Window]$Window
    )
    
    try {
        Write-Verbose "Injection des styles personnalisés via la méthode XamlReader dans $($Window.Title)"
        
        $globalStylesPath = Join-Path $Global:ToolBoxStylesPath "GlobalStyles.xaml"
        if (-not (Test-Path $globalStylesPath)) {
            Write-Warning "Fichier GlobalStyles.xaml introuvable."
            return $false
        }
        
        # --- NOUVELLE MÉTHODE DE CHARGEMENT DIRECT ET ROBUSTE ---
        
        # 1. Lire le contenu du fichier XAML comme une chaîne de caractères
        $xamlContent = Get-Content -Path $globalStylesPath -Raw

        # 2. Créer un lecteur XML à partir de cette chaîne
        $stringReader = New-Object System.IO.StringReader -ArgumentList $xamlContent
        $xmlReader = [System.Xml.XmlReader]::Create($stringReader)

        # 3. Utiliser XamlReader pour transformer directement le XML en objet ResourceDictionary
        # C'est la méthode la plus fiable, elle ne dépend pas des URI.
        $customStyles = [System.Windows.Markup.XamlReader]::Load($xmlReader)
        
        # --- FIN DE LA NOUVELLE MÉTHODE ---

        if (-not $customStyles) {
            throw "Impossible de parser le ResourceDictionary depuis GlobalStyles.xaml"
        }

        # Ajouter le dictionnaire de ressources à la fenêtre
        $Window.Resources.MergedDictionaries.Add($customStyles)
        
        Write-Verbose "Styles personnalisés injectés avec succès via XamlReader."
        return $true
    }
    catch {
        # Cette fois, si une erreur se produit, elle sera obligatoirement interceptée ici.
        Write-Error "Erreur critique et définitive lors de l'injection des styles via XamlReader : $($_.Exception.Message)"
        return $false
    }
}