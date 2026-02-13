<#
.SYNOPSIS
    Gère la sélection du dossier cible via un Mini-Browser SharePoint.

.DESCRIPTION
    Ce script relie le bouton "Sélectionner..." à la logique de choix de dossier.
    Il effectue :
    1. L'appel à la fonction globale Show-SPFolderPicker (Mini-Browser).
    2. La récupération de l'objet Folder sélectionné.
    3. L'affichage des métadonnées actuelles du dossier (filtrées par whitelist).
    4. Le déclenchement de la mise à jour du formulaire ($Global:UpdateRenamerForm) une fois le dossier choisi.
#>
function Register-RenamerPickerEvents {
    param(
        [hashtable]$Ctrl,
        [System.Windows.Window]$Window
    )
    


    $Ctrl.BtnPickFolder.Add_Click({
            # Try to get control dynamically if stale
            $listBox = $Ctrl.ListBox
            if (-not $listBox) { $listBox = $Window.FindName("ConfigListBox") }
            
            $cfg = $null
            if ($listBox) { $cfg = $listBox.SelectedItem }
            
            if (-not $cfg) { 
                [System.Windows.MessageBox]::Show("Veuillez d'abord sélectionner un Modèle de configuration.")
                return 
            }
        
            # Launch Picker
            # Note: Now calling Global Function defined in Logic/Show-SPFolderPicker.ps1
            $folder = Show-SPFolderPicker -SiteUrl $cfg.SiteUrl -LibraryName $cfg.LibraryName -Window $Window
        
            if ($folder) {
                # UI Update
                if ($Ctrl.TargetFolderBox) { 
                    $Ctrl.TargetFolderBox.Text = $folder.Name
                    $Ctrl.TargetFolderBox.Tag = $folder # Store Object
                }
            
                # Show Metadata
                $item = $folder.ListItemAllFields
                $metaTxt = "Métadonnées actuelles :`n"
                
                try {
                    if ($item -and $item.FieldValues) {
                        $keys = $item.FieldValues.Keys
                        
                        # 1. Calculate Whitelist from Naming Rule
                        $whitelist = @("Title", "FileLeafRef", "FileRef") # Minimal Base
                        
                        if ($cfg.TargetFolder) {
                            $rules = Get-AppNamingRules
                            $targetRule = $rules | Where-Object { $_.RuleId -eq $cfg.TargetFolder } | Select-Object -First 1
                            if ($targetRule) {
                                try {
                                    $layout = ($targetRule.DefinitionJson | ConvertFrom-Json).Layout
                                    foreach ($elem in $layout) {
                                        if ($elem.Name) { $whitelist += $elem.Name }
                                    }
                                }
                                catch {}
                            }
                        }

                        foreach ($k in $keys) {
                            # FILTER: Show Only Whitelisted Fields
                            if ($whitelist -contains $k) {
                                $val = $null
                                try { $val = $item.FieldValues[$k] } catch {}
                                
                                # Label mapping
                                $label = $k
                                if ($k -eq "FileLeafRef") { $label = "Nom du fichier/dossier" }
                                if ($k -eq "Title") { $label = "Titre" }

                                if ($val) { 
                                    # Resolve Lookup Values for display
                                    if ($val -is [Microsoft.SharePoint.Client.FieldLookupValue]) { $val = $val.LookupValue }
                                    elseif ($val -is [Array] -and $val[0] -is [Microsoft.SharePoint.Client.FieldLookupValue]) { 
                                        $val = ($val | ForEach-Object { $_.LookupValue }) -join "; " 
                                    }
                                    
                                    $metaTxt += "- $label : $val`n" 
                                }
                            }
                        }
                    }
                }
                catch {
                    # Silent or Log Warning - Prevent UI Crash from Metadata Access
                    Write-Host "Warning: Metadata access failed - $($_.Exception.Message)" 
                }
                if ($Ctrl.CurrentMetaText) { $Ctrl.CurrentMetaText.Text = $metaTxt }
            
                # Trigger Form Generation & Hydration
                if ($Global:UpdateRenamerForm) {
                    & $Global:UpdateRenamerForm
                }
            }
        }.GetNewClosure())
}
