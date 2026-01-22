# Modules/LauncherUI/Functions/Update-ManagementScriptList.ps1

function Update-ManagementScriptList {
    if (-not $Global:IsAppAdmin) { return }
    
    # 1. Liste des Scripts (Gauche - Bas)
    $Global:AppControls.ManageScriptsListBox.Dispatcher.Invoke([Action]{
        $Global:AppControls.ManageScriptsListBox.ItemsSource = $null
        $Global:AppControls.ManageScriptsListBox.ItemsSource = $Global:AppAvailableScripts
    })

    # 2. Liste des Groupes Connus (Bibliothèque - Haut)
    $knownGroups = Get-AppKnownGroups
    
    # SÉCURISATION : On vérifie que le contrôle a bien été trouvé avant d'y toucher
    if ($Global:AppControls.ContainsKey('LibraryGroupsComboBox') -and $null -ne $Global:AppControls.LibraryGroupsComboBox) {
        
        $Global:AppControls.LibraryGroupsComboBox.Dispatcher.Invoke([Action]{
            $Global:AppControls.LibraryGroupsComboBox.ItemsSource = $null
            $Global:AppControls.LibraryGroupsComboBox.ItemsSource = @($knownGroups)
            $Global:AppControls.LibraryGroupsComboBox.SelectedIndex = -1
        })
        
    } else {
        Write-Warning "Le contrôle 'LibraryGroupsComboBox' est introuvable dans `$Global:AppControls. Vérifiez Launcher.ps1."
    }
}