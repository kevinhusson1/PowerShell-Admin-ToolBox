<#
.SYNOPSIS
    Éditeur XML graphique pour la création et la modification de fichiers XML structurés.
.DESCRIPTION
    Ce script lance une application WPF permettant de manipuler des structures XML de manière intuitive.
    L'application est pilotée par une configuration externe (settings.ps1) qui définit les types d'éléments,
    leur apparence, leurs propriétés et leurs règles de hiérarchie.
.VERSION
    1.0 - Version stable et fonctionnelle.
.AUTHOR
    HUSSON Kévin 
#>

# ===================================================================
# INITIALISATION
# ===================================================================

# Clear-Host
# $VerbosePreference = "Continue" # Mettre à "SilentlyContinue" en production
    $global:PSDefaultParameterValues['*:Encoding'] = 'utf8'

# --- Définition des variables globales pour l'application ---
    $global:xmlIndentation = 2

# S'il est lancé seul, on le calcule à partir de l'emplacement du script actuel.
    if (-not $global:globalPath) {
        # $PSScriptRoot est le répertoire du script en cours d'exécution.
        # On remonte de deux niveaux pour trouver la racine de la ToolBox (scripts -> ToolBox)
        $global:globalPath = (Resolve-Path (Join-Path $PSScriptRoot "..\")).Path
        Write-Verbose "Bootstrap: \$global:globalPath initialisé à '$($global:globalPath)'"
    }

# Redéfinition des chemins globaux essentiels
    $global:functionsPath   = Join-Path $global:globalPath "functions"
    $global:resourcesPath   = Join-Path $global:globalPath "resources"
    $global:stylePath       = Join-Path $global:globalPath "styles"
    $global:icoPath         = Join-Path $global:globalPath "resources\ico"

# Chargement des fonctions et configurations vitales
    try {
        . (Join-Path $global:functionsPath "Get-Function.ps1")
        Get-Function -FunctionName Load-File -FunctionsPath $global:functionsPath
        Get-Function -FunctionName Load-Assembly -FunctionsPath $global:functionsPath

        # Chargement des assemblies .NET nécessaires pour les UI WPF
        Load-Assembly -AssemblyNames @("PresentationCore", "PresentationFramework", "System.Windows.Forms")
        [System.Windows.Forms.Application]::EnableVisualStyles()

        # Chargement des styles XAML globaux dans une variable globale
        $global:stylesXamlPath = Join-Path $global:stylePath "styles.xaml"
        if (-not $global:stylesXAML) { # On ne le charge que s'il n'existe pas déjà
            $global:stylesXAML = Load-File -Path $global:stylesXamlPath
        }

        # Chargement des paramètres globaux de l'application
        $settingsPath = Join-Path $global:resourcesPath "settings.ps1"
        Load-File -Path $settingsPath

    } catch {
        [System.Windows.MessageBox]::Show("Erreur critique durant l'initialisation du script : $($_.Exception.Message)", "Erreur Bootstrap", "OK", "Stop")
        Exit
    }


Get-Function -FunctionName Load-File -FunctionsPath $global:functionsPath
Get-Function -FunctionName Load-Assembly -FunctionsPath $global:functionsPath
Get-Function -FunctionName Show-InputBox -FunctionsPath $global:functionsPath
Get-Function -FunctionName Show-MessageBox -FunctionsPath $global:functionsPath
Get-Function -FunctionName Show-NewTemplateDialog -FunctionsPath $global:functionsPath

$settingsPath = Join-Path -Path $global:resourcesPath -ChildPath "templatesXML.ps1"
if (Test-Path $settingsPath) { Load-File -Path $settingsPath } else { Write-Warning "Fichier de configuration 'templatesXML.ps1' introuvable." }

# --- Chargement des assemblies .NET ---
Load-Assembly -AssemblyNames @("PresentationCore", "PresentationFramework", "System.Windows.Forms")
[System.Windows.Forms.Application]::EnableVisualStyles()

# ===================================================================
# FONCTIONS MÉTIER DE LA FENÊTRE PRINCIPALE
# ===================================================================

function global:Update-WindowTitle {
    $title = "Éditeur XML"
    if ($script:currentFilePath) { $title += " - $(Split-Path $script:currentFilePath -Leaf)" }
    if ($script:hasUnsavedChanges) { $title += "*" }
    $script:ui.Window.Title = $title
}

function Confirm-UnsavedChanges {
    if (-not $script:hasUnsavedChanges) { return $true }

    $message = "Vous avez des modifications non enregistrées. Voulez-vous les sauvegarder avant de continuer ?"
    $result = Show-MessageBox -Title "Sauvegarder les modifications ?" -Message $message -ButtonType "YesNoCancel" -IconType "Warning"

    switch ($result) {
        'Yes'    { Do-SaveFile; return (-not $script:hasUnsavedChanges) }
        'No'     { return $true }
        'Cancel' { return $false }
        default  { return $false }
    }
}

function Get-InsertionIndex {
    param([System.Windows.Controls.ItemsControl]$parentItemsControl, [string]$newElementName)
    $order = @{'permissions'=1; 'tags'=2; 'link'=3; 'file'=4; 'directory'=5}
    $newOrder = $order[$newElementName] ?? 99
    $i = 0
    foreach ($item in $parentItemsControl.Items) {
        $existingOrder = $order[$item.Tag.LocalName.ToLower()] ?? 99
        if ($existingOrder -gt $newOrder) { return $i }
        $i++
    }
    return $parentItemsControl.Items.Count
}

## fonctions pour créer, lire, mettre à jour et supprimer des éléments dans le document XML
function global:New-XmlDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$RootElementName
    )

    Write-Verbose "Création d'un nouveau document XML avec la racine <$RootElementName>."

    try {
        # Valider le nom de l'élément racine avant de créer le document
        $validationResult = Test-XmlName -Name $RootElementName
        if ($validationResult -isnot [bool] -or -not $validationResult) {
            # Si Test-XmlName retourne une chaîne (message d'erreur)
            throw "Le nom de l'élément racine '$RootElementName' est invalide. $validationResult"
        }

        $xmlDoc = New-Object System.Xml.XmlDocument
        
        # Ajout de la déclaration XML standard (<?xml ... ?>)
        $xmlDeclaration = $xmlDoc.CreateXmlDeclaration("1.0", "UTF-8", $null)
        $xmlDoc.AppendChild($xmlDeclaration) | Out-Null
        
        # Création et ajout de l'élément racine
        $rootElement = $xmlDoc.CreateElement($RootElementName)
        $xmlDoc.AppendChild($rootElement) | Out-Null
        
        return $xmlDoc
    }
    catch {
        Write-Error "Erreur dans New-XmlDocument : $($_.Exception.Message)"
        # Retourner $null pour que l'appelant sache qu'il y a eu une erreur
        return $null
    }
}

function global:Add-XmlElement {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [System.Xml.XmlDocument]$XmlDocument,
        [Parameter(Mandatory=$true)]
        [System.Xml.XmlElement]$ParentElement,
        [Parameter(Mandatory=$true)]
        [string]$NewElementName
    )
    
    Write-Verbose "Ajout de l'élément <$NewElementName> sous <$($ParentElement.Name)>"
    try {
        $validationResult = Test-XmlName -Name $NewElementName
        if ($validationResult -isnot [bool] -or -not $validationResult) {
            throw "Le nom de l'élément '$NewElementName' est invalide. $validationResult"
        }

        $newElement = $XmlDocument.CreateElement($NewElementName)
        $ParentElement.AppendChild($newElement) | Out-Null
        
        return $newElement # Retourne le nœud créé pour que l'UI puisse l'ajouter
    }
    catch {
        Write-Error "Erreur dans Add-XmlElement : $($_.Exception.Message)"
        return $null
    }
}

function global:Add-XmlAttribute {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [System.Xml.XmlDocument]$XmlDocument,
        [Parameter(Mandatory=$true)]
        [System.Xml.XmlElement]$TargetElement,
        [Parameter(Mandatory=$true)]
        [string]$AttributeName,
        [Parameter(Mandatory=$false)]
        [string]$AttributeValue = ""
    )
    
    Write-Verbose "Ajout de l'attribut '$AttributeName' à <$($TargetElement.Name)>"
    try {
        $validationResult = Test-XmlName -Name $AttributeName
        if ($validationResult -isnot [bool] -or -not $validationResult) {
            throw "Le nom de l'attribut '$AttributeName' est invalide. $validationResult"
        }

        if ($TargetElement.HasAttribute($AttributeName)) {
            throw "L'attribut '$AttributeName' existe déjà sur cet élément."
        }

        $newAttribute = $XmlDocument.CreateAttribute($AttributeName)
        $newAttribute.Value = $AttributeValue
        $TargetElement.Attributes.Append($newAttribute) | Out-Null
        
        return $newAttribute # Retourne l'attribut créé
    }
    catch {
        Write-Error "Erreur dans Add-XmlAttribute : $($_.Exception.Message)"
        return $null
    }
}

function global:Add-XmlText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [System.Xml.XmlDocument]$XmlDocument,
        [Parameter(Mandatory=$true)]
        [System.Xml.XmlElement]$TargetElement,
        [Parameter(Mandatory=$true)]
        [string]$TextContent
    )

    Write-Verbose "Ajout de contenu textuel à <$($TargetElement.Name)>"
    try {
        ### CORRECTION ICI ###
        # Un élément ne peut contenir à la fois du texte et des sous-éléments.
        # C'est une simplification, mais elle rend la gestion de l'UI beaucoup plus simple.
        # On vérifie si l'élément cible a déjà des enfants de type 'Element'.
        $hasElementChildren = $false
        foreach ($child in $TargetElement.ChildNodes) {
            if ($child.NodeType -eq 'Element') {
                $hasElementChildren = $true
                break # Pas la peine de continuer si on en a trouvé un
            }
        }
        
        if ($hasElementChildren) {
            throw "Impossible d'ajouter du texte à un élément qui contient déjà d'autres éléments enfants."
        }

        $newTextNode = $XmlDocument.CreateTextNode($TextContent)
        $TargetElement.AppendChild($newTextNode) | Out-Null
        
        return $newTextNode # Retourne le nœud texte créé
    }
    catch {
        Write-Error "Erreur dans Add-XmlText : $($_.Exception.Message)"
        return $null
    }
}

function global:Remove-XmlElement {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [System.Xml.XmlNode]$NodeToDelete
    )

    if (-not $NodeToDelete.ParentNode) {
        Write-Error "Impossible de supprimer le nœud racine."
        return $false
    }

    try {
        Write-Verbose "Suppression du nœud <$($NodeToDelete.LocalName)> du parent <$($NodeToDelete.ParentNode.LocalName)>."
        # La méthode RemoveChild retourne le nœud qui a été supprimé.
        $NodeToDelete.ParentNode.RemoveChild($NodeToDelete) | Out-Null
        return $true
    }
    catch {
        Write-Error "Erreur lors de la suppression du nœud : $($_.Exception.Message)"
        return $false
    }
}

function global:Save-XmlDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [System.Xml.XmlDocument]$XmlDocument,
        [Parameter(Mandatory=$true)]
        [string]$FilePath,
        [Parameter(Mandatory=$false)]
        [int]$Indentation = 2
    )

    try {
        Write-Verbose "Sauvegarde et formatage du document XML vers : $FilePath"
        
        # Étape 1 : Obtenir le XML sous forme de chaîne brute.
        $rawXmlString = $XmlDocument.OuterXml
        
        # Étape 2 : Utiliser la classe XDocument (LINQ to XML) pour le re-formater.
        # XDocument.Parse() lit la chaîne.
        # .ToString() la réécrit, et par défaut, elle est parfaitement indentée.
        $formattedXmlString = [System.Xml.Linq.XDocument]::Parse($rawXmlString).ToString()

        # Étape 3 : Écrire la chaîne formatée dans le fichier avec l'encodage UTF-8.
        # [System.IO.File]::WriteAllText est plus robuste que Set-Content.
        [System.IO.File]::WriteAllText($FilePath, $formattedXmlString, [System.Text.Encoding]::UTF8)
        
        Write-Verbose "Sauvegarde formatée terminée avec succès."
        return $true
    }
    catch {
        Write-Error "Erreur lors de la sauvegarde du fichier XML : $($_.Exception.Message)"
        return $false
    }
}

function global:Move-XmlNodeUp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [System.Xml.XmlNode]$NodeToMove
    )
    $parentNode = $NodeToMove.ParentNode
    if (-not $parentNode) { return $false }

    # On cherche le premier frère précédent qui est du même type de balise.
    $previousSibling = $NodeToMove.PreviousSibling
    while ($previousSibling -and ($previousSibling.NodeType -ne 'Element' -or $previousSibling.LocalName -ne $NodeToMove.LocalName)) {
        $previousSibling = $previousSibling.PreviousSibling
    }
    
    if (-not $previousSibling) { return $false } # Pas de frère du même type avant

    try {
        $parentNode.InsertBefore($NodeToMove, $previousSibling) | Out-Null
        return $true
    } catch {
        Write-Error "Erreur dans Move-XmlNodeUp: $($_.Exception.Message)"
        return $false
    }
}

function global:Move-XmlNodeDown {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [System.Xml.XmlNode]$NodeToMove
    )
    $parentNode = $NodeToMove.ParentNode
    if (-not $parentNode) { return $false }

    # On cherche le premier frère suivant qui est du même type de balise.
    $nextSibling = $NodeToMove.NextSibling
    while ($nextSibling -and ($nextSibling.NodeType -ne 'Element' -or $nextSibling.LocalName -ne $NodeToMove.LocalName)) {
        $nextSibling = $nextSibling.NextSibling
    }

    if (-not $nextSibling) { return $false } # Pas de frère du même type après

    try {
        $parentNode.InsertAfter($NodeToMove, $nextSibling) | Out-Null
        return $true
    } catch {
        Write-Error "Erreur dans Move-XmlNodeDown: $($_.Exception.Message)"
        return $false
    }
}

function global:Duplicate-XmlElement {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [System.Xml.XmlNode]$NodeToDuplicate
    )

    $parentNode = $NodeToDuplicate.ParentNode
    if (-not $parentNode) {
        Write-Error "Impossible de dupliquer le nœud racine."
        return $null
    }

    try {
        # CloneNode(true) fait une copie profonde (deep clone), avec tous les enfants.
        $clonedNode = $NodeToDuplicate.CloneNode($true)
        
        # Modifier légèrement le nom du nouvel élément pour éviter les doublons stricts si nécessaire
        if ($clonedNode.Attributes['name']) {
            $clonedNode.Attributes['name'].Value = "$($clonedNode.Attributes['name'].Value) - Copie"
        }

        # Insérer le clone juste après l'original
        $parentNode.InsertAfter($clonedNode, $NodeToDuplicate) | Out-Null
        
        # Retourner le nouveau nœud pour que l'UI puisse l'utiliser
        return $clonedNode
    }
    catch {
        Write-Error "Erreur lors de la duplication du nœud : $($_.Exception.Message)"
        return $null
    }
}

## Fonction de validation des noms XML
function global:Test-XmlName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name
    )

    # Regex pour un nom d'élément XML simple et sûr (commence par une lettre, puis lettres, chiffres, tirets, underscores).
    # Cela interdit les espaces, les accents et autres caractères spéciaux pour plus de sécurité.
    $validXmlNameRegex = '^[a-zA-Z_][a-zA-Z0-9_.-]*$'

    if ($Name -match $validXmlNameRegex) {
        return $true
    } else {
        if ($Name -match '\s') {
            return "Le nom ne peut pas contenir d'espaces."
        }
        if ($Name -match '^[^a-zA-Z_]') {
            return "Le nom doit commencer par une lettre ou un underscore (_)."
        }
        return "Le nom contient des caractères non autorisés (accents, symboles...)."
    }
}

## Fonctionpour manipuler le TreeView de l'UI
function global:New-TreeViewItemFromXmlNode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [System.Xml.XmlNode]$XmlNode
    )
    $treeViewItem = New-Object System.Windows.Controls.TreeViewItem
    $treeViewItem.Tag = $XmlNode
    $nodeName = $XmlNode.LocalName.ToLower()
    $mapping = $global:ElementMappings[$nodeName] ?? $global:ElementMappings['__default__']
    $itemHeaderPanel = New-Object System.Windows.Controls.StackPanel -Property @{ Orientation = "Horizontal" }
    $iconTextBlock = New-Object System.Windows.Controls.TextBlock -Property @{
        Margin = [System.Windows.Thickness]::new(0, 0, 5, 0); VerticalAlignment = "Center"; Text = $mapping.Icon
        Foreground = [System.Windows.Media.SolidColorBrush]::new(([System.Windows.Media.ColorConverter]::ConvertFromString($mapping.Color)))
    }
    $labelTextBlock = New-Object System.Windows.Controls.TextBlock -Property @{
        VerticalAlignment = "Center"; Text = & $mapping.Label $XmlNode
    }
    $itemHeaderPanel.Children.Add($iconTextBlock) | Out-Null
    $itemHeaderPanel.Children.Add($labelTextBlock) | Out-Null
    $treeViewItem.Header = $itemHeaderPanel
    return $treeViewItem
}

function global:Update-TreeViewFromXml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Controls.TreeView]$TreeView,
        [Parameter(Mandatory = $true)]
        [System.Xml.XmlDocument]$XmlDocument
    )
    function Add-XmlNodeToTreeViewRecursive {
        param([System.Xml.XmlNode]$XmlNode, [System.Windows.Controls.ItemsControl]$ParentItemsControl)
        if ($XmlNode.NodeType -ne 'Element') { return }
        $treeViewItem = New-TreeViewItemFromXmlNode -XmlNode $XmlNode
        $ParentItemsControl.Items.Add($treeViewItem) | Out-Null
        $childrenToSort = @()
        foreach ($childNode in $XmlNode.ChildNodes) {
            if ($childNode.NodeType -eq 'Element') { $childrenToSort += $childNode }
        }
        $sortedChildren = $childrenToSort | Sort-Object {
            $mapping = $global:ElementMappings[$_.LocalName.ToLower()] ?? $global:ElementMappings['__default__']
            return $mapping.SortOrder
        }
        foreach ($sortedChild in $sortedChildren) {
            Add-XmlNodeToTreeViewRecursive -XmlNode $sortedChild -ParentItemsControl $treeViewItem
        }
    }
    $TreeView.Items.Clear()
    if ($XmlDocument.DocumentElement) {
        Add-XmlNodeToTreeViewRecursive -XmlNode $XmlDocument.DocumentElement -ParentItemsControl $TreeView
        if ($TreeView.Items.Count -gt 0) { ($TreeView.Items[0] -as [System.Windows.Controls.TreeViewItem]).IsExpanded = $true }
    }
}

function global:Update-PropertiesPanel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [hashtable]$UI,
        [Parameter(Mandatory=$true)] [System.Xml.XmlNode]$XmlNode
    )

    $HostPanel = $UI.PropertiesHostPanel
    $HostPanel.Children.Clear()

    $Window = $UI.Window
    $mapping = $global:ElementMappings[$XmlNode.LocalName.ToLower()] ?? $global:ElementMappings['__default__']

    if (-not $mapping.Properties -or $mapping.Properties.Count -eq 0) {
        $label = New-Object System.Windows.Controls.TextBlock -Property @{ 
            Text = "Cet élément <$($XmlNode.LocalName)> n'a pas de propriétés modifiables."
            FontStyle = "Italic"
            TextWrapping = "Wrap"
            Foreground = [System.Windows.Media.Brushes]::Gray 
        }
        $HostPanel.Children.Add($label) | Out-Null
        return
    }

    # Utiliser une boucle 'foreach' est plus simple, mais la clé est comment on gère la variable à l'intérieur.
    foreach ($propDef_iterator in $mapping.Properties) {
        
        # On crée une copie locale de la variable. C'est cette copie qui sera "capturée" par la closure.
        $currentPropDef = $propDef_iterator

        $label = New-Object System.Windows.Controls.TextBlock -Property @{ 
            Text = $currentPropDef.Label
            Style = $Window.FindResource("H4Style") 
        }
        $HostPanel.Children.Add($label) | Out-Null

        switch ($currentPropDef.ControlType) {
            'TextBox' {
                $textBox = New-Object System.Windows.Controls.TextBox -Property @{
                    Style = $Window.FindResource("StandardTextBoxStyle")
                    Text = $XmlNode.Attributes[$currentPropDef.AttributeName]?.Value
                    Margin = [System.Windows.Thickness]::new(0,5,0,10)
                }
                
                # On crée le scriptblock qui utilisera la variable locale 'currentPropDef'
                $textChangedScriptBlock = {
                    param($sender, $e)
                    if(-not $sender.IsFocused){ return }
                    $selectedItem = $UI.XmlTreeView.SelectedItem; if(-not $selectedItem){ return }
                    
                    $node = $selectedItem.Tag
                    # Utilise $currentPropDef qui a été capturé avec la bonne valeur
                    $node.SetAttribute($currentPropDef.AttributeName, $sender.Text)
                    
                    $tempItem = New-TreeViewItemFromXmlNode -XmlNode $node
                    $newLabelText = ($tempItem.Header.Children[1] -as [System.Windows.Controls.TextBlock]).Text
                    $headerPanel = $selectedItem.Header -as [System.Windows.Controls.StackPanel]
                    ($headerPanel.Children[1] -as [System.Windows.Controls.TextBlock]).Text = $newLabelText
                    
                    $script:hasUnsavedChanges = $true
                    Update-WindowTitle
                }.GetNewClosure() # .GetNewClosure() fige la portée
                
                $textBox.Add_TextChanged($textChangedScriptBlock)
                $HostPanel.Children.Add($textBox) | Out-Null
            }

            'ComboBox' {
                $comboBox = New-Object System.Windows.Controls.ComboBox -Property @{
                    Style = $Window.FindResource("StandardComboBoxStyle")
                    ItemContainerStyle = $Window.FindResource("StandardComboBoxItemStyle")
                    Height = 32
                    Margin = [System.Windows.Thickness]::new(0,5,0,10)
                }
                
                $currentPropDef.Options | ForEach-Object { $comboBox.Items.Add($_) }
                $comboBox.SelectedItem = $XmlNode.Attributes[$currentPropDef.AttributeName]?.Value

                # On crée le scriptblock qui utilisera la variable locale 'currentPropDef'
                $selectionChangedScriptBlock = {
                    param($sender, $e)
                    if($sender.SelectedItem -eq $null -or -not $sender.IsDropDownOpen){ return }
                    
                    $selectedItem = $UI.XmlTreeView.SelectedItem; if(-not $selectedItem){ return }
                    
                    $node = $selectedItem.Tag
                    if($node.Attributes[$currentPropDef.AttributeName].Value -eq $sender.SelectedItem){ return }
                    
                    # Utilise $currentPropDef qui a été capturé
                    $node.SetAttribute($currentPropDef.AttributeName, $sender.SelectedItem)

                    $tempItem = New-TreeViewItemFromXmlNode -XmlNode $node
                    $newLabelText = ($tempItem.Header.Children[1] -as [System.Windows.Controls.TextBlock]).Text
                    $headerPanel = $selectedItem.Header -as [System.Windows.Controls.StackPanel]
                    ($headerPanel.Children[1] -as [System.Windows.Controls.TextBlock]).Text = $newLabelText
                    
                    $script:hasUnsavedChanges = $true
                    Update-WindowTitle
                }.GetNewClosure() # .GetNewClosure() fige la portée

                $comboBox.Add_SelectionChanged($selectionChangedScriptBlock)
                $HostPanel.Children.Add($comboBox) | Out-Null
            }
        }
    }
}

function global:Update-UIOnSelection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [hashtable]$UI
    )

    # 1. Réinitialisation de l'UI
    $UI.PropertiesHostPanel.Children.Clear()
    $UI.PropertiesInstructionText.Visibility = "Visible"

    # 2. Gestion de la sélection
    $selectedTreeViewItem = $UI.XmlTreeView.SelectedItem
    if (-not $selectedTreeViewItem) {
        $UI.StatusText.Text = "Aucun élément sélectionné."
        @( $UI.ButtonAddElement, $UI.ButtonDuplicate, $UI.ButtonMoveUp, $UI.ButtonMoveDown, $UI.ButtonDelete ) | ForEach-Object { $_.IsEnabled = $false }
        return
    }

    # 3. Préparation à l'affichage des propriétés
    $UI.PropertiesInstructionText.Visibility = "Collapsed"
    
    ### CORRECTION ICI ###
    # On utilise la bonne variable $selectedTreeViewItem pour obtenir le nœud.
    $selectedNode = $selectedTreeViewItem.Tag
    
    # Appel à la fonction qui construit le panneau
    Update-PropertiesPanel -UI $UI -XmlNode $selectedNode

    $UI.StatusText.Text = "Élément <$($selectedNode.LocalName)> sélectionné."
    
    # 4. Logique d'activation des boutons
    $isRoot = ($selectedNode.LocalName -eq "root")
    $UI.ButtonDelete.IsEnabled = (-not $isRoot)
    $UI.ButtonDuplicate.IsEnabled = (-not $isRoot)
    $UI.ButtonAddElement.IsEnabled = $global:XmlSchema.ContainsKey($selectedNode.LocalName.ToLower())
    $UI.ButtonMoveUp.IsEnabled = $false
    $UI.ButtonMoveDown.IsEnabled = $false
    if (-not $isRoot) {
        $previousSibling = $selectedNode.PreviousSibling
        while ($previousSibling -and ($previousSibling.NodeType -ne 'Element' -or $previousSibling.LocalName -ne $selectedNode.LocalName)) {
            $previousSibling = $previousSibling.PreviousSibling
        }
        if ($previousSibling) { $UI.ButtonMoveUp.IsEnabled = $true }

        $nextSibling = $selectedNode.NextSibling
        while ($nextSibling -and ($nextSibling.NodeType -ne 'Element' -or $nextSibling.LocalName -ne $selectedNode.LocalName)) {
            $nextSibling = $nextSibling.NextSibling
        }
        if ($nextSibling) { $UI.ButtonMoveDown.IsEnabled = $true }
    }
}

function Do-NewFile {
    if (-not (Confirm-UnsavedChanges)) { return }

    # 1. Appeler la fenêtre de dialogue qui retourne maintenant juste le nom du template.
    $chosenTemplateName = Show-NewTemplateDialog -OwnerWindow $script:ui.Window -Templates $global:ApplicationTemplates -UI $script:ui
    # write-host ($chosenTemplateName[2])
    $chosenTemplateName = $chosenTemplateName[-1] # On récupère juste le nom du template
    # 2. Si l'utilisateur a annulé, la fonction retourne $null ou une chaîne vide.
    if ([string]::IsNullOrWhiteSpace($chosenTemplateName)) {
        $script:ui.StatusText.Text = "Création de document annulée."
        return 
    }

    # 3. Réinitialisation complète de l'état
    $script:xmlDoc = $null
    $script:currentFilePath = ""
    $script:ui.XmlTreeView.ItemsSource = $null
    $script:ui.PropertiesHostPanel.Children.Clear()
    $script:ui.PropertiesInstructionText.Visibility = "Visible"
    $script:ui.StatusText.Text = "Création d'un nouveau document..."

    # 4. Récupérer la configuration du template choisi
    $templateConfig = $global:ApplicationTemplates[$chosenTemplateName]
    $chosenRootName = $templateConfig.DefaultRootName # Récupérer le nom de la racine ici

    # Mettre à jour les variables de configuration actives
    $script:activeTemplateName = $chosenTemplateName
    $global:ElementMappings = $templateConfig.ElementMappings
    $global:XmlSchema = $templateConfig.XmlSchema

    # 5. Créer le document XML
    $script:xmlDoc = New-XmlDocument -RootElementName $chosenRootName
    if ($script:xmlDoc) {
        # On inscrit le nom du template dans un attribut de la racine
        $script:xmlDoc.DocumentElement.SetAttribute("template", $chosenTemplateName)

        # Mettre à jour l'état et l'UI
        $script:hasUnsavedChanges = $true
        Update-TreeViewFromXml -TreeView $script:ui.XmlTreeView -XmlDocument $script:xmlDoc
        Update-WindowTitle
        
        $script:ui.LabelCurrentFile.Text = "Nouveau document ($chosenTemplateName)"
        $script:ui.StatusText.Text = "Prêt."
        
        $script:ui.ButtonSave.IsEnabled = $true
        $script:ui.ButtonSaveAs.IsEnabled = $true
        $script:ui.ButtonValidateXml.IsEnabled = $true
    } else {
        Show-MessageBox -Title "Erreur" -Message "Impossible de créer le document." -IconType "Error" | Out-Null
    }
}

function Do-OpenFile {
    if (-not (Confirm-UnsavedChanges)) { return }

    # L'utilisateur choisit un fichier.
    $openFileDialog = New-Object Microsoft.Win32.OpenFileDialog
    $openFileDialog.Filter = "Fichiers XML (*.xml)|*.xml|Tous les fichiers (*.*)|*.*"
    if ($openFileDialog.ShowDialog() -ne $true) { return }
    
    $filePath = $openFileDialog.FileName
    
    try {
        ### RÉINITIALISATION COMPLÈTE DE L'ÉTAT ###
        $script:xmlDoc = $null
        $script:currentFilePath = ""
        $script:ui.XmlTreeView.ItemsSource = $null # Force le vidage
        $script:ui.PropertiesHostPanel.Children.Clear()
        $script:ui.PropertiesInstructionText.Visibility = "Visible"
        $script:ui.StatusText.Text = "Ouverture du fichier..."

        # Charger le fichier en mémoire.
        $xmlDoc = New-Object System.Xml.XmlDocument
        $xmlDoc.PreserveWhitespace = $true
        $xmlDoc.Load($filePath)

        # Détecter le template depuis l'attribut.
        $templateNameFromFile = $xmlDoc.DocumentElement.GetAttribute("template")

        # Si l'attribut n'existe pas, on demande à l'utilisateur.
        if ([string]::IsNullOrWhiteSpace($templateNameFromFile)) {
            $dialogResult = Show-NewTemplateDialog -OwnerWindow $script:ui.Window -Templates $global:ApplicationTemplates -UI $script:ui
            if (-not $dialogResult) { $script:ui.StatusText.Text = "Ouverture annulée."; return }
            $templateNameFromFile = $dialogResult.TemplateName
        }

        # Vérifier si le template est connu.
        if (-not $global:ApplicationTemplates.ContainsKey($templateNameFromFile)) {
            Show-MessageBox -Title "Template Inconnu" -Message "Le fichier est associé au template '$templateNameFromFile', qui n'est pas connu." -IconType "Error" | Out-Null
            return
        }

        # Configurer l'application avec le bon template.
        $templateConfig = $global:ApplicationTemplates[$templateNameFromFile]
        $script:activeTemplateName = $templateNameFromFile
        $global:ElementMappings = $templateConfig.ElementMappings
        $global:XmlSchema = $templateConfig.XmlSchema

        # Finaliser l'ouverture et mettre à jour l'UI.
        $script:xmlDoc = $xmlDoc
        $script:currentFilePath = $filePath
        $script:hasUnsavedChanges = $false
        
        Update-TreeViewFromXml -TreeView $script:ui.XmlTreeView -XmlDocument $script:xmlDoc
        Update-WindowTitle
        
        $script:ui.LabelCurrentFile.Text = "$script:currentFilePath ($templateNameFromFile)"
        $script:ui.StatusText.Text = "Fichier chargé avec succès."
        
        $script:ui.ButtonSave.IsEnabled = $true
        $script:ui.ButtonSaveAs.IsEnabled = $true
        $script:ui.ButtonValidateXml.IsEnabled = $true

    } catch {
        Show-MessageBox -Title "Erreur d'Ouverture" -Message "Erreur lors du chargement du fichier :`n$($_.Exception.Message)" -IconType "Error" | Out-Null
    }
}

function Do-SaveFile {
    if (-not $script:xmlDoc) {return}
    if ($script:activeTemplateName) {
        $script:xmlDoc.DocumentElement.SetAttribute("template", $script:activeTemplateName)
    }
    if ([string]::IsNullOrEmpty($script:currentFilePath)) {
        Do-SaveFileAs
    } else {
        if (Save-XmlDocument -XmlDocument $script:xmlDoc -FilePath $script:currentFilePath) {
            $script:hasUnsavedChanges = $false; Update-WindowTitle; $script:ui.StatusText.Text = "Fichier sauvegardé."
        } else {
            Show-MessageBox -Title "Erreur" -Message "Erreur de sauvegarde." -IconType "Error" | Out-Null
        }
    }
}

function Do-SaveFileAs {
    if (-not $script:xmlDoc) {return}
    $saveFileDialog = New-Object Microsoft.Win32.SaveFileDialog
    $saveFileDialog.Filter = "Fichiers XML (*.xml)|*.xml"; $saveFileDialog.Title = "Sauvegarder sous..."
    $saveFileDialog.FileName = if ($script:currentFilePath) { (Split-Path $script:currentFilePath -Leaf) } else { "document.xml" }
    if ($saveFileDialog.ShowDialog() -eq $true) {
        $newFilePath = $saveFileDialog.FileName
        if (Save-XmlDocument -XmlDocument $script:xmlDoc -FilePath $newFilePath) {
            $script:currentFilePath = $newFilePath; $script:hasUnsavedChanges = $false; Update-WindowTitle
            $script:ui.LabelCurrentFile.Text = $script:currentFilePath; $script:ui.StatusText.Text = "Fichier sauvegardé."
        } else {
            Show-MessageBox -Title "Erreur" -Message "Erreur de sauvegarde." -IconType "Error" | Out-Null
        }
    }
}

# ===================================================================
# DÉMARRAGE DE L'APPLICATION
# ===================================================================

# Chargement du dictionnaire de ressources (styles)
$global:stylesXamlPath  = Join-Path -Path $global:stylePath  -ChildPath "styles.xaml"
$stylesDictionary = Load-File -Path $global:stylesXamlPath
if (-not $stylesDictionary) { Write-Warning "Le fichier de styles partagés n'a pas pu être chargé." }

$xamlPath = Join-Path -Path $global:stylePath -ChildPath "UI_XMLEditor.xaml"
$UI_XMLEditor = Load-File -Path $xamlPath

# Définir l'icône (chemin vers un fichier .ico)
$iconPath = $global:icoPath + "\xml-editor.ico"
$UI_XMLEditor.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create((New-Object System.Uri($iconPath, [System.UriKind]::Absolute)))



if ($null -ne $UI_XMLEditor) {
    if ($stylesDictionary) { 
        $UI_XMLEditor.Resources.MergedDictionaries.Add($stylesDictionary)
    }
    
    # -- Initialisation des variables de session --
    $script:xmlDoc = $null
    $script:currentFilePath = ""
    $script:hasUnsavedChanges = $false

    $script:activeTemplateName = ""
    $script:activeElementMappings = $null
    $script:activeXmlSchema = $null

    # -- Registre des contrôles UI --
    $script:ui = @{}
    try {
        $script:ui.Window = $UI_XMLEditor
        $script:ui.Styles = $stylesDictionary
        $script:ui.ButtonNew = $UI_XMLEditor.FindName("ButtonNew"); $script:ui.ButtonOpen = $UI_XMLEditor.FindName("ButtonOpen"); $script:ui.ButtonSave = $UI_XMLEditor.FindName("ButtonSave")
        $script:ui.ButtonSaveAs = $UI_XMLEditor.FindName("ButtonSaveAs"); $script:ui.ButtonValidateXml = $UI_XMLEditor.FindName("ButtonValidateXml"); $script:ui.ButtonClose = $UI_XMLEditor.FindName("ButtonClose")
        $script:ui.XmlTreeView = $UI_XMLEditor.FindName("XmlTreeView")
        $script:ui.TreeViewScrollViewer = $UI_XMLEditor.FindName("TreeViewScrollViewer")
        $script:ui.ButtonAddElement = $UI_XMLEditor.FindName("ButtonAddElement"); $script:ui.ButtonDuplicate = $UI_XMLEditor.FindName("ButtonDuplicate")
        $script:ui.ButtonMoveUp = $UI_XMLEditor.FindName("ButtonMoveUp"); $script:ui.ButtonMoveDown = $UI_XMLEditor.FindName("ButtonMoveDown"); $script:ui.ButtonDelete = $UI_XMLEditor.FindName("ButtonDelete")
        $script:ui.PropertiesHostPanel = $UI_XMLEditor.FindName("PropertiesHostPanel"); $script:ui.PropertiesInstructionText = $UI_XMLEditor.FindName("PropertiesPanel_InstructionText")
        $script:ui.StatusText = $UI_XMLEditor.FindName("StatusText"); $script:ui.LabelCurrentFile = $UI_XMLEditor.FindName("LabelCurrentFile")
    } catch { Write-Error "ERREUR CRITIQUE: Un contrôle XAML est introuvable. $_"; [System.Windows.MessageBox]::Show("Erreur de liaison XAML.", "Erreur", "OK", "Stop"); Exit }
    
    # -- État initial des contrôles --
    $script:ui.ButtonSave.IsEnabled = $false; $script:ui.ButtonSaveAs.IsEnabled = $false; $script:ui.ButtonValidateXml.IsEnabled = $false

    # --- GESTIONNAIRES D'ÉVÉNEMENTS ---
    $script:ui.ButtonNew.Add_Click({ Do-NewFile })
    $script:ui.ButtonOpen.Add_Click({ Do-OpenFile })
    $script:ui.ButtonSave.Add_Click({ Do-SaveFile })
    $script:ui.ButtonSaveAs.Add_Click({ Do-SaveFileAs })
    
    $script:ui.ButtonClose.Add_Click({ 
        if (Confirm-UnsavedChanges) { 
            $script:ui.Window.Close() 
        } 
    })
    
    $script:ui.Window.add_Closing({ 
        param($s,$e) 
        if (-not (Confirm-UnsavedChanges)) { 
            $e.Cancel = $true 
        } 
    })
    
    $script:ui.ButtonValidateXml.Add_Click({ 
        if (-not $script:xmlDoc) {return}
        $tmp = Join-Path $env:TEMP "preview.xml"
        $script:xmlDoc.Save($tmp)
        Invoke-Item $tmp 
    })
    
    $script:ui.XmlTreeView.Add_SelectedItemChanged({ 
        Update-UIOnSelection -UI $script:ui 
    })

    $script:ui.ButtonAddElement.Add_Click({
        $script:contextualTreeViewItem = $script:ui.XmlTreeView.SelectedItem
        if (-not $script:contextualTreeViewItem) { return }
        $script:contextualParentNode = $script:contextualTreeViewItem.Tag
        $parentName = $script:contextualParentNode.LocalName.ToLower()
        $allowedChildren = $global:XmlSchema[$parentName]
        if (-not $allowedChildren) {
            Show-MessageBox -Title "Info" -Message "Aucun élément enfant ne peut être ajouté." -IconType "Information" | Out-Null
            return
        }
        $menu = $script:ui.Window.FindResource("AddElementMenu")
        $menu.Items.Clear()
        foreach ($childName in $allowedChildren) {
            $mapping = $global:ElementMappings[$childName]
            $menuItem = New-Object System.Windows.Controls.MenuItem
            $menuItem.Header = "Ajouter $($mapping.Icon) <$childName>"
            $menuItem.Tag = $childName
            $menuItem.Add_Click({
                param($sender, $e)
                $name = $sender.Tag
                $newNode = Add-XmlElement -XmlDocument $script:xmlDoc -ParentElement $script:contextualParentNode -NewElementName $name
                if ($newNode) {
                    $map = $global:ElementMappings[$name]
                    foreach ($attr in $map.DefaultAttributes.GetEnumerator()) { $newNode.SetAttribute($attr.Name, $attr.Value) }
                    
                    ### CORRECTION DE L'APPEL ###
                    # Pas besoin de récursion ici, on ajoute juste UN item.
                    $newItem = New-TreeViewItemFromXmlNode -XmlNode $newNode
                    
                    $index = Get-InsertionIndex -parentItemsControl $script:contextualTreeViewItem -newElementName $name
                    $script:contextualTreeViewItem.Items.Insert($index, $newItem)
                    $script:contextualTreeViewItem.IsExpanded = $true
                    $newItem.IsSelected = $true
                    $script:ui.XmlTreeView.Focus()
                    $script:hasUnsavedChanges = $true
                    Update-WindowTitle
                }
            })
            $menu.Items.Add($menuItem) | Out-Null
        }
        $menu.PlacementTarget = $script:ui.ButtonAddElement
        $menu.IsOpen = $true
    })

    $script:ui.ButtonDelete.Add_Click({
        $item = $script:ui.XmlTreeView.SelectedItem
        if (-not $item) { return }
        $node = $item.Tag
        $confirm = Show-MessageBox -Title "Confirmer" -Message "Supprimer <$($node.LocalName)> et ses enfants ?" -ButtonType "YesNo" -IconType "Warning"
        if ($confirm -eq 'Yes') {
            if (Remove-XmlElement -NodeToDelete $node) {
                $item.Parent.Items.Remove($item)
                $script:hasUnsavedChanges = $true
                Update-WindowTitle
            }
        }
    })

    $script:ui.ButtonDuplicate.Add_Click({
        $itemToDuplicate = $script:ui.XmlTreeView.SelectedItem
        if (-not $itemToDuplicate) { return }

        $nodeToDuplicate = $itemToDuplicate.Tag
        $clonedNode = Duplicate-XmlElement -NodeToDuplicate $nodeToDuplicate
        
        if ($clonedNode) {
            # On crée l'item racine du sous-arbre dupliqué
            $newTreeViewItem = New-TreeViewItemFromXmlNode -XmlNode $clonedNode
            
            # --- NOUVELLE LOGIQUE RÉCURSIVE LOCALE ---
            # On crée une petite fonction qui sait comment peupler les enfants d'un item
            function Add-ChildrenToViewItem {
                param(
                    [System.Xml.XmlNode]$xmlParent,
                    [System.Windows.Controls.TreeViewItem]$viewParent
                )
                
                # On utilise exactement la même logique de tri que dans Update-TreeViewFromXml
                $childrenToSort = @()
                foreach ($childNode in $xmlParent.ChildNodes) {
                    if ($childNode.NodeType -eq 'Element') { $childrenToSort += $childNode }
                }
                $sortedChildren = $childrenToSort | Sort-Object {
                    $mapping = $global:ElementMappings[$_.LocalName.ToLower()] ?? $global:ElementMappings['__default__']
                    return $mapping.SortOrder
                }

                # On peuple les enfants
                foreach ($sortedChild in $sortedChildren) {
                    $childViewItem = New-TreeViewItemFromXmlNode -XmlNode $sortedChild
                    $viewParent.Items.Add($childViewItem) | Out-Null
                    # Appel récursif pour les petits-enfants
                    Add-ChildrenToViewItem -xmlParent $sortedChild -viewParent $childViewItem
                }
            }
            
            # On appelle notre fonction pour peupler le nouvel item avec ses enfants
            Add-ChildrenToViewItem -xmlParent $clonedNode -viewParent $newTreeViewItem

            # --- Insertion dans l'arbre principal ---
            $parentItem = $itemToDuplicate.Parent
            $originalIndex = $parentItem.Items.IndexOf($itemToDuplicate)
            $parentItem.Items.Insert($originalIndex + 1, $newTreeViewItem)

            # Finalisation
            $newTreeViewItem.IsSelected = $true
            $newTreeViewItem.IsExpanded = $true
            $script:ui.XmlTreeView.Focus()
            $script:hasUnsavedChanges = $true
            Update-WindowTitle
        } else {
            Show-MessageBox -Title "Erreur" -Message "Une erreur est survenue lors de la duplication." -IconType "Error" | Out-Null
        }
    })

    $script:ui.ButtonMoveUp.Add_Click({
        $item = $script:ui.XmlTreeView.SelectedItem
        if (-not $item) { return }
        if (Move-XmlNodeUp -NodeToMove $item.Tag) {
            $parent = $item.Parent
            $index = $parent.Items.IndexOf($item)
            if ($index -gt 0) {
                $parent.Items.Remove($item)
                $parent.Items.Insert($index - 1, $item)
                $item.IsSelected = $true
                $script:ui.XmlTreeView.Focus()
                $script:hasUnsavedChanges = $true
                Update-WindowTitle
            }
        }
    })

    $script:ui.ButtonMoveDown.Add_Click({
        $item = $script:ui.XmlTreeView.SelectedItem
        if (-not $item) { return }
        if (Move-XmlNodeDown -NodeToMove $item.Tag) {
            $parent = $item.Parent
            $index = $parent.Items.IndexOf($item)
            # Utilisation de -lt (Less Than) pour la comparaison
            if ($index -lt ($parent.Items.Count - 1)) {
                $parent.Items.Remove($item)
                $parent.Items.Insert($index + 1, $item)
                $item.IsSelected = $true
                $script:ui.XmlTreeView.Focus()
                $script:hasUnsavedChanges = $true
                Update-WindowTitle
            }
        }
    })
    
    # --- Gestion manuelle des raccourcis ---
    $script:ui.Window.Add_KeyDown({
        param($sender, $e)
        if ($e.KeyboardDevice.Modifiers -eq [System.Windows.Input.ModifierKeys]::Control) {
            switch ($e.Key) {
                "N" { Do-NewFile; $e.Handled = $true }
                "O" { Do-OpenFile; $e.Handled = $true }
                "S" { if ($script:ui.ButtonSave.IsEnabled) { Do-SaveFile }; $e.Handled = $true }
            }
        } elseif ($e.KeyboardDevice.Modifiers -eq ([System.Windows.Input.ModifierKeys]::Control + [System.Windows.Input.ModifierKeys]::Shift) -and $e.Key -eq 'S') {
            if ($script:ui.ButtonSaveAs.IsEnabled) { Do-SaveFileAs; $e.Handled = $true }
        }
    })

    $script:ui.TreeViewScrollViewer.Add_PreviewMouseWheel({
        param($sender, $e)
        
        # Le sender est maintenant le ScrollViewer lui-même.
        $scrollViewer = $sender
        
        # On fait défiler le ScrollViewer de la quantité de la molette.
        # Note : On ne change pas la direction, on ajoute le delta (qui est négatif ou positif).
        # C'est une erreur commune, il faut bien soustraire.
        $scrollViewer.ScrollToVerticalOffset($scrollViewer.VerticalOffset - $e.Delta)
        
        # On marque l'événement comme géré pour éviter tout comportement parasite.
        $e.Handled = $true
    })

    # --- AFFICHAGE DE LA FENÊTRE ---
    Write-Verbose "Affichage de la fenêtre principale."
    $script:ui.Window.ShowDialog() | Out-Null
    Write-Verbose "Fenêtre principale fermée. Fin du script."
}
else {
    Write-Error "ERREUR CRITIQUE: Le chargement du XAML principal a échoué."
}