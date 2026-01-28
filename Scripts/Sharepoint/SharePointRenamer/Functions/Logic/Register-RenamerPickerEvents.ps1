<#
.SYNOPSIS
    Gère la sélection du dossier cible via un Mini-Browser SharePoint.
#>
function Register-RenamerPickerEvents {
    param(
        [hashtable]$Ctrl,
        [System.Windows.Window]$Window
    )
    
    # Helper: Custom Simple Picker Window
    function Show-SPFolderPicker {
        param($SiteUrl, $LibraryName, $UserAuth)
        
        # Layout Xaml minimal
        $xaml = @"
<Window xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation'
        xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'
        Title='Sélectionner un dossier ($LibraryName)' Height='500' Width='400' WindowStartupLocation='CenterOwner'>
    <Grid Margin='10'>
        <Grid.RowDefinitions>
            <RowDefinition Height='*'/>
            <RowDefinition Height='Auto'/>
        </Grid.RowDefinitions>
        <TreeView x:Name='FolderTree' Grid.Row='0' BorderBrush='#CCCCCC' BorderThickness='1' Margin='0,0,0,10'/>
        <StackPanel Grid.Row='1' Orientation='Horizontal' HorizontalAlignment='Right'>
            <Button x:Name='BtnCancel' Content='Annuler' Width='80' Margin='0,0,10,0'/>
            <Button x:Name='BtnSelect' Content='Sélectionner' Width='80'/>
        </StackPanel>
    </Grid>
</Window>
"@
        $win = [System.Windows.Markup.XamlReader]::Parse($xaml)
        $win.Owner = $Window
        
        $tree = $win.FindName("FolderTree")
        $btnOk = $win.FindName("BtnSelect")
        $btnCancel = $win.FindName("BtnCancel")
        
        $selectedPath = $null
        
        $btnCancel.Add_Click({ $win.Close() })
        
        # Connect PnP
        $conn = $null
        try {
            $thumb = $Global:AppConfig.azure.certThumbprint
            $clientId = $Global:AppConfig.azure.authentication.userAuth.appId
            $tenant = $Global:AppConfig.azure.tenantName
            
            $conn = Connect-PnPOnline -Url $SiteUrl -ClientId $clientId -Thumbprint $thumb -Tenant $tenant -ReturnConnection -ErrorAction Stop
        }
        catch {
            [System.Windows.MessageBox]::Show("Erreur connexion : $_")
            return $null
        }

        # Populate Root
        try {
            $root = New-Object System.Windows.Controls.TreeViewItem
            $root.Header = $LibraryName
            $root.Tag = "/$LibraryName" # Root Path (approx)
            # Fetch Lib URL real
            $lib = Get-PnPList -Identity $LibraryName -Connection $conn -Includes RootFolder | Select-Object -ExpandProperty RootFolder
            $root.Tag = $lib.ServerRelativeUrl
            
            # Add Dummy for expansion
            $root.Items.Add("Loading...")
            $tree.Items.Add($root)
            
            # Lazy Load
            $expandEvent = {
                param($sender, $e)
                $item = $e.Source
                if ($item.Items.Count -eq 1 -and $item.Items[0] -is [string]) {
                    $item.Items.Clear()
                    $path = $item.Tag
                    try {
                        $subs = Get-PnPFolderItem -FolderServerRelativeUrl $path -ItemType Folder -Connection $conn
                        foreach ($sub in $subs) {
                            $node = New-Object System.Windows.Controls.TreeViewItem
                            $node.Header = $sub.Name
                            $node.Tag = $sub.ServerRelativeUrl
                            $node.Items.Add("Loading...") # Dummy
                            $node.Add_Expanded($expandEvent)
                            $item.Items.Add($node)
                        }
                    }
                    catch { [System.Windows.MessageBox]::Show("Erreur lecture : $_") }
                }
            }
            $root.Add_Expanded($expandEvent)
            $root.IsExpanded = $true
        }
        catch { [System.Windows.MessageBox]::Show("Erreur init : $_"); return $null }

        $btnOk.Add_Click({ 
                if ($tree.SelectedItem) {
                    $selectedPath = $tree.SelectedItem.Tag
                    $win.DialogResult = $true # Closes window
                }
            })

        $win.ShowDialog() | Out-Null
        
        if ($selectedPath) {
            # Fetch Full Item Data for Hydration
            $folder = Get-PnPFolder -Url $selectedPath -Includes ListItemAllFields -Connection $conn
            return $folder
        }
        return $null
    }

    $Ctrl.BtnPickFolder.Add_Click({
            $cfg = $Ctrl.ListBox.SelectedItem
            if (-not $cfg) { 
                [System.Windows.MessageBox]::Show("Veuillez d'abord sélectionner un Modèle de configuration.")
                return 
            }
        
            # Launch Picker
            $folder = Show-SPFolderPicker -SiteUrl $cfg.SiteUrl -LibraryName $cfg.LibraryName
        
            if ($folder) {
                # UI Update
                $Ctrl.TargetFolderBox.Text = $folder.Name
                $Ctrl.TargetFolderBox.Tag = $folder # Store Object
            
                # Show Metadata
                $item = $folder.ListItemAllFields
                $metaTxt = "Métadonnées actuelles :`n"
                if ($item) {
                    $item.FieldValues.Keys | Where-Object { $_ -ne "FileLeafRef" -and $_ -ne "FileRef" } | ForEach-Object {
                        $val = $item.FieldValues[$_]
                        if ($val) { $metaTxt += "- $_ : $val`n" }
                    }
                }
                $Ctrl.CurrentMetaText.Text = $metaTxt
            
                # Trigger Form Generation & Hydration
                if ($Global:UpdateRenamerForm) {
                    & $Global:UpdateRenamerForm
                }
            }
        })
}
