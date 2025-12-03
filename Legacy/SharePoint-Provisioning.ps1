# SharePoint-Provisioning.ps1
# Version 1.13 - Permissions, tag et lien OK et parametré et en assisté

param(
    # On garde les déclarations propres, sans valeurs par défaut pour les tests
    [string]$DefaultSiteUrl,
    [string]$DefaultLibraryName,
    [string]$DefaultDestinationUrl,
    [string]$DefaultXmlPath,
    [switch]$CreateNewFolder,
    [string]$DefaultTemplateName,
    [switch]$OverwritePermissions
)

$script:launchParameters = $null
$script:testValues = $null
$script:paramsToUse = $null

# On sauvegarde une copie des VRAIS paramètres passés au lancement.
$script:launchParameters = @{}
foreach ($param in $PSBoundParameters.GetEnumerator()) {
    $script:launchParameters[$param.Key] = $param.Value
}


# --- On définit les valeurs de TEST ici, de manière séparée et claire ---
# $script:testValues = @{
#     DefaultSiteUrl = "https://vosgelis365.sharepoint.com/sites/TEST_PNP/"
#     DefaultLibraryName = "Documents"
#     DefaultDestinationUrl = "https://vosgelis365.sharepoint.com/sites/TEST_PNP/Shared Documents/General/DESTINATION"
#     DefaultXmlPath = "C:\CLOUD\Github\PowerShell_Scripts\PROJECT\ToolBox\resources\xml\test2.xml"
#     CreateNewFolder = $true
#     DefaultTemplateName = "VEFA"
#     OverwritePermissions = $true
# }

# --- Initialisation ---
if (-not $global:globalPath) {
    $global:globalPath = (Resolve-Path (Join-Path $PSScriptRoot "..\")).Path
}
$global:functionsPath = Join-Path $global:globalPath "functions"
$global:resourcesPath = Join-Path $global:globalPath "resources"
$global:stylePath     = Join-Path $global:globalPath "styles"
$global:icoPath       = Join-Path $global:globalPath "resources\ico"
try {
    . (Join-Path $global:functionsPath "Get-Function.ps1")
    Get-Function -FunctionName Load-File -FunctionsPath $global:functionsPath
    Get-Function -FunctionName Load-Assembly -FunctionsPath $global:functionsPath
    Get-Function -FunctionName Add-RichText -FunctionsPath $global:functionsPath
    Get-Function -FunctionName Show-MessageBox -FunctionsPath $global:functionsPath
    Get-Function -FunctionName Show-CopyableMessageBox -FunctionsPath $global:functionsPath
    Load-Assembly -AssemblyNames @("PresentationCore", "PresentationFramework", "System.Windows.Forms")
    [System.Windows.Forms.Application]::EnableVisualStyles()
    if (-not $global:stylesXAML) {
        $global:stylesXamlPath = Join-Path $global:stylePath "styles.xaml"
        $global:stylesXAML = Load-File -Path $global:stylesXamlPath
    }
    # Chargement des paramètres globaux de l'application
        $settingsPath = Join-Path $global:resourcesPath "settings.ps1"
        Load-File -Path $settingsPath
} catch {
    [System.Windows.MessageBox]::Show("Erreur critique durant l'initialisation du script : $($_.Exception.Message)", "Erreur Bootstrap", "OK", "Stop")
    Exit
}

#Chargement des templates XML
$templatesXmlPath = Join-Path -Path $global:resourcesPath -ChildPath "templatesXML.ps1"
if (Test-Path $templatesXmlPath) { Load-File -Path $templatesXmlPath } else { Write-Warning "Fichier de configuration des templates XML ('templatesXML.ps1') introuvable." }

#Chargement des templates de noms de dossiers
$folderTemplatesPath = Join-Path -Path $global:resourcesPath -ChildPath "FolderNameTemplates.ps1"
if (Test-Path $folderTemplatesPath) { Load-File -Path $folderTemplatesPath } else { Write-Warning "Fichier de configuration des templates de dossiers ('FolderNameTemplates.ps1') introuvable." }

# --- Logique Spécifique à l'Application ---
# 1. Chargement UI et récupération contrôles
$xamlPath = Join-Path $global:stylePath "UI_SharePointProvisioning.xaml"
$Window = Load-File -Path $xamlPath

# Définir l'icône (chemin vers un fichier .ico)
$iconPath = $global:icoPath + "\folder-structure.ico"
$Window.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create((New-Object System.Uri($iconPath, [System.UriKind]::Absolute)))

if ($global:stylesXAML) { $Window.Resources.MergedDictionaries.Add($global:stylesXAML) }
$Controls = @{
    LogRichTextBox                  = $Window.FindName("LogRichTextBox")
    StatusTextBox                   = $Window.FindName("StatusTextBox")
    CopyUrlButton                   = $Window.FindName("CopyUrlButton")
    OpenUrlButton                   = $Window.FindName("OpenUrlButton")
    DeployButton                    = $Window.FindName("DeployButton")
    SiteComboBox                    = $Window.FindName("SiteComboBox")
    LibraryComboBox                 = $Window.FindName("LibraryComboBox")
    TargetTreeView                  = $Window.FindName("TargetTreeView")
    TargetTreeViewScrollViewer      = $Window.FindName("TargetTreeViewScrollViewer")
    LoadXmlModelButton              = $Window.FindName("LoadXmlModelButton")
    SourceXmlTreeView               = $Window.FindName("SourceXmlTreeView")
    SourceXmlTreeViewScrollViewer   = $Window.FindName("SourceXmlTreeViewScrollViewer")
    CreateFolderCheckBox            = $Window.FindName("CreateFolderCheckBox")
    TemplateComboBox                = $Window.FindName("TemplateComboBox")
    DynamicFormHolder               = $Window.FindName("DynamicFormHolder")
    OverwritePermissionsCheckBox    = $Window.FindName("OverwritePermissionsCheckBox")
    ExportConfigButton              = $Window.FindName("ExportConfigButton")
    XmlFileNameTextBlock            = $Window.FindName("XmlFileNameTextBlock")
    ResetUIButton                   = $Window.FindName("ResetUIButton")
    DeploymentProgressBar           = $Window.FindName("DeploymentProgressBar")
}

# 3. Variables d'état
$script:isResettlingUI = $false
$script:IsConnected = $false
$script:deploymentTargetUrl = $absoluteUrl
$Controls.StatusTextBox.Text = "Destination prête : $script:deploymentTargetUrl"
$script:pnpListObject = $null
$script:xmlModel = $null
$script:allFoldersMap = @{}
$script:onTreeViewItemExpanded = {
    param($sender, $e)
    $expandedItem = $e.OriginalSource -as [System.Windows.Controls.TreeViewItem]
    if ($expandedItem.Items.Count -ne 1 -or -not ($expandedItem.Items[0] -is [string])) { return }
    $expandedItem.Dispatcher.Invoke([Action]{ $expandedItem.Items.Clear() })
    $pnpFolderItem = $expandedItem.Tag
    # On passe l'objet TreeViewItem pour qu'il soit rempli.
    Load-PnPChildrenIntoTreeViewItem -ParentFolderUrl $pnpFolderItem.ServerRelativeUrl -WpfParentItem $expandedItem
}

# 4. Fonctions
function Load-XmlModelFromFile {
    param([string]$FilePath)

    Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "Chargement du modèle XML depuis : $FilePath" -Color "Blue" -AddNewLine $true
    
    try {
        if (-not (Test-Path -Path $FilePath -PathType Leaf)) {
            throw "Le fichier spécifié n'existe pas."
        }
        
        $xmlDoc = New-Object System.Xml.XmlDocument
        $xmlDoc.Load($FilePath)
        
        $templateNameFromFile = $xmlDoc.DocumentElement.GetAttribute("template")
        if (-not $global:ApplicationTemplates.ContainsKey($templateNameFromFile)) {
            throw "Le type de template '$templateNameFromFile' n'est pas reconnu."
        }
        
        $script:activeXmlTemplateName = $templateNameFromFile
        $script:xmlModel = $xmlDoc
        $script:xmlModelPath = $FilePath # <-- On stocke le chemin pour l'export futur

        $fileName = Split-Path $FilePath -Leaf
        $Controls.XmlFileNameTextBlock.Text = $fileName
        $Controls.XmlFileNameTextBlock.ToolTip = $FilePath # On met le chemin complet dans le tooltip

        Update-TreeViewFromXml -TreeView $Controls.SourceXmlTreeView -XmlDocument $script:xmlModel
        
        Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "Modèle '$((Split-Path $FilePath -Leaf))' chargé avec succès." -Color "Green" -IsBold $true -AddNewLine $true
        
        # Désactiver le bouton de chargement manuel
        $Controls.LoadXmlModelButton.IsEnabled = $false
        
    } catch {
        Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "ERREUR lors du chargement du modèle XML : $($_.Exception.Message)" -Color "Red" -AddNewLine $true
        $script:xmlModel = $null
        $script:xmlModelPath = $null
        $Controls.XmlFileNameTextBlock.Text = "" # On vide le nom en cas d'erreur
        $Controls.XmlFileNameTextBlock.ToolTip = ""
        $Controls.LoadXmlModelButton.IsEnabled = $true
    }
    
    Update-ButtonsState
}

function Populate-LibraryList {
    param(
        [string]$SiteUrl
        # On supprime l'ancien paramètre -LibraryNameToSelect, il n'est plus utile.
    )
    Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "-> Connexion au site '$SiteUrl' pour lister les bibliothèques..." -Color "Gray" -AddNewLine $true
    try {
        Connect-PnPOnline -Url $SiteUrl -ClientId $global:ClientID -Tenant "vosgelis365.onmicrosoft.com" -Thumbprint $global:CertificateThumbprint -ErrorAction Stop
        $libraries = Get-PnPList | Where-Object { $_.BaseTemplate -eq 101 } | Sort-Object Title
        $Controls.LibraryComboBox.ItemsSource = $libraries
        Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "-> $($libraries.Count) bibliothèque(s) trouvée(s). Veuillez en sélectionner une." -Color "Green" -AddNewLine $true

        # === CORRECTION ICI : On consulte les paramètres de lancement ===
        # On regarde si le paramètre DefaultLibraryName a été fourni au démarrage.
        if ($script:paramsToUse.ContainsKey('DefaultLibraryName')) {
            $libraryNameToSelect = $script:paramsToUse.DefaultLibraryName
            $libraryToSelect = $libraries | Where-Object { $_.Title -eq $libraryNameToSelect } | Select-Object -First 1
            
            if ($libraryToSelect) {
                # On sélectionne la bibliothèque. L'événement SelectionChanged se chargera du reste.
                $Controls.LibraryComboBox.SelectedItem = $libraryToSelect
                Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "-> Bibliothèque '$libraryNameToSelect' pré-sélectionnée par paramètre." -Color "Blue" -AddNewLine $true
            } else {
                Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "AVERTISSEMENT : La bibliothèque par défaut '$libraryNameToSelect' n'a pas été trouvée." -Color "Orange" -AddNewLine $true
                $Controls.LibraryComboBox.IsEnabled = $true
            }
        } else {
            # Si aucun paramètre n'a été fourni, on active simplement la ComboBox pour un choix manuel.
            $Controls.LibraryComboBox.IsEnabled = $true
        }
        # =============================================================

    } catch {
        Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "ERREUR lors de la connexion/récupération des bibliothèques : $($_.Exception.Message)" -Color "Red" -AddNewLine $true
    }
}

function Initialize-PnPConnection {
    Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "Initialisation de la connexion applicative à SharePoint..." -Color "Blue" -AddNewLine $true
    try {
        $adminUrl = "https://vosgelis365-admin.sharepoint.com"
        Connect-PnPOnline -Url $adminUrl -ClientId $global:ClientID -Tenant "vosgelis365.onmicrosoft.com" -Thumbprint $global:CertificateThumbprint -ErrorAction Stop
        $script:IsConnected = $true
        Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "STATUT : Connecté au portail d'administration" -Color "Green" -IsBold $true -AddNewLine $true
        return $true
    } catch {
        $script:IsConnected = $false
        Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "ERREUR : $($_.Exception.Message)" -Color "Red" -AddNewLine $true
        return $false
    }
}

# Crée un TreeViewItem stylisé à partir d'un objet PnP (ListItem)
function New-TreeViewItemForPnPFolder {
    param(
        [Parameter(Mandatory=$true)]
        $PnpFolderObject
    )
    
    $treeViewItem = New-Object System.Windows.Controls.TreeViewItem
    $treeViewItem.Tag = $PnpFolderObject

    # ... (la création du header reste la même) ...
    $headerPanel = New-Object System.Windows.Controls.StackPanel -Property @{ Orientation = "Horizontal" }
    $iconBlock = New-Object System.Windows.Controls.TextBlock -Property @{ Margin = "0,0,5,0"; VerticalAlignment = "Center"; Text = "📁"; Foreground = [System.Windows.Media.Brushes]::Goldenrod }
    $nameBlock = New-Object System.Windows.Controls.TextBlock -Property @{ Text = $PnpFolderObject.Name; VerticalAlignment = "Center" }
    $headerPanel.Children.Add($iconBlock) | Out-Null
    $headerPanel.Children.Add($nameBlock) | Out-Null
    $treeViewItem.Header = $headerPanel

    $folderProperties = Get-PnPFolder -Url $PnpFolderObject.ServerRelativeUrl -Includes ItemCount
    
    if ($folderProperties.ItemCount -gt 0) {
        # On ajoute le placeholder invisible
        $treeViewItem.Items.Add($null) | Out-Null

        # === CORRECTION : On utilise une variable de statut dans le Tag ===
        # Au lieu de se désabonner, on vérifie simplement si le chargement a déjà eu lieu.
        $treeViewItem.Tag = @{
            PnpFolderObject = $PnpFolderObject
            IsLoaded = $false
        }
        $treeViewItem.add_Expanded({
            param($sender, $e)

            # Si c'est déjà chargé, on ne fait rien.
            if ($sender.Tag.IsLoaded) { return }
            
            # On passe le statut à "chargé" pour que ce bloc ne s'exécute plus.
            $sender.Tag.IsLoaded = $true

            $expandedItem = $e.OriginalSource -as [System.Windows.Controls.TreeViewItem]
            $expandedItem.Dispatcher.Invoke([Action]{ $expandedItem.Items.Clear() })
            
            $originalCursor = $Window.Cursor
            try {
                $Window.Cursor = [System.Windows.Input.Cursors]::Wait
                Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "Exploration de '$($expandedItem.Tag.PnpFolderObject.Name)'..." -Color "DarkSlateGray" -AddNewLine $true
                $Window.Dispatcher.Invoke([System.Action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
                Load-PnPChildrenIntoTreeViewItem -ParentFolderUrl $expandedItem.Tag.PnpFolderObject.ServerRelativeUrl -WpfParentItem $expandedItem
            } finally {
                $Window.Cursor = $originalCursor
            }
        })
    }

    return $treeViewItem
}

# -- NOUVELLE FONCTION CORE : Charge les enfants d'un dossier, avec fallbacks --
function Load-FolderChildren {
    param([System.Windows.Controls.TreeViewItem]$ParentItem)

    $parentData = $ParentItem.Tag
    if ($parentData.IsLoaded) { return }

    try {
        $folderUrl = $parentData.ServerRelativeUrl
        $subFolders = $null

        # Méthode 1: Get-PnPFolderItem
        try {
            $subFolders = Get-PnPFolderItem -FolderSiteRelativeUrl $folderUrl -ItemType Folder -ErrorAction Stop
        } catch {
            # Méthode 2 (Fallback) : Get-PnPFolder
            try {
                $parentPnPFolder = Get-PnPFolder -Url $folderUrl -ErrorAction Stop
                $ctx = Get-PnPContext
                $ctx.Load($parentPnPFolder.Folders)
                $ctx.ExecuteQuery()
                $subFolders = $parentPnPFolder.Folders
            } catch {
                Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "ERREUR: Toutes les méthodes de chargement ont échoué pour '$folderUrl'." -Color "Red" -AddNewLine $true
                $subFolders = @() # Assurer que c'est une collection vide
            }
        }

        $ParentItem.Items.Clear()

        if ($subFolders.Count -eq 0) {
            $emptyItem = New-Object System.Windows.Controls.TreeViewItem -Property @{ Header = "(Aucun sous-dossier)"; IsEnabled = $false; FontStyle = "Italic"; Foreground = [System.Windows.Media.Brushes]::Gray }
            $ParentItem.Items.Add($emptyItem) | Out-Null
        } else {
            foreach ($folder in $subFolders) {
                $childItem = New-TreeViewItemForPnPProvisioning -PnpFolderObject $folder
                $ParentItem.Items.Add($childItem) | Out-Null
            }
        }
        
        $parentData.IsLoaded = $true
    } catch {
        Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "Erreur critique lors du chargement des enfants de '$($parentData.Name)'." -Color "Red" -IsBold $true -AddNewLine $true
    }
}

# -- NOUVELLE FONCTION CORE : Crée un TreeViewItem complet --
function New-TreeViewItemForPnPProvisioning {
    param([Parameter(Mandatory=$true)] $PnpFolderObject)
    
    $treeViewItem = New-Object System.Windows.Controls.TreeViewItem
    $hasChildren = Test-FolderHasChildren -FolderUrl $PnpFolderObject.ServerRelativeUrl

    # Création de l'en-tête avec icône et nom
    $headerPanel = New-Object System.Windows.Controls.StackPanel -Property @{ Orientation = "Horizontal" }
    $iconBlock = New-Object System.Windows.Controls.TextBlock -Property @{ Margin = "0,0,5,0"; VerticalAlignment = "Center"; Text = "📁"; Foreground = [System.Windows.Media.Brushes]::Goldenrod }
    $nameBlock = New-Object System.Windows.Controls.TextBlock -Property @{ Text = $PnpFolderObject.Name; VerticalAlignment = "Center" }
    $headerPanel.Children.Add($iconBlock) | Out-Null
    $headerPanel.Children.Add($nameBlock) | Out-Null
    $treeViewItem.Header = $headerPanel

    # Stockage des données importantes dans le Tag
    $treeViewItem.Tag = @{
        ServerRelativeUrl = $PnpFolderObject.ServerRelativeUrl
        Name = $PnpFolderObject.Name
        IsLoaded = $false
    }
    
    if ($hasChildren) {
        $treeViewItem.Items.Add("Chargement...") | Out-Null
        $treeViewItem.add_Expanded({
            Load-FolderChildren -ParentItem $this
        })
    }

    return $treeViewItem
}

# Charge les enfants directs d'un dossier dans un TreeViewItem parent.
function Load-PnPChildrenIntoTreeViewItem {
    param(
        [string]$ParentFolderUrl,
        [System.Windows.Controls.TreeViewItem]$WpfParentItem,
        [int]$SkipItems = 0
    )
    try {
        $pageSize = 10 

        $parentFolder = Get-PnPFolder -Url $ParentFolderUrl -Includes Folders
        $ctx = Get-PnPContext
        $ctx.Load($parentFolder.Folders)
        $ctx.ExecuteQuery()

        $allSortedSubFolders = $parentFolder.Folders | Sort-Object -Property Name
        $itemsToShow = $allSortedSubFolders | Select-Object -Skip $SkipItems -First $pageSize
        
        $totalItemsAvailable = $allSortedSubFolders.Count
        $itemsCurrentlyShown = $SkipItems + $itemsToShow.Count
        $hasMoreItems = $itemsCurrentlyShown -lt $totalItemsAvailable

        if ($SkipItems -gt 0) {
            $lastItem = $WpfParentItem.Items[-1]
            if ($lastItem -is [System.Windows.Controls.TreeViewItem] -and $lastItem.Tag.Type -eq "LoadMore") {
                $WpfParentItem.Items.Remove($lastItem)
            }
        }
        
        if ($WpfParentItem.Items.Count -eq 0 -and $itemsToShow.Count -eq 0) {
            $emptyItem = New-Object System.Windows.Controls.TreeViewItem -Property @{ Header = "(Aucun sous-dossier)"; IsEnabled = $false; FontStyle = "Italic"; Foreground = [System.Windows.Media.Brushes]::Gray }
            $WpfParentItem.Items.Add($emptyItem) | Out-Null
            return
        }

        foreach ($folder in $itemsToShow) {
            $childItem = New-TreeViewItemForPnPFolder -PnpFolderObject $folder
            $WpfParentItem.Items.Add($childItem) | Out-Null
        }

        if ($hasMoreItems) {
            $loadMoreItem = New-Object System.Windows.Controls.TreeViewItem
            $loadMoreItem.Header = "Charger plus ($itemsCurrentlyShown / $totalItemsAvailable)..."
            $loadMoreItem.Foreground = [System.Windows.Media.Brushes]::DodgerBlue
            $loadMoreItem.FontStyle = "Italic"
            
            # === CORRECTION : On stocke le contexte dans le Tag ===
            $loadMoreItem.Tag = @{
                Type            = "LoadMore"
                ParentFolderUrl = $ParentFolderUrl
                WpfParentItem   = $WpfParentItem
                SkipItems       = $itemsCurrentlyShown
            }
            
            $loadMoreItem.add_Selected({
                param($sender, $e)
                $loadMoreData = $sender.Tag
                $originalCursor = $Window.Cursor
                try {
                    $Window.Cursor = [System.Windows.Input.Cursors]::Wait
                    Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "Chargement des éléments suivants..." -Color "DarkSlateGray" -AddNewLine $true
                    $Window.Dispatcher.Invoke([System.Action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
                    # On utilise les données du Tag pour l'appel
                    Load-PnPChildrenIntoTreeViewItem -ParentFolderUrl $loadMoreData.ParentFolderUrl -WpfParentItem $loadMoreData.WpfParentItem -SkipItems $loadMoreData.SkipItems
                } finally { $Window.Cursor = $originalCursor }
            })
            $WpfParentItem.Items.Add($loadMoreItem) | Out-Null
        }
    } catch {
         $folderNameToLog = if ($ParentFolderUrl) { "'$ParentFolderUrl'" } else { "'' (URL VIDE)" }
         Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "Erreur lors du chargement du contenu de $folderNameToLog : $($_.Exception.Message)" -Color "Red" -AddNewLine $true
    }
}

# Fonction récursive qui utilise l'objet List directement
function Add-PnPChildrenToTreeView {
    param(
        [Parameter(Mandatory=$true)]
        [Microsoft.SharePoint.Client.List]$PnPList, # On passe l'objet List directement

        [Parameter(Mandatory=$true)]
        [string]$ParentFolderUrl, # URL relative du dossier parent

        [Parameter(Mandatory=$true)]
        [System.Windows.Controls.ItemsControl]$WpfParentItem
    )

    try {
        # La requête CAML pour trouver les enfants directs d'un dossier
        $camlQuery = @"
        <View Scope='RecursiveFiles'>
            <Query>
                <Where>
                    <Eq>
                        <FieldRef Name='FileDirRef' />
                        <Value Type='Text'>$ParentFolderUrl</Value>
                    </Eq>
                </Where>
            </Query>
            <ViewFields>
                <FieldRef Name='ID' />
                <FieldRef Name='FileLeafRef' />
                <FieldRef Name='FileRef' />
                <FieldRef Name='FSObjType' />
            </ViewFields>
        </View>
"@
        
        # === CORRECTION PRINCIPALE : On utilise -List avec l'objet $PnPList ===
        $childItems = Get-PnPListItem -List $PnPList -Query $camlQuery
        
        foreach ($child in $childItems) {
            $childTreeViewItem = New-TreeViewItemFromPnPItem -PnpListItem $child
            $WpfParentItem.Items.Add($childTreeViewItem) | Out-Null

            # Si l'enfant est un dossier (FSObjType = 1), on relance la fonction pour ses propres enfants
            if ($child.FieldValues.FSObjType -eq 1) {
                Add-PnPChildrenToTreeView -PnPList $PnPList -ParentFolderUrl $child.FieldValues.FileRef -WpfParentItem $childTreeViewItem
            }
        }
    } catch {
        $errorMessage = "Impossible de lister le contenu de '$ParentFolderUrl' : $($_.Exception.Message)"
        Add-RichText -RichTextBox $Controls.LogRichTextBox -Text $errorMessage -Color "Red" -AddNewLine $true
    }
}

# Fonction principale qui démarre le peuplement de la TreeView
function Populate-TargetTreeView {
    param([string]$LibraryTitle)
    
    $Controls.TargetTreeView.Items.Clear()
    Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "Analyse de la structure racine dans '$LibraryTitle'..." -Color "DarkCyan" -AddNewLine $true
    $Window.Cursor = [System.Windows.Input.Cursors]::Wait

    try {
        $list = Get-PnPList -Identity $LibraryTitle
        $rootPnPFolder = $list.RootFolder
        
        $rootTreeViewItem = New-TreeViewItemForPnPFolder -PnpFolderObject $rootPnPFolder
        ($rootTreeViewItem.Header.Children[0] -as [System.Windows.Controls.TextBlock]).Text = "📚"
        ($rootTreeViewItem.Header.Children[1] -as [System.Windows.Controls.TextBlock]).Text = $list.Title
        
        $Controls.TargetTreeView.Items.Add($rootTreeViewItem) | Out-Null
        
        # === CORRECTION MAJEURE : On déclenche la logique de sélection manuellement ===
        
        # 1. On programme la sélection visuelle
        $rootTreeViewItem.IsSelected = $true
        $rootTreeViewItem.BringIntoView()
        
        # 2. On exécute la logique de mise à jour de l'URL et des boutons
        $relativeUrl = $rootPnPFolder.ServerRelativeUrl
        $contextUri = [uri](Get-PnPContext).Url
        $absoluteUrl = "$($contextUri.Scheme)://$($contextUri.Host)$relativeUrl"
        $script:deploymentTargetUrl = $absoluteUrl

        # 3. On met à jour la barre de statut
        $displayText = "Destination prête : $script:deploymentTargetUrl"
        if ($displayText.Length -gt 80) {
            $displayText = "Destination prête : ...$($script:deploymentTargetUrl.Substring($script:deploymentTargetUrl.Length - 60))"
        }
        $Controls.StatusTextBox.Text = $displayText
        $Controls.StatusTextBox.ToolTip = $script:deploymentTargetUrl
        
        # 4. On active les boutons
        $Controls.CopyUrlButton.IsEnabled = $true
        $Controls.OpenUrlButton.IsEnabled = $true
        Update-ButtonsState # Cette fonction va vérifier si le modèle XML est aussi chargé et activer le bouton de déploiement

        # 5. On logue la sélection pour confirmation
        Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "Destination par défaut sélectionnée : '$relativeUrl'" -Color "DarkGreen" -AddNewLine $true
        
        Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "Structure racine chargée. Dépliez les dossiers pour explorer." -Color "Green" -AddNewLine $true
    } catch {
        Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "Erreur lors du peuplement initial de la TreeView pour '$LibraryTitle' : $($_.Exception.Message)" -Color "Red" -IsBold $true -AddNewLine $true
    } finally {
        $Window.Cursor = [System.Windows.Input.Cursors]::Arrow
    }
}

function New-TreeViewItemFromXmlNode {
    param(
        [Parameter(Mandatory=$true)] [System.Xml.XmlNode]$XmlNode
    )
    $treeViewItem = New-Object System.Windows.Controls.TreeViewItem
    $treeViewItem.Tag = $XmlNode
    
    # On utilise la config du template actif stockée dans une variable globale
    $mappings = $global:ApplicationTemplates[$script:activeXmlTemplateName].ElementMappings
    $nodeName = $XmlNode.LocalName.ToLower()
    $mapping = $mappings[$nodeName] ?? $mappings['__default__']
    
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

function Update-TreeViewFromXml {
    param(
        [Parameter(Mandatory = $true)] [System.Windows.Controls.TreeView]$TreeView,
        [Parameter(Mandatory = $true)] [System.Xml.XmlDocument]$XmlDocument
    )
    function Add-XmlNodeToTreeViewRecursive {
        param([System.Xml.XmlNode]$XmlNode, [System.Windows.Controls.ItemsControl]$ParentItemsControl)
        if ($XmlNode.NodeType -ne 'Element') { return }
        $treeViewItem = New-TreeViewItemFromXmlNode -XmlNode $XmlNode
        $ParentItemsControl.Items.Add($treeViewItem) | Out-Null
        
        $mappings = $global:ApplicationTemplates[$script:activeXmlTemplateName].ElementMappings
        
        $childrenToSort = @()
        foreach ($childNode in $XmlNode.ChildNodes) {
            if ($childNode.NodeType -eq 'Element') { $childrenToSort += $childNode }
        }
        $sortedChildren = $childrenToSort | Sort-Object {
            $map = $mappings[$_.LocalName.ToLower()] ?? $mappings['__default__']
            return $map.SortOrder
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

function Update-ButtonsState {
    # Si l'UI est en cours de réinitialisation, on ne fait rien.
    if ($script:isResettlingUI) { return }

    # --- Logique pour le bouton "Lancer le Déploiement" (inchangée) ---
    $shouldDeployBeEnabled = $false
    $isDestinationBaseReady = -not [string]::IsNullOrWhiteSpace($script:deploymentTargetUrl)
    $isSourceReady = $null -ne $script:xmlModel

    if ($isDestinationBaseReady -and $isSourceReady) {
        if ($Controls.CreateFolderCheckBox.IsChecked -ne $true) {
            $shouldDeployBeEnabled = $true
        } else {
            $isFormValid = $true
            if (-not $Controls.TemplateComboBox.SelectedItem) {
                $isFormValid = $false
            }
            if ($isFormValid) {
                $inputWrapPanel = Find-VisualChild -Visual ($Controls.DynamicFormHolder) -Type ([System.Windows.Controls.WrapPanel])
                if ($inputWrapPanel) {
                    $textBoxes = $inputWrapPanel.Children | Where-Object { $_ -is [System.Windows.Controls.TextBox] }
                    if ($textBoxes) { # S'assurer qu'il y a des textboxes à valider
                        foreach($tb in $textBoxes) {
                            if ([string]::IsNullOrWhiteSpace($tb.Text)) {
                                $isFormValid = $false
                                break
                            }
                        }
                    }
                } else {
                    $isFormValid = $false
                }
            }
            if ($isFormValid) {
                $shouldDeployBeEnabled = $true
            }
        }
    }
    $Controls.DeployButton.IsEnabled = $shouldDeployBeEnabled

    # --- NOUVELLE LOGIQUE pour le bouton "Ouvrir" et "Copier" ---
    $shouldOpenBeEnabled = $false
    # Le bouton est actif si une destination de base est sélectionnée.
    if ($isDestinationBaseReady) {
        # Si la case n'est PAS cochée, le chemin existe déjà, on peut l'ouvrir.
        if ($Controls.CreateFolderCheckBox.IsChecked -ne $true) {
            $shouldOpenBeEnabled = $true
        }
        # Si la case EST cochée, le chemin final n'existe pas encore.
        # Le bouton ne sera activé qu'après le déploiement via $script:lastDeploymentPath.
        # Donc on le laisse à $false pour l'instant.
    }
    
    # Si un déploiement vient d'avoir lieu ($script:lastDeploymentPath est rempli), on active le bouton.
    if (-not [string]::IsNullOrWhiteSpace($script:lastDeploymentPath)) {
        $shouldOpenBeEnabled = $true
    }

    $Controls.OpenUrlButton.IsEnabled = $shouldOpenBeEnabled
    $Controls.CopyUrlButton.IsEnabled = $isDestinationBaseReady # Le bouton Copier est actif dès qu'il y a une URL à copier.
}

# -- Fonction principale de déploiement --
function Start-Provisioning {
    if (-not $script:deploymentTargetUrl -or -not $script:xmlModel) { return }

    $finalDestinationUrl = $script:deploymentTargetUrl
    $newFolderName = ""

    if ($Controls.CreateFolderCheckBox.IsChecked -eq $true) {
        $previewLabel = Find-VisualChild -Visual ($Controls.DynamicFormHolder) -Type ([System.Windows.Controls.Label]) -Name "PreviewLabel"
        if ($previewLabel) { $newFolderName = $previewLabel.Content.ToString().Replace("Résultat : ", "").Trim() }
        $finalDestinationUrl = ($script:deploymentTargetUrl.TrimEnd('/')) + "/" + $newFolderName
    }
    
    $confirm = Show-MessageBox -Message "Déployer sur :`n$($finalDestinationUrl)`n`nContinuer ?" -Title "Confirmer" -ButtonType "YesNo" -IconType "Question"
    if ($confirm -ne "Yes") { Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "Déploiement annulé."; return }

    $Window.Cursor = [System.Windows.Input.Cursors]::Wait
    $Controls.DeployButton.IsEnabled = $false
    Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "--- DÉBUT DU DÉPLOIEMENT ---" -Color "Purple" -IsBold $true -AddTwoLine $true
    
    # === AJOUT : Initialisation de la ProgressBar ===
    $totalOperations = Count-XmlOperations -XmlNode $script:xmlModel.DocumentElement
    Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "Calcul du nombre d'opérations : $totalOperations" -Color "Gray" -AddNewLine $true
    $Controls.DeploymentProgressBar.Maximum = $totalOperations
    $Controls.DeploymentProgressBar.Value = 0
    $Controls.DeploymentProgressBar.Visibility = "Visible"
    # ===============================================

    try {
        $targetSiteUrl = $Controls.SiteComboBox.SelectedItem.Url
        Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "Connexion au site cible '$targetSiteUrl'..." -Color "DarkSlateGray" -AddNewLine $true
        Connect-PnPOnline -Url $targetSiteUrl -ClientId $global:ClientID -Tenant "vosgelis365.onmicrosoft.com" -Thumbprint $global:CertificateThumbprint -ErrorAction Stop

        # ==================== SOLUTION FINALE POUR LE NOM DE LA LIBRAIRIE ====================
        $baseAbsUrl = [uri]$script:deploymentTargetUrl
        $serverRelativePath = $baseAbsUrl.AbsolutePath
        $pathParts = $serverRelativePath.Split('/', [System.StringSplitOptions]::RemoveEmptyEntries)
        $internalLibraryName = $pathParts[2]
        
        if ([string]::IsNullOrWhiteSpace($internalLibraryName)) {
            throw "Impossible de déterminer le nom interne de la bibliothèque à partir de l'URL : '$serverRelativePath'."
        }
        
        # Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "Utilisation de la bibliothèque (déduit de l'URL) : '$internalLibraryName'" -Color "Blue" -AddNewLine $true
        # ===============================================================================
        
        $library = Get-PnPList -Identity $internalLibraryName
        $destinationSubFolderPath = $script:deploymentTargetUrl.Replace((Get-PnPContext).Url, "").Replace($library.RootFolder.ServerRelativeUrl, "").Trim('/')
        
        if ($Controls.CreateFolderCheckBox.IsChecked -eq $true -and -not [string]::IsNullOrWhiteSpace($newFolderName)) {
            $fullNewFolderPath = if ($destinationSubFolderPath) { "$destinationSubFolderPath/$newFolderName" } else { $newFolderName }
            Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "Création du dossier personnalisé : '$fullNewFolderPath'" -Color "Purple" -AddNewLine $true
            try {
                Add-PnPFolder -Name $newFolderName -Folder $destinationSubFolderPath | Out-Null
                $destinationSubFolderPath = $fullNewFolderPath
                Add-RichText -RichTextBox $Controls.LogRichTextBox -Text " -> Dossier créé avec succès." -Color "Green" -AddNewLine $true
            } catch {
                if ($_.Exception.Message -like "*already exists*") {
                    Add-RichText -RichTextBox $Controls.LogRichTextBox -Text " -> Avertissement : Le dossier existe déjà." -Color "Orange" -AddNewLine $true
                    $destinationSubFolderPath = $fullNewFolderPath
                } else { throw $_ }
            }
        }
        
        # On initialise le compteur à 0
        $operationCounter = 0

        # On passe le nom INTERNE correct à la fonction récursive.
        Deploy-XmlNode -XmlNode $script:xmlModel.DocumentElement -LibraryName $internalLibraryName -RelativeBasePath $destinationSubFolderPath -Counter ([ref]$operationCounter)
        
        Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "--- DÉPLOIEMENT TERMINÉ AVEC SUCCÈS ---" -Color "Green" -IsBold $true -AddTwoLine $true
        
        $script:lastDeploymentPath = $finalDestinationUrl
        # Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "Le bouton 'Ouvrir' pointe maintenant vers le dossier déployé." -Color "Blue" -AddNewLine $true

        Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "--- URL DE DEPLOIEMENT : $script:lastDeploymentPath ---" -Color "Green" -IsBold $true -AddTwoLine $true

        $choice = Show-MessageBox -Message "Le déploiement est terminé.`n`nVoulez-vous préparer un nouveau déploiement ?" -Title "Déploiement Réussi" -ButtonType "YesNo" -IconType "Question"

        if ($choice -eq "Yes") {
            Reset-UIForNewDeployment
        }

    } catch {
        Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "--- ERREUR CRITIQUE PENDANT LE DÉPLOIEMENT : $($_.Exception.Message) ---" -Color "Red" -IsBold $true -AddTwoLine $true
    } finally {
        $Controls.DeploymentProgressBar.Visibility = "Collapsed"
        $Window.Cursor = [System.Windows.Input.Cursors]::Arrow
        Update-ButtonsState
    }
}

# -- Fonction récursive qui traite chaque nœud XML --
function Deploy-XmlNode {
    param(
        [System.Xml.XmlNode]$XmlNode,
        [string]$LibraryName,
        [string]$RelativeBasePath,
        [ref]$Counter
    )

    if ($XmlNode.NodeType -ne 'Element') { return }

    $currentRelativePath = $RelativeBasePath
    $updateActionsAllowed = $true

    switch ($XmlNode.LocalName) {
        "directory" {
            $folderName = $XmlNode.GetAttribute("name")
            $fullRelativePath = if ([string]::IsNullOrEmpty($RelativeBasePath)) { $folderName } else { "$RelativeBasePath/$folderName" }
            Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "Traitement dossier : '$fullRelativePath'..." -Color "DarkCyan" -AddNewLine $true
            
            try {
                Add-PnPFolder -Name $folderName -Folder $RelativeBasePath | Out-Null
                $Counter.Value++; $Controls.DeploymentProgressBar.Value = $Counter.Value; $Window.Dispatcher.Invoke([System.Action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
                Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "  -> Dossier '$folderName' créé avec succès." -Color "Green" -AddNewLine $true
                $currentRelativePath = $fullRelativePath
            } catch {
                if ($_.Exception.Message -like "*already exists*") {
                    Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "  -> Avertissement : Le dossier '$folderName' existe déjà." -Color "Orange" -AddNewLine $true
                    $currentRelativePath = $fullRelativePath
                    
                    $overwriteCb = $Controls.OverwritePermissionsCheckBox
                    if ($overwriteCb -and $overwriteCb.IsChecked -eq $true) {
                        Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "  -> L'option d'écrasement est active. Mise à jour forcée." -Color "Blue" -AddNewLine $true
                        $updateActionsAllowed = $true
                    } 
                    elseif ($XmlNode.SelectSingleNode("permissions") -or $XmlNode.SelectSingleNode("tags")) {
                        $message = "Le dossier '$folderName' existe déjà. Mettre à jour ses permissions et métadonnées ?"
                        $choice = Show-MessageBox -Message $message -Title "Conflit Détecté" -ButtonType "YesNoCancel" -IconType "Question"
                        switch ($choice) {
                            "Yes"    { 
                                Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "  -> L'utilisateur a choisi de mettre à jour." -Color "Blue" -AddNewLine $true
                                $updateActionsAllowed = $true
                            }
                            "No"     { 
                                Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "  -> Mise à jour ignorée." -Color "Orange" -AddNewLine $true
                                $updateActionsAllowed = $false
                            }
                            "Cancel" { 
                                throw "Déploiement annulé par l'utilisateur." 
                            }
                        }
                    } else {
                        $updateActionsAllowed = $false
                    }
                } else { 
                    Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "  -> ERREUR : $($_.Exception.Message)" -Color "Red" -AddNewLine $true
                    return 
                }
            }

            if ($updateActionsAllowed) {
                try {
                    $folderObject = Get-PnPFolder -Url $currentRelativePath
                    $ctx = Get-PnPContext
                    $ctx.Load($folderObject.ListItemAllFields)
                    $ctx.ExecuteQuery()
                    $folderItem = $folderObject.ListItemAllFields
                    if (-not $folderItem) { throw "Impossible de trouver l'item dossier '$currentRelativePath'." }

                    foreach ($actionNode in ($XmlNode.ChildNodes | Where-Object { $_.LocalName -ne 'directory' })) {
                        switch ($actionNode.LocalName) {
                            "permissions" {
                                Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "  Application des permissions..." -Color "DarkMagenta" -AddNewLine $true
                                $Counter.Value++; $Controls.DeploymentProgressBar.Value = $Counter.Value; $Window.Dispatcher.Invoke([System.Action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
                                foreach ($userNode in $actionNode.ChildNodes) {
                                    if ($userNode.LocalName -eq "user") {
                                        $email = $userNode.GetAttribute("email"); $level = $userNode.GetAttribute("level")
                                        $permissionMap = @{ "read" = "Read"; "contribute" = "Contribute"; "full" = "Full Control" }; $role = $permissionMap[$level.ToLower()]
                                        if ($email -and $role) {
                                            try { 
                                                Set-PnPListItemPermission -List $LibraryName -Identity $folderItem.Id -User $email -AddRole $role
                                                Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "    -> OK pour '$email' ($role)." -Color "Green" -AddNewLine $true
                                            } catch { Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "    -> ERREUR pour '$email': $($_.Exception.Message)" -Color "Red" -AddNewLine $true }
                                        }
                                    }
                                }
                            }
                            "tags" {
                                Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "  Application des métadonnées..." -Color "DarkGoldenrod" -AddNewLine $true
                                $Counter.Value++; $Controls.DeploymentProgressBar.Value = $Counter.Value; $Window.Dispatcher.Invoke([System.Action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
                                $metadataGrouped = @{}
                                foreach ($tagNode in $actionNode.ChildNodes) {
                                    if ($tagNode.LocalName -eq "tag") {
                                        $tagName = $tagNode.GetAttribute("name"); $tagValue = $tagNode.GetAttribute("value")
                                        if ($tagName -and $tagValue) {
                                            if (-not $metadataGrouped.ContainsKey($tagName)) { $metadataGrouped[$tagName] = [System.Collections.Generic.List[string]]::new() }
                                            $metadataGrouped[$tagName].Add($tagValue)
                                        }
                                    }
                                }
                                $metadataForPnP = @{}; foreach ($key in $metadataGrouped.Keys) { $metadataForPnP[$key] = $metadataGrouped[$key].ToArray() }
                                if ($metadataForPnP.Count -gt 0) {
                                    foreach($key in $metadataForPnP.Keys){ 
                                        $valuesToLog = $metadataForPnP[$key] -join "', '"
                                        Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "    -> Application de ['$valuesToLog'] à la colonne '$key'..." -Color "DarkGoldenrod" -AddNewLine $true
                                    }
                                    Set-PnPListItem -List $LibraryName -Identity $folderItem.Id -Values $metadataForPnP
                                    Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "    -> Métadonnées appliquées avec succès." -Color "Green" -AddNewLine $true
                                }
                            }
                            "link" {
                                Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "  Création du lien..." -Color "DarkOliveGreen" -AddNewLine $true
                                $Counter.Value++; $Controls.DeploymentProgressBar.Value = $Counter.Value; $Window.Dispatcher.Invoke([System.Action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
                                try {
                                    $linkUrl = $actionNode.GetAttribute("destination")
                                    $urlFileContent = "[InternetShortcut]`r`nURL=$linkUrl"
                                    $tempFile = [System.IO.Path]::GetTempFileName() + ".url"
                                    Set-Content -Path $tempFile -Value $urlFileContent -Encoding ASCII
                                    if (-not [string]::IsNullOrEmpty($linkUrl)) {
                                        $linkName = $actionNode.GetAttribute("name")
                                        Add-PnPFile -Path $tempFile -Folder $currentRelativePath -NewFileName ($linkName + ".url")
                                        Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "    -> Lien '$linkName' créé avec succès." -Color "Green" -AddNewLine $true
                                        Remove-Item -Path $tempFile -Force
                                    } else {
                                        Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "    -> ERREUR : URL de lien manquante." -Color "Red" -AddNewLine $true
                                    }
                                } catch { Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "  -> ERREUR création lien: $($_.Exception.Message)" -Color "Red" -AddNewLine $true }
                            }
                        }
                    }
                } catch {
                    Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "  -> ERREUR GLOBALE lors de la récupération de l'item ou de l'application des propriétés: $($_.Exception.Message)" -Color "Red" -IsBold $true -AddNewLine $true
                }
            }
        }
    }

    foreach ($childNode in ($XmlNode.ChildNodes | Where-Object { $_.LocalName -eq 'directory' })) {
        Deploy-XmlNode -XmlNode $childNode -LibraryName $LibraryName -RelativeBasePath $currentRelativePath -Counter $Counter
    }
}

## FONCTION DE GESTION DES PANNEAUX
    # Met à jour le label de prévisualisation du nom du dossier
    function Update-FolderNamePreview {
        $formHolder = $Controls.DynamicFormHolder
        
        $previewLabel = Find-VisualChild -Visual $formHolder -Type ([System.Windows.Controls.Label]) -Name "PreviewLabel"
        if(-not $previewLabel) { return }

        $nameParts = @()
        $inputWrapPanel = Find-VisualChild -Visual $formHolder -Type ([System.Windows.Controls.WrapPanel])
        if(-not $inputWrapPanel) { return }

        foreach ($control in $inputWrapPanel.Children) {
            if ($control -is [System.Windows.Controls.TextBox]) { $nameParts += $control.Text }
            elseif ($control -is [System.Windows.Controls.Label]) { $nameParts += $control.Content }
            elseif ($control -is [System.Windows.Controls.ComboBox]) {
                if ($control.SelectedValue) { $nameParts += $control.SelectedValue }
                else { $nameParts += $control.Text }
            }
        }
        $previewLabel.Content = "Résultat : " + ($nameParts -join '')

        # --- NOUVEL APPEL ---
        # À chaque fois que la preview du nom change, on met à jour la barre de statut.
        Update-StatusTextWithFinalUrl
    }

    function Find-VisualChild {
        param([System.Windows.DependencyObject]$Visual, [System.Type]$Type, [string]$Name)
        for ($i = 0; $i -lt [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($Visual); $i++) {
            $child = [System.Windows.Media.VisualTreeHelper]::GetChild($Visual, $i)
            if ($child -is $Type -and ($child.Name -eq $Name -or [string]::IsNullOrEmpty($Name))) { return $child }
            $found = Find-VisualChild -Visual $child -Type $Type -Name $Name
            if ($found) { return $found }
        }
    }

    # Génère les contrôles du formulaire à partir d'un template
    function Generate-DynamicFormControls {
        param([string]$TemplateName)

        $formHolder = $Controls.DynamicFormHolder
        $formHolder.Children.Clear()

        # === CORRECTION ICI ===
        # On remplace .ContainsKey($TemplateName) par .Keys -contains $TemplateName
        if (-not ($global:FolderNameTemplates.Keys -contains $TemplateName)) { 
            Write-Warning "Le template '$TemplateName' est introuvable dans la configuration."
            return 
        }

        $template = $global:FolderNameTemplates[$TemplateName]
        
        # Conteneur pour les contrôles de saisie (WrapPanel pour un meilleur alignement)
        $inputWrapPanel = New-Object System.Windows.Controls.WrapPanel -Property @{ 
            Orientation = "Horizontal" 
        }
        $formHolder.Children.Add($inputWrapPanel) | Out-Null
        
        # La suite de la fonction est identique
        foreach ($controlDef in $template.Layout) {
            $control = $null
            switch ($controlDef.Type) {
                'TextBox' {
                    $control = New-Object System.Windows.Controls.TextBox -Property @{
                        Name = $controlDef.Name; Text = $controlDef.DefaultValue
                        Style = $Window.FindResource("StandardTextBoxStyle")
                        MinWidth = 80; Margin = "0,0,5,5"; VerticalContentAlignment = "Center"
                    }
                    $control.Add_TextChanged({ 
                        Update-FolderNamePreview 
                        Update-ButtonsState
                    })
                }
                'Label' {
                    $control = New-Object System.Windows.Controls.Label -Property @{
                        Content = $controlDef.Content; VerticalAlignment = "Center"; Margin = "0,0,5,5"
                    }
                }
                'ComboBox' {
                    $control = New-Object System.Windows.Controls.ComboBox -Property @{
                        Name = $controlDef.Name; Style = $Window.FindResource("SharePointComboBoxStyle")
                        MinWidth = 100; Margin = "0,0,5,5"; ItemsSource = $controlDef.Options
                    }
                    if ($controlDef.DisplayMemberPath) { $control.DisplayMemberPath = $controlDef.DisplayMemberPath }
                    if ($controlDef.SelectedValuePath) { $control.SelectedValuePath = $controlDef.SelectedValuePath }
                    $control.SelectedIndex = 0
                    $control.Add_SelectionChanged({ Update-FolderNamePreview })
                }
            }
            if ($control) { $inputWrapPanel.Children.Add($control) | Out-Null }
        }
        
        $previewLabel = New-Object System.Windows.Controls.Label -Property @{ Name = "PreviewLabel"; FontWeight = "Bold"; Margin = "0,10,0,0"; Content = "Résultat : " }
        $formHolder.Children.Add($previewLabel) | Out-Null
        
        $descLabel = New-Object System.Windows.Controls.TextBlock -Property @{ Name = "DescriptionLabel"; FontStyle = "Italic"; Foreground = "Gray"; Margin = "0,5,0,0"; Text = $template.Description; TextWrapping = "Wrap" }
        $formHolder.Children.Add($descLabel) | Out-Null
        
        Update-FolderNamePreview
    }

    # Initialise les panneaux de configuration
    function Setup-ConfigurationPanelEvents {
        # Peuple la ComboBox avec les clés des templates
        $Controls.TemplateComboBox.ItemsSource = $global:FolderNameTemplates.Keys

        # Événement quand on coche/décoche la case "Créer un dossier"
        $Controls.CreateFolderCheckBox.Add_Checked({
            $Controls.TemplateComboBox.IsEnabled = $true
            # Si un template est sélectionné, on le génère
            if($Controls.TemplateComboBox.SelectedItem) { 
                Generate-DynamicFormControls -TemplateName $Controls.TemplateComboBox.SelectedItem 
            }
            Update-StatusTextWithFinalUrl
            Update-ButtonsState
        })
        $Controls.CreateFolderCheckBox.Add_Unchecked({
            $Controls.TemplateComboBox.IsEnabled = $false
            # On vide simplement le conteneur du formulaire dynamique
            $Controls.DynamicFormHolder.Children.Clear()
            Update-StatusTextWithFinalUrl
            Update-ButtonsState
        })
        
        # Événement quand on change la sélection dans la ComboBox des templates
        $Controls.TemplateComboBox.Add_SelectionChanged({
            param($sender, $e)
            # On ne génère le formulaire que si la case est cochée
            if ($Controls.CreateFolderCheckBox.IsChecked -eq $true -and $sender.SelectedItem) {
                Generate-DynamicFormControls -TemplateName $sender.SelectedItem
            }
            Update-ButtonsState
        })

        # Événement pour le bouton d'exportation
        $Controls.ExportConfigButton.Add_Click({
            Export-Configuration
        })

        # Événement pour le bouton de réinitialisation
        $Controls.ResetUIButton.Add_Click({
            # On demande confirmation à l'utilisateur car c'est une action destructive
            $confirm = Show-MessageBox -Message "Voulez-vous vraiment réinitialiser toute l'interface ?" -Title "Confirmer la réinitialisation" -ButtonType "YesNo" -IconType "Warning"
            if ($confirm -eq "Yes") {
                # On force une réinitialisation "manuelle" en ignorant les paramètres de lancement
                Reset-UIForNewDeployment -ForceManualReset
            }
        })
    }

    # Fonction pour l'export de configuration
    function Export-Configuration {
        $commandParts = @(".\SharePoint-Provisioning.ps1")
        
        # Paramètres de base (inchangés)
        if ($Controls.SiteComboBox.SelectedItem) {
            $commandParts += "`n    -DefaultSiteUrl `"$($Controls.SiteComboBox.SelectedItem.Url)`""
        }
        if ($Controls.LibraryComboBox.SelectedItem) {
            $commandParts += "`n    -DefaultLibraryName `"$($Controls.LibraryComboBox.SelectedItem.Title)`""
        }
        if ($script:deploymentTargetUrl) {
            # On utilise la même logique que pour la barre de statut pour avoir l'URL finale
            $finalUrl = $script:deploymentTargetUrl
            if($Controls.CreateFolderCheckBox.IsChecked -eq $true) {
                $previewLabel = Find-VisualChild -Visual ($Controls.DynamicFormHolder) -Type ([System.Windows.Controls.Label]) -Name "PreviewLabel"
                if ($previewLabel) {
                    $newFolderName = $previewLabel.Content.ToString().Replace("Résultat : ", "").Trim()
                    $finalUrl = ($script:deploymentTargetUrl.TrimEnd('/')) + "/" + $newFolderName
                }
            }
            $commandParts += "`n    -DefaultDestinationUrl `"$finalUrl`""
        }
        if ($script:xmlModelPath) {
            $commandParts += "`n    -DefaultXmlPath `"$($script:xmlModelPath)`""
        }
        
        # --- NOUVEAU : Récupération des paramètres optionnels ---

        # 1. Création de dossier
        if ($Controls.CreateFolderCheckBox.IsChecked -eq $true) {
            $commandParts += "`n    -CreateNewFolder"
            if ($Controls.TemplateComboBox.SelectedItem) {
                $commandParts += "`n    -DefaultTemplateName `"$($Controls.TemplateComboBox.SelectedItem)`""
            }
        }

        # 2. Écrasement des permissions
        if ($Controls.OverwritePermissionsCheckBox.IsChecked -eq $true) {
            $commandParts += "`n    -OverwritePermissions"
        }
        # --- FIN NOUVEAU ---
        
        $finalCommand = $commandParts -join " "

        # On appelle maintenant une boîte de dialogue personnalisée
        Show-CopyableMessageBox -Title "Commande d'Exportation" -Prompt "Commande PowerShell pour reproduire cette configuration :" -TextToCopy $finalCommand
    }

    function Update-StatusTextWithFinalUrl {
        # === CORRECTION DÉFINITIVE DE LA GARDE ===
        # Si l'URL de base n'est pas définie (cas après une réinitialisation manuelle),
        # on met à jour la barre de statut avec un message vide et on s'arrête immédiatement.
        if ([string]::IsNullOrWhiteSpace($script:deploymentTargetUrl)) {
            $Controls.StatusTextBox.Text = "Destination prête :"
            $Controls.StatusTextBox.ToolTip = ""
            return # On quitte la fonction pour ne pas exécuter le reste du code sur une variable nulle.
        }
        # =========================================

        $finalDestinationUrl = $script:deploymentTargetUrl
        if ($Controls.CreateFolderCheckBox.IsChecked -eq $true) {
            $previewLabel = Find-VisualChild -Visual ($Controls.DynamicFormHolder) -Type ([System.Windows.Controls.Label]) -Name "PreviewLabel"
            if ($previewLabel) {
                $newFolderName = $previewLabel.Content.ToString().Replace("Résultat : ", "").Trim()
                $finalDestinationUrl = ($script:deploymentTargetUrl.TrimEnd('/')) + "/" + $newFolderName
            }
        }

        # Le reste de la fonction est inchangé...
        $displayText = "Destination prête : $finalDestinationUrl"
        if ($displayText.Length -gt 100) {
            $displayText = "Destination prête : ...$($finalDestinationUrl.Substring($finalDestinationUrl.Length - 80))"
        }
        $Controls.StatusTextBox.Text = $displayText
        $Controls.StatusTextBox.ToolTip = $finalDestinationUrl
    }

## Fonction de réinitialisation de l'interface utilisateur pour un nouveau déploiement
function Reset-UIForNewDeployment {
    param(
        # Nouveau paramètre pour forcer une réinitialisation complète
        [switch]$ForceManualReset
    )

    # Si le reset est forcé, on ignore les paramètres. Sinon, on les utilise.
    $paramsToUse = if ($ForceManualReset) { @{} } else {
        $(if ($script:launchParameters.Count -gt 0) { $script:launchParameters } else { $script:testValues }) ?? @{}
    }

    # On active le verrou pour bloquer les mises à jour automatiques
    $script:isResettlingUI = $true
    
    Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "--- RÉINITIALISATION DE L'INTERFACE ---" -Color "Orange" -IsBold $true -AddTwoLine $true
    
    # On vide les champs qui doivent toujours l'être
    $inputWrapPanel = Find-VisualChild -Visual ($Controls.DynamicFormHolder) -Type ([System.Windows.Controls.WrapPanel])
    if ($inputWrapPanel) {
        $textBoxes = $inputWrapPanel.Children | Where-Object { $_ -is [System.Windows.Controls.TextBox] }
        foreach($tb in $textBoxes) { $tb.Text = "" }
    }
    $script:lastDeploymentPath = $null

    # On réinitialise les sections UNIQUEMENT si elles n'ont pas été fournies en paramètre
    if (-not $paramsToUse.ContainsKey('DefaultDestinationUrl')) {
        if ($script:IsConnected) { $Controls.SiteComboBox.IsEnabled = $true }
        
        # On réinitialise la sélection ET le tag du site.
        $Controls.SiteComboBox.SelectedIndex = -1
        $Controls.SiteComboBox.Tag = $null

        $Controls.LibraryComboBox.ItemsSource = $null
        $Controls.LibraryComboBox.IsEnabled = $false
        $Controls.TargetTreeView.Items.Clear()
        $script:deploymentTargetUrl = $null
        $Controls.CopyUrlButton.IsEnabled = $false
        $Controls.OpenUrlButton.IsEnabled = $false
        Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "Veuillez sélectionner une nouvelle destination." -Color "Blue" -AddNewLine $true
    }
    
    if (-not $paramsToUse.ContainsKey('DefaultXmlPath')) {
        $script:xmlModel = $null; $script:xmlModelPath = $null
        $Controls.SourceXmlTreeView.Items.Clear()
        $Controls.LoadXmlModelButton.IsEnabled = $true
        $Controls.XmlFileNameTextBlock.Text = ""
        $Controls.XmlFileNameTextBlock.ToolTip = ""
        $Controls.LoadXmlModelButton.Visibility = "Visible"
        Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "Veuillez charger un nouveau modèle XML." -Color "Blue" -AddNewLine $true
    }

    if (-not $paramsToUse.ContainsKey('CreateNewFolder')) {
        if ($Controls.CreateFolderCheckBox.IsChecked) { $Controls.CreateFolderCheckBox.IsChecked = $false }
    }
    if (-not $paramsToUse.ContainsKey('DefaultTemplateName')) {
        if ($Controls.TemplateComboBox.SelectedIndex -ne -1) { $Controls.TemplateComboBox.SelectedIndex = -1 }
    }
    if (-not $paramsToUse.ContainsKey('OverwritePermissions')) {
        if ($Controls.OverwritePermissionsCheckBox.IsChecked) { $Controls.OverwritePermissionsCheckBox.IsChecked = $false }
    }
    
    # On retire le verrou
    $script:isResettlingUI = $false

    # On force une mise à jour complète de l'état de l'interface.
    Update-StatusTextWithFinalUrl
    Update-ButtonsState
    $Controls.LogRichTextBox.ScrollToEnd()
}

#fonction de comptage pour la progress bar
function Count-XmlOperations {
    param([System.Xml.XmlNode]$XmlNode)
    $count = 0
    if ($XmlNode.NodeType -ne 'Element') { return 0 }

    # On compte le dossier lui-même
    if($XmlNode.LocalName -eq 'directory'){
        $count = 1
        # On compte les actions directes
        $count += $XmlNode.SelectNodes("permissions|tags|link").Count
    }

    # On ajoute le compte des sous-dossiers
    foreach ($childDir in $XmlNode.SelectNodes("directory")) {
        $count += Count-XmlOperations -XmlNode $childDir
    }
    
    return $count
}

## GESTION DES ÉVÉNEMENTS
$Controls.SiteComboBox.add_SelectionChanged({
    param($sender, $e)
    $selectedSite = $sender.SelectedItem
    if ($null -eq $selectedSite) { return }
    if ($sender.Tag -ne $selectedSite.Url) {
        Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "Site sélectionné : '$($selectedSite.Title)'" -Color "Blue" -AddNewLine $true
        $sender.Tag = $selectedSite.Url
        $Controls.TargetTreeView.Items.Clear()
        $Controls.LibraryComboBox.ItemsSource = $null
        $Controls.StatusTextBox.Text = "Veuillez sélectionner une bibliothèque dans le site '$($selectedSite.Title)'."
        $Controls.DeployButton.IsEnabled = $false
        Populate-LibraryList -SiteUrl $selectedSite.Url
    }
})

$Controls.LibraryComboBox.add_SelectionChanged({
    param($sender, $e)
    $selectedLibrary = $sender.SelectedItem
    if ($null -eq $selectedLibrary) { return }
    Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "Bibliothèque sélectionnée : '$($selectedLibrary.Title)'" -Color "Blue" -IsBold $true -AddNewLine $true
    Populate-TargetTreeView -LibraryTitle $selectedLibrary.Title
})

# Gestionnaire d'événement pour la molette de la souris
$Controls.TargetTreeViewScrollViewer.add_PreviewMouseWheel({
    param($sender, $e)
    
    # Le sender est le ScrollViewer
    # On ajuste sa position verticale en fonction du mouvement de la molette (e.Delta)
    $sender.ScrollToVerticalOffset($sender.VerticalOffset - $e.Delta)
    
    # On indique que l'événement a été traité pour éviter qu'il ne soit propagé ailleurs
    $e.Handled = $true
})

$Controls.TargetTreeView.add_SelectedItemChanged({
    param($sender, $e)
    
    # --- PARTIE 1 : Mise à jour purement visuelle (style) ---
    # On continue d'utiliser $e.OldValue et $e.NewValue pour la mise en forme.
    # Nettoyage du style de l'ancienne sélection
    if ($e.OldValue -is [System.Windows.Controls.TreeViewItem]) {
        $oldHeaderPanel = $e.OldValue.Header -as [System.Windows.Controls.StackPanel]
        if ($oldHeaderPanel -and $oldHeaderPanel.Children.Count -ge 2) {
            $textBlock = $oldHeaderPanel.Children[1] -as [System.Windows.Controls.TextBlock]
            if ($textBlock) {
                $textBlock.FontWeight = "Normal"
                $textBlock.Foreground = [System.Windows.Media.Brushes]::Black
            }
        }
    }
    # Application du style à la nouvelle sélection
    if ($e.NewValue -is [System.Windows.Controls.TreeViewItem]) {
        $newHeaderPanel = $e.NewValue.Header -as [System.Windows.Controls.StackPanel]
        if ($newHeaderPanel -and $newHeaderPanel.Children.Count -ge 2) {
            $textBlock = $newHeaderPanel.Children[1] -as [System.Windows.Controls.TextBlock]
            if ($textBlock) {
                $textBlock.FontWeight = "Bold"
                $textBlock.Foreground = [System.Windows.Media.Brushes]::DodgerBlue
            }
        }
    }

    # --- PARTIE 2 : Logique métier (fiabilisée) ---
    # LA CORRECTION : On ignore $e.NewValue pour la logique et on utilise la source de vérité.
    $selectedItem = $Controls.TargetTreeView.SelectedItem
    
    # On vérifie que la sélection est valide pour une action.
    # Un item est invalide si:
    # - Il est null (rien n'est sélectionné).
    # - Son Tag est null.
    # - Son Tag contient une hashtable avec la clé 'Type' (c'est notre item "Charger plus...").
    if ($null -eq $selectedItem -or $null -eq $selectedItem.Tag -or ($selectedItem.Tag -is [hashtable] -and $selectedItem.Tag.ContainsKey('Type'))) {
        return # C'est normal, on ne fait rien.
    }

    # À ce stade, on est certain que $selectedItem.Tag contient notre objet PnP Folder.
    # Dans votre code, vous avez un Tag qui est directement l'objet PnP, et un autre qui est une hashtable.
    # Adaptons-nous aux deux cas pour une robustesse maximale.
    $pnpFolderObject = if ($selectedItem.Tag -is [hashtable]) { $selectedItem.Tag.PnpFolderObject } else { $selectedItem.Tag }
    
    # On vérifie par sécurité que l'objet dans le Tag est bien du type attendu.
    if (-not ($pnpFolderObject -is [Microsoft.SharePoint.Client.Folder])) { return }

    # On peut maintenant continuer la logique en toute confiance.
    try {
        $relativeUrl = $pnpFolderObject.ServerRelativeUrl
        $contextUri = [uri](Get-PnPContext).Url
        $absoluteUrl = "$($contextUri.Scheme)://$($contextUri.Host)$relativeUrl"

        Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "Nouvelle destination sélectionnée : '$relativeUrl'" -Color "DarkGreen" -AddNewLine $true
        
        $script:deploymentTargetUrl = $absoluteUrl

        # Mise à jour de la barre de statut
        Update-StatusTextWithFinalUrl
        
        $Controls.CopyUrlButton.IsEnabled = $true
        $Controls.OpenUrlButton.IsEnabled = $true
        Update-ButtonsState

    } catch {
        Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "Erreur lors de la mise à jour de la destination : $($_.Exception.Message)" -Color "Red" -AddNewLine $true
    }
})

$Controls.CopyUrlButton.Add_Click({
    if (-not [string]::IsNullOrWhiteSpace($script:deploymentTargetUrl)) {
        Set-Clipboard -Value $script:deploymentTargetUrl
        Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "URL copiée dans le presse-papiers." -Color "Blue" -AddNewLine $true
    }
})

$Controls.OpenUrlButton.Add_Click({
    # S'il y a un chemin de déploiement final, on l'utilise en priorité.
    $urlToOpen = if (-not [string]::IsNullOrWhiteSpace($script:lastDeploymentPath)) {
        $script:lastDeploymentPath
    } else {
        $script:deploymentTargetUrl
    }

    if (-not [string]::IsNullOrWhiteSpace($urlToOpen)) {
        try {
            Start-Process $urlToOpen
            Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "Ouverture de '$urlToOpen' dans le navigateur..." -Color "Blue" -AddNewLine $true
        } catch {
            Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "Erreur lors de l'ouverture de l'URL : $($_.Exception.Message)" -Color "Red" -AddNewLine $true
        }
    }
})

$Controls.LoadXmlModelButton.Add_Click({
    $openFileDialog = New-Object Microsoft.Win32.OpenFileDialog
    $openFileDialog.Filter = "Fichiers XML (*.xml)|*.xml"
    $openFileDialog.Title = "Sélectionner un modèle d'arborescence"
    if ($openFileDialog.ShowDialog() -ne $true) {
        Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "Chargement du modèle annulé." -Color "Orange" -AddNewLine $true
        return
    }
    
    # On appelle simplement notre nouvelle fonction
    Load-XmlModelFromFile -FilePath $openFileDialog.FileName
})

$Controls.SourceXmlTreeViewScrollViewer.add_PreviewMouseWheel({
    param($sender, $e)
    
    # Le sender est le ScrollViewer
    # On ajuste sa position verticale en fonction du mouvement de la molette (e.Delta)
    $sender.ScrollToVerticalOffset($sender.VerticalOffset - $e.Delta)
    
    # On indique que l'événement a été traité pour éviter qu'il ne soit propagé ailleurs
    $e.Handled = $true
})

$Controls.DeployButton.Add_Click({
    Start-Provisioning
})

# ===================================================================
#           DÉMARRAGE DE L'APPLICATION ET CHARGEMENT INITIAL
# ===================================================================

Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "Démarrage..." -ClearContent $true -AddNewLine $true

$script:paramsToUse = $(if ($script:launchParameters.Count -gt 0) { $script:launchParameters } else { $script:testValues }) ?? @{}

Setup-ConfigurationPanelEvents

if (Initialize-PnPConnection) {
    Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "Récupération de la liste des sites disponibles..." -Color "DarkSlateGray" -AddNewLine $true
    $allSites = Get-PnPTenantSite | Sort-Object Title
    $Controls.SiteComboBox.ItemsSource = $allSites
    Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "$($allSites.Count) site(s) trouvé(s)." -Color "Green" -AddNewLine $true

    # --- LOGIQUE DE PRÉ-SÉLECTION HIÉRARCHIQUE ---

    # CAS 1 : Une URL de destination COMPLÈTE est fournie. C'est la plus haute priorité.
    if ($script:paramsToUse.ContainsKey('DefaultDestinationUrl') -and -not [string]::IsNullOrWhiteSpace($script:paramsToUse.DefaultDestinationUrl)) {
        $destinationUrl = $script:paramsToUse.DefaultDestinationUrl
        Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "Destination fournie en paramètre : $destinationUrl" -Color "Purple" -IsBold $true -AddNewLine $true
        
        try {
            $uriObject = [uri]$destinationUrl
            $siteUrlFromParam = "$($uriObject.Scheme)://$($uriObject.Host)$($uriObject.AbsolutePath.Substring(0, $uriObject.AbsolutePath.IndexOf('/', 8)))"
            $siteToSelect = $allSites | Where-Object { $_.Url -eq $siteUrlFromParam } | Select-Object -First 1

            if ($siteToSelect) {
                $Controls.SiteComboBox.SelectedItem = $siteToSelect
                $Controls.SiteComboBox.IsEnabled = $false; $Controls.LibraryComboBox.IsEnabled = $false
                $Controls.TargetTreeView.Visibility = "Collapsed"
                $pathTextBlock = New-Object System.Windows.Controls.TextBlock -Property @{ Text = "Destination (fournie en paramètre) :`n$destinationUrl"; TextWrapping = "Wrap"; FontStyle = "Italic"; Margin = [System.Windows.Thickness]::new(5); VerticalAlignment = "Center" }
                $Controls.TargetTreeViewScrollViewer.Content = $pathTextBlock
                $script:deploymentTargetUrl = $destinationUrl
                Update-StatusTextWithFinalUrl
                $Controls.CopyUrlButton.IsEnabled = $true; $Controls.OpenUrlButton.IsEnabled = $true
            } else {
                Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "AVERTISSEMENT: Impossible de trouver le site '$siteUrlFromParam' correspondant à l'URL fournie." -Color "Orange" -AddNewLine $true
            }
        } catch {
             Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "AVERTISSEMENT: L'URL de destination '$destinationUrl' est invalide. $($_.Exception.Message)" -Color "Orange" -AddNewLine $true
        }
    }
    # CAS 2 : Pas d'URL complète, mais un site (et potentiellement une bibliothèque) sont fournis.
    elseif ($script:paramsToUse.ContainsKey('DefaultSiteUrl') -and -not [string]::IsNullOrWhiteSpace($script:paramsToUse.DefaultSiteUrl)) {
        $siteUrl = $script:paramsToUse.DefaultSiteUrl
        $siteToSelect = $allSites | Where-Object { $_.Url -eq $siteUrl } | Select-Object -First 1
        if ($siteToSelect) { 
            # On sélectionne le site. L'événement SelectionChanged se déclenchera.
            # Populate-LibraryList sera appelé, et il utilisera $script:paramsToUse.DefaultLibraryName s'il existe.
            $Controls.SiteComboBox.SelectedItem = $siteToSelect 
        }
        $Controls.SiteComboBox.IsEnabled = $false
    }
    # CAS 3 : Aucun paramètre de destination, mode 100% manuel.
    else {
        $Controls.SiteComboBox.IsEnabled = $true
    }
}

# --- GESTION DES PARAMÈTRES D'OPTIONS ---
Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "Application des paramètres d'options..." -Color "Gray" -AddNewLine $true

# On ne vérifie que les vrais paramètres de lancement pour la désactivation
# Si des paramètres ont été passés, on est en mode "automatisé".
if ($script:paramsToUse.Count -gt 0) {
    $Controls.ResetUIButton.IsEnabled = $false
}
# =================================================================================

if ($script:paramsToUse.ContainsKey('DefaultXmlPath')) {
    Load-XmlModelFromFile -FilePath $script:paramsToUse.DefaultXmlPath
    $Controls.LoadXmlModelButton.IsEnabled = $false
}

if ($script:paramsToUse.ContainsKey('OverwritePermissions')) {
    $Controls.OverwritePermissionsCheckBox.IsChecked = $script:paramsToUse.OverwritePermissions
    $Controls.OverwritePermissionsCheckBox.IsEnabled = $false
}

if ($script:paramsToUse.ContainsKey('CreateNewFolder')) {
    $Controls.CreateFolderCheckBox.IsChecked = $script:paramsToUse.CreateNewFolder
    $Controls.CreateFolderCheckBox.IsEnabled = $false
}

# La ComboBox doit être gérée après la CheckBox
if ($Controls.CreateFolderCheckBox.IsChecked -eq $true -and $script:paramsToUse.ContainsKey('DefaultTemplateName')) {
    $templateName = $script:paramsToUse.DefaultTemplateName
    if ($Controls.TemplateComboBox.Items.Contains($templateName)) {
        $Controls.TemplateComboBox.SelectedItem = $templateName
        $Controls.TemplateComboBox.IsEnabled = $false
    }
}

# S'abonner à l'événement 'Loaded'...
$Window.Add_Loaded({
    Update-ButtonsState # On s'assure que l'état du bouton est correct au chargement
    $Controls.LogRichTextBox.ScrollToEnd()
    Add-RichText -RichTextBox $Controls.LogRichTextBox -Text "Interface prête." -Color "Gray" -AddNewLine $true
})

# Affiche la fenêtre principale...
$Window.ShowDialog() | Out-Null