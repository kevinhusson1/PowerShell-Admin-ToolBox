<#
.SYNOPSIS
    Affiche une fenêtre de sélection de dossier SharePoint (Mini-Browser).
    Utilise PnP PowerShell pour la navigation.

.PARAMETER SiteUrl
    URL du site SharePoint racine.
    
.PARAMETER LibraryName
    Nom de la bibliothèque de documents.

.PARAMETER Window
    Fenêtre parente (pour Owner).

.RETURN VALUE
    [PnP.PowerShell.Commands.Model.SharePoint.Folder] Le dossier sélectionné, ou $null.
#>
function Global:Show-SPFolderPicker {
    param(
        [string]$SiteUrl, 
        [string]$LibraryName,
        [System.Windows.Window]$Window
    )
    
    # Layout Xaml minimal (Updated with LogBox)
    $xaml = @"
<Window xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation'
        xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'
        Title='Sélectionner un dossier ($LibraryName)' Height='600' Width='500' WindowStartupLocation='CenterOwner'>
    <Grid Margin='10'>
        <Grid.RowDefinitions>
            <RowDefinition Height='*'/>
            <RowDefinition Height='100'/>
            <RowDefinition Height='Auto'/>
        </Grid.RowDefinitions>
        
        <!-- TreeView -->
        <TreeView x:Name='FolderTree' Grid.Row='0' BorderBrush='#CCCCCC' BorderThickness='1' Margin='0,0,0,10'/>
        
        <!-- Debug Log -->
        <TextBox x:Name='LogBox' Grid.Row='1' IsReadOnly='True' VerticalScrollBarVisibility='Auto' Margin='0,0,0,10' Background='#F0F0F0' FontFamily='Consolas' FontSize='10'/>

        <!-- Buttons -->
        <StackPanel Grid.Row='2' Orientation='Horizontal' HorizontalAlignment='Right'>
            <Button x:Name='BtnCancel' Content='Annuler' Width='80' Margin='0,0,10,0'/>
            <Button x:Name='BtnSelect' Content='Sélectionner' Width='80'/>
        </StackPanel>
    </Grid>
</Window>
"@
    $win = [System.Windows.Markup.XamlReader]::Parse($xaml)
    if ($Window) { $win.Owner = $Window }
    
    $tree = $win.FindName("FolderTree")
    $logBox = $win.FindName("LogBox")
    $btnOk = $win.FindName("BtnSelect")
    $btnCancel = $win.FindName("BtnCancel")
    
    # Debug Helper inside Picker
    function Log-Picker($Msg) {
        $logBox.AppendText("$(Get-Date -Format 'HH:mm:ss') $Msg`r`n")
        $logBox.ScrollToEnd()
    }

    # FIX SCOPE: Use Hashtable for Mutable State across Closures
    $state = @{ SelectedPath = $null }
    
    $btnCancel.Add_Click({ $win.Close() })
    
    Log-Picker "Démarrage du sélecteur..."
    Log-Picker "Site: $SiteUrl"
    Log-Picker "Lib: $LibraryName"

    # Connect PnP
    $conn = $null
    try {
        # Retrieve Auth from AppConfig (assumes AppConfig is global/available)
        $thumb = $Global:AppConfig.azure.certThumbprint
        $clientId = $Global:AppConfig.azure.authentication.userAuth.appId
        $tenant = $Global:AppConfig.azure.tenantName
        
        Log-Picker "Tentative de connexion PnP..."
        Log-Picker "ClientID: $clientId"
        Log-Picker "Tenant: $tenant"

        $conn = Connect-PnPOnline -Url $SiteUrl -ClientId $clientId -Thumbprint $thumb -Tenant $tenant -ReturnConnection -ErrorAction Stop
        Log-Picker "Connexion PnP réussie !"
    }
    catch {
        Log-Picker "ERREUR CONNEXION: $_"
        return $null # Keep window open? No, logic expects return.
    }

    # Populate Root
    try {
        Log-Picker "Récupération de la racine ($LibraryName)..."
        
        $root = New-Object System.Windows.Controls.TreeViewItem
        $root.Header = $LibraryName
        $root.Tag = "/$LibraryName" # Fallback
        
        # Fetch Lib URL real
        $lib = Get-PnPList -Identity $LibraryName -Connection $conn -Includes RootFolder -ErrorAction Stop | Select-Object -ExpandProperty RootFolder
        if ($lib) {
            Log-Picker "Racine trouvée: $($lib.ServerRelativeUrl)"
            $root.Tag = $lib.ServerRelativeUrl
        }
        else {
            Log-Picker "AVERTISSEMENT: Get-PnPList a retourné null pour la RootFolder."
        }
        
        # Add Dummy for expansion
        $root.Items.Add("Loading...")
        $tree.Items.Add($root)
        
        # Lazy Load
        $expandEvent = {
            param($sender, $e)
            $item = $e.Source
            
            # Prevent multi-trigger bubbles
            if ($item -ne $sender) { return }

            Log-Picker "Expansion de > $($item.Header) ($($item.Tag))"
            
            if ($item.Items.Count -eq 1 -and $item.Items[0] -is [string]) {
                $item.Items.Clear()
                $path = $item.Tag
                try {
                    # STRATEGY CHANGE: Use Get-PnPFolder which handles ServerRelativeUrl correctly
                    # Get-PnPFolderItem was failing because it likely expected a Site-Relative path (no /sites/...)
                    
                    Log-Picker "Lecture via Get-PnPFolder -Url '$path'..."
                    $parentFolder = Get-PnPFolder -Url $path -Includes Folders -Connection $conn -ErrorAction Stop
                    
                    # Manual Filtering (exclude hidden system folders not starting with _)
                    $subs = $parentFolder.Folders | Where-Object { -not $_.Name.StartsWith("_") -and $_.Name -ne "Forms" }
                    
                    Log-Picker "Sous-dossiers trouvés : $(@($subs).Count)"
                    
                    foreach ($sub in $subs) {
                        $node = New-Object System.Windows.Controls.TreeViewItem
                        $node.Header = $sub.Name
                        $node.Tag = $sub.ServerRelativeUrl
                        $node.Items.Add("Loading...") # Dummy
                        $node.Add_Expanded($expandEvent)
                        $item.Items.Add($node)
                    }
                }
                catch { 
                    Log-Picker "ERREUR LECTURE DOSSIER: $_"
                }
            }
        }
        $root.Add_Expanded($expandEvent)
        $root.IsExpanded = $true
    }
    catch { 
        Log-Picker "ERREUR INIT ARBRE: $_"
    }

    $btnOk.Add_Click({ 
            if ($tree.SelectedItem) {
                Log-Picker "Sélection validée : $($tree.SelectedItem.Tag)"
                # FIX: Update hashtable property to ensure persistence across scope
                $state.SelectedPath = $tree.SelectedItem.Tag
                $win.DialogResult = $true # Closes window
            }
            else {
                Log-Picker "Aucune sélection."
            }
        })

    $win.ShowDialog() | Out-Null
    
    if ($state.SelectedPath) {
        # Fetch Full Item Data for Hydration
        try {
            Log-Picker "Récupération métadonnées finales..."
            $folder = Get-PnPFolder -Url $state.SelectedPath -Includes ListItemAllFields -Connection $conn
            return $folder
        }
        catch {
            # Helper Log won't be seen as window closes, but we return null
            return $null
        }
    }
    return $null
}
