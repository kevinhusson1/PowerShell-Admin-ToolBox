function Initialize-ListUserUI {
    param(
        [Parameter(Mandatory)][System.Windows.Window]$Window,
        [Parameter(Mandatory)][System.Collections.IList]$AllUsersData
    )

    $script:LUG_CacheData = $AllUsersData # Copie locale au script pour accès dans les events
    
    # 1. MAPPING DES CONTRÔLES (Portée SCRIPT pour persistance dans les events)
    $script:LUG_Controls = @{
        'ComboBoxPoste'       = $Window.FindName('ComboBoxPoste')
        'ComboBoxDepartement' = $Window.FindName('ComboBoxDepartement')
        'TextBoxRecherche'    = $Window.FindName('TextBoxRecherche')
        'ButtonReset'         = $Window.FindName('ButtonResetFilters')
        'DataGrid'            = $Window.FindName('DataGridUsers')
        'ButtonExport'        = $Window.FindName('ButtonExport')
        'LabelStatus'         = $Window.FindName('LabelStatus')
        'NoDataBorder'        = $Window.FindName('NoDataMessageBorder')
        
        # Sidebar Controls
        'Sidebar'             = $Window.FindName('DetailSidebar')
        'DetailGridSplitter'  = $Window.FindName('DetailGridSplitter')
        'SidebarColumn'       = $Window.FindName('SidebarColumn')
        'ButtonCloseSidebar'  = $Window.FindName('CloseSidebarButton')
        'DetailAvatarText'    = $Window.FindName('DetailAvatarText')
        'DetailDisplayName'   = $Window.FindName('DetailDisplayName')
        'DetailJobTitle'      = $Window.FindName('DetailJobTitle')
        'DetailEmail'         = $Window.FindName('DetailEmail')
        'DetailPhoneWork'     = $Window.FindName('DetailPhoneWork')
        'DetailPhoneMobile'   = $Window.FindName('DetailPhoneMobile')
        'DetailObjectId'      = $Window.FindName('DetailObjectId')
        'DetailDepartment'    = $Window.FindName('DetailDepartment')
        'DetailCompany'       = $Window.FindName('DetailCompany')
        'DetailCity'          = $Window.FindName('DetailCity')
        'DetailManager'       = $Window.FindName('DetailManager')
        # Manager field not in XAML yet but good to have prepared
    }

    # 2. LOGIQUE UI COMMUNE
    
    # Helper pour mettre à jour les TextBlocks de détail (ScriptBlock pour éviter les problèmes de Scope dans les Events)
    $script:SetDetailText = {
        param($ControlName, $Value)
        if ($script:LUG_Controls[$ControlName]) {
            $script:LUG_Controls[$ControlName].Text = if ([string]::IsNullOrWhiteSpace($Value)) { "-" } else { $Value }
        }
    }

    $script:FilterLogic = {
        param($Sender)

        try {
            # 1. Récupération sécurisée des valeurs de filtres
            # On force en string pour éviter les objets nuls ou types disparates
            $jobFilter = "$($script:LUG_Controls.ComboBoxPoste.SelectedItem)"
            $deptFilter = "$($script:LUG_Controls.ComboBoxDepartement.SelectedItem)"
            $searchText = "$($script:LUG_Controls.TextBoxRecherche.Text)".Trim()
            
            $allText = Get-AppText 'ui.filters.all'

            # DEBUG LOGS (Pour comprendre pourquoi le filtre échoue)
            Write-Host "FILTER DEBUG | Job: '$jobFilter' | Dept: '$deptFilter' | Search: '$searchText' | ALL: '$allText'" -ForegroundColor Cyan

            # 2. Filtrage
            $filtered = $script:LUG_CacheData | Where-Object {
                $userJob = if ($_.JobTitle) { $_.JobTitle } else { "" }
                $userDept = if ($_.Department) { $_.Department } else { "" }

                # Condition Poste
                $passJob = ($false)
                if ([string]::IsNullOrWhiteSpace($jobFilter) -or $jobFilter -eq $allText) {
                    $passJob = $true
                }
                elseif ($userJob -eq $jobFilter) {
                    $passJob = $true
                }

                # Condition Département
                $passDept = ($false)
                if ([string]::IsNullOrWhiteSpace($deptFilter) -or $deptFilter -eq $allText) {
                    $passDept = $true
                }
                elseif ($userDept -eq $deptFilter) {
                    $passDept = $true
                }

                $passJob -and $passDept
            }

            # 3. Recherche Texte (si applicable)
            if ($searchText.Length -ge 3) {
                $cleanPhoneSearch = $searchText -replace '[^0-9+]', ''
                $filtered = $filtered | Where-Object {
                    $match = $false
                    if ($_.DisplayName -like "*$searchText*") { $match = $true }
                    elseif ($_.Mail -like "*$searchText*") { $match = $true }
                    elseif ($_.JobTitle -like "*$searchText*") { $match = $true }
                    
                    if (-not $match -and $cleanPhoneSearch.Length -gt 0) {
                        $p1 = $_.PrimaryBusinessPhone -replace '[^0-9+]', ''
                        $p2 = $_.MobilePhone -replace '[^0-9+]', ''
                        if ($p1 -like "*$cleanPhoneSearch*" -or $p2 -like "*$cleanPhoneSearch*") { $match = $true }
                    }
                    $match
                }
            }

            # 4. Mise à jour UI
            $view = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
            if ($filtered) { $filtered | ForEach-Object { $view.Add($_) } }
            
            # Utilisation de Dispatcher pour thread-safety UI si appelé depuis un event
            $script:LUG_Controls.DataGrid.Dispatcher.Invoke({
                    $script:LUG_Controls.DataGrid.ItemsSource = $view
                
                    # Update Status
                    $count = $view.Count
                    if ($script:LUG_Controls.LabelStatus) { $script:LUG_Controls.LabelStatus.Text = (Get-AppText 'ui.status.ready') -f $count }
                    if ($script:LUG_Controls.NoDataBorder) { $script:LUG_Controls.NoDataBorder.Visibility = if ($count -eq 0) { 'Visible' } else { 'Collapsed' } }
                })

            # Debug Résultat
            Write-Host "FILTER RESULT | Found: $($view.Count) items" -ForegroundColor Green
        }
        catch {
            Write-Error "Error in FilterLogic: $_"
        }
    }

    if (-not $script:LUG_Controls.DataGrid) {
        Write-Error "[FATAL] DataGrid 'DataGridUsers' not found in Window!"
    }
    else {
        # Write-Host "[INFO] DataGrid found. Attaching SelectionChanged event..." -ForegroundColor Cyan
    }

    # 3. INTERACTION SIDEBAR (User Selection via Click)
    # HACK: On utilise PreviewMouseLeftButtonUp car SelectionChanged est capricieux avec SelectionUnit=Cell
    $script:LUG_Controls.DataGrid.Add_PreviewMouseLeftButtonUp({
            param($s, $e)
        
            # On vérifie si l'élément cliqué fait partie d'une ligne de données
            # DepId: VisualTreeHelper non dispo facilement en PS pur sans cast complexe, 
            # on utilise une astuce : vérifier le DataContext de la source originale
        
            $src = $e.OriginalSource
        
            # Remonter la hiérarchie pour trouver la DataGridRow ou s'assurer qu'on est sur du contenu
            # En PowerShell WPF simple, le plus fiable est souvent de regarder selectedItem EN DEHORS de l'event changed,
            # ou mieux : CurrentItem qui est mis à jour par le clic avant le MouseUp généralement.
        
            # Petit délai pour laisser le temps au moteur WPF de mettre à jour CurrentItem/SelectedItem après le 'MouseDown' interne
            # Start-Sleep -Milliseconds 10 # Bloquant, à éviter
        
            $selectedUser = $script:LUG_Controls.DataGrid.CurrentItem
        
            # Si on clique sur un header, CurrentItem reste l'ancien, attention.
            # Mais si on vient de cliquer, CurrentItem correspond à la cellule active.
        
            # DEBUG (Commenté pour prod)
            # Write-Host ">>> CLICK DETECTED (MouseUp)" -ForegroundColor Magenta
            # Write-Host "    CurrentItem: $(if($selectedUser){$selectedUser.DisplayName}else{'NULL'})" -ForegroundColor DarkGray

            if ($null -ne $selectedUser) {
                # Force la largeur de la colonne Sidebar à une valeur fixe par défaut (ex: 380px)
                # Cela empêche l'auto-resize basé sur le contenu long et active le TextWrapping
                if ($script:LUG_Controls.SidebarColumn) {
                    $script:LUG_Controls.SidebarColumn.Width = New-Object System.Windows.GridLength 380
                }

                # Afficher Sidebar
                if ($script:LUG_Controls.Sidebar) { 
                    $script:LUG_Controls.Sidebar.Visibility = 'Visible'
                }
                # Afficher Splitter
                if ($script:LUG_Controls.DetailGridSplitter) {
                    $script:LUG_Controls.DetailGridSplitter.Visibility = 'Visible'
                }

                # Remplir Avatar (Initiales)
                if ($script:LUG_Controls.DetailAvatarText) {
                    $initials = "??"
                    if ($selectedUser.DisplayName) {
                        $parts = $selectedUser.DisplayName -split ' '
                        if ($parts.Count -ge 2) { $initials = "$($parts[0][0])$($parts[1][0])" }
                        elseif ($parts.Count -eq 1) { $initials = "$($parts[0][0])" }
                    }
                    $script:LUG_Controls.DetailAvatarText.Text = $initials.ToUpper()
                }

                # Remplir Champs avec Invoke (&)
                & $script:SetDetailText 'DetailDisplayName' $selectedUser.DisplayName
                & $script:SetDetailText 'DetailJobTitle'    $selectedUser.JobTitle
                & $script:SetDetailText 'DetailEmail'       $selectedUser.Mail
                & $script:SetDetailText 'DetailPhoneWork'   $selectedUser.PrimaryBusinessPhone
                & $script:SetDetailText 'DetailPhoneMobile' $selectedUser.MobilePhone
                & $script:SetDetailText 'DetailObjectId'    $selectedUser.Id
                & $script:SetDetailText 'DetailDepartment'  $selectedUser.Department
                & $script:SetDetailText 'DetailCompany'     $selectedUser.CompanyName
                & $script:SetDetailText 'DetailCity'        $selectedUser.City
                & $script:SetDetailText 'DetailManager'     $selectedUser.ManagerDisplayName
            }
        })

    # Bouton Fermer Sidebar
    if ($script:LUG_Controls.ButtonCloseSidebar) {
        $script:LUG_Controls.ButtonCloseSidebar.Add_Click({
                # Masquer Sidebar
                if ($script:LUG_Controls.Sidebar) { $script:LUG_Controls.Sidebar.Visibility = 'Collapsed' }
            
                # Masquer Splitter
                if ($script:LUG_Controls.DetailGridSplitter) { $script:LUG_Controls.DetailGridSplitter.Visibility = 'Collapsed' }
            
                # Reset largeur colonne à Auto pour que le DataGrid reprenne la place (sinon GridSplitter a pu figer une largeur)
                if ($script:LUG_Controls.SidebarColumn) {
                    $script:LUG_Controls.SidebarColumn.Width = [System.Windows.GridLength]::Auto
                }

                $script:LUG_Controls.DataGrid.UnselectAll()
            })
    }


    # 4. INITIALISATION
    $jobs = $AllUsersData | Select-Object -ExpandProperty JobTitle -Unique | Sort-Object
    $depts = $AllUsersData | Select-Object -ExpandProperty Department -Unique | Sort-Object

    $script:LUG_Controls.ComboBoxPoste.ItemsSource = @((Get-AppText 'ui.filters.all')) + $jobs
    $script:LUG_Controls.ComboBoxDepartement.ItemsSource = @((Get-AppText 'ui.filters.all')) + $depts
    
    $script:LUG_Controls.ComboBoxPoste.SelectedIndex = 0
    $script:LUG_Controls.ComboBoxDepartement.SelectedIndex = 0
    $script:LUG_Controls.DataGrid.ItemsSource = $AllUsersData
    if ($script:LUG_Controls.LabelStatus) { $script:LUG_Controls.LabelStatus.Text = (Get-AppText 'ui.status.ready') -f $AllUsersData.Count }

    # Events Filtres
    $script:LUG_Controls.ComboBoxPoste.Add_SelectionChanged({ & $script:FilterLogic })
    $script:LUG_Controls.ComboBoxDepartement.Add_SelectionChanged({ & $script:FilterLogic })
    $script:LUG_Controls.TextBoxRecherche.Add_TextChanged({ & $script:FilterLogic })
    
    $script:LUG_Controls.ButtonReset.Add_Click({
            $script:LUG_Controls.TextBoxRecherche.Text = ""
            $script:LUG_Controls.ComboBoxPoste.SelectedIndex = 0
            $script:LUG_Controls.ComboBoxDepartement.SelectedIndex = 0
            & $script:FilterLogic
        })

    $script:LUG_Controls.ButtonExport.Add_Click({
            Export-UserDirectoryData -DataGrid $script:LUG_Controls.DataGrid -OwnerWindow $Window
        })
}
