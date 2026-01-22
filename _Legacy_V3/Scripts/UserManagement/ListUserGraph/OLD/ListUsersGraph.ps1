# ListUsersGraph.ps1
# Script PowerShell pour la récupération des utilisateurs via Microsoft Graph sous forme de tableau
# Version: 1.2 (Intégration des améliorations UI)
# Auteur: Kevin HUSSON

Import-Module -Name Microsoft.Graph.Authentication -force

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

# --- Fonctions Utilitaires (placées en premier pour être disponibles) ---
Get-Function -FunctionName "Show-ExportDialog" -FunctionsPath $global:functionsPath -ErrorAction Stop
Get-Function -FunctionName "Show-UserDetailsDialog" -FunctionsPath $global:functionsPath -ErrorAction Stop
function Format-PhoneNumberForDisplay {
    param([string]$phone)
    if ([string]::IsNullOrWhiteSpace($phone)) { return "" }

    $originalPhoneForDebug = $phone # Garder une trace pour le débogage si besoin
    $cleanedPhone = $phone -replace '[^\d+]', '' # Nettoyage initial : garde chiffres et '+'
    
    # Si un '+' existe ailleurs qu'au début, on le supprime pour éviter les formats incorrects
    if ($cleanedPhone.IndexOf('+') -gt 0) { 
        $cleanedPhone = $cleanedPhone -replace '[+]', '' 
    }

    if ($cleanedPhone.StartsWith("+33") -and $cleanedPhone.Length -eq 12) { # Format international français +33X XX XX XX XX
        $numPart = $cleanedPhone.Substring(3)
        return "+33 $($numPart[0]) $($numPart.Substring(1,2)) $($numPart.Substring(3,2)) $($numPart.Substring(5,2)) $($numPart.Substring(7,2))"
    } elseif ($cleanedPhone.StartsWith("0") -and $cleanedPhone.Length -eq 10) { # Format national français 0X.XX.XX.XX.XX
        return "$($cleanedPhone.Substring(0,2)).$($cleanedPhone.Substring(2,2)).$($cleanedPhone.Substring(4,2)).$($cleanedPhone.Substring(6,2)).$($cleanedPhone.Substring(8,2))"
    }
    
    return $originalPhoneForDebug # Retourne l'original si aucun formatage n'a pu être appliqué
}

# --- Initialisation et Logique UI ---
function Initialize-UI {
    Write-Verbose "Chargement du fichier XAML UI_ListUsersGraph.xaml..."
    $xamlPath = Join-Path -Path $global:stylePath -ChildPath "UI_ListUsersGraph.xaml"
    $script:UI_ListUsersGraph = $null 
    try {
        $script:UI_ListUsersGraph = Load-File -Path $xamlPath -ErrorAction Stop
        if (-not $script:UI_ListUsersGraph) { throw "Load-File a retourné null pour $xamlPath" }
        Write-Verbose "Fichier XAML UI_ListUsersGraph chargé avec succès."
    } catch {
        Write-Error "ERREUR CRITIQUE: Chargement XAML '$xamlPath' échoué. $($_.Exception.Message)"
        [System.Windows.MessageBox]::Show("Erreur critique: Interface utilisateur non chargée.`n$($_.Exception.Message)", "Erreur UI", "OK", "Stop")
        Exit
    }

    # Définir l'icône (chemin vers un fichier .ico)
    $iconPath = $global:icoPath + "\contacts-book.ico"
    $UI_ListUsersGraph.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create((New-Object System.Uri($iconPath, [System.UriKind]::Absolute)))


    try {
        if ($global:stylesXAML) { 
            $script:UI_ListUsersGraph.Resources.MergedDictionaries.Add($global:stylesXAML)
            Write-Verbose "Styles globaux appliqués à UI_ListUsersGraph."
        } else { Write-Warning "AVERTISSEMENT: Styles XAML globaux (`$global:stylesXAML`) non trouvés." }
    } catch { Write-Error "ERREUR: Application des styles globaux échouée: $($_.Exception.Message)" }

    $script:Controls = @{
        DataGridUsers       = $script:UI_ListUsersGraph.FindName("DataGridUsers")
        ComboBoxPoste       = $script:UI_ListUsersGraph.FindName("ComboBoxPoste")
        ComboBoxDepartement = $script:UI_ListUsersGraph.FindName("ComboBoxDepartement")
        TextBoxRecherche    = $script:UI_ListUsersGraph.FindName("TextBoxRecherche")
        ButtonResetFilters  = $script:UI_ListUsersGraph.FindName("ButtonResetFilters")
        LabelStatus         = $script:UI_ListUsersGraph.FindName("LabelStatus")
        ButtonExport        = $script:UI_ListUsersGraph.FindName("ButtonExport")
        # LogoImage           = $script:UI_ListUsersGraph.FindName("LogoImage") # Si vous ajoutez x:Name="LogoImage" à l'Image
    }
    $missingControls = $script:Controls.Keys | Where-Object { -not $script:Controls[$_] }
    if ($missingControls) {
        Write-Error "ERREUR CRITIQUE: Contrôles XAML manquants: $($missingControls -join ', ')"
        [System.Windows.MessageBox]::Show("Erreur UI: Certains contrôles n'ont pas pu être trouvés dans le XAML.", "Erreur UI", "OK", "Stop"); Exit
    }

    # Ajustement de la hauteur des ComboBox pour correspondre au bouton ResetFilters
    # La hauteur du bouton est définie à 32 dans le XAML.
    $script:Controls.ComboBoxPoste.Height = 32
    $script:Controls.ComboBoxDepartement.Height = 32
    
    # Optionnel: Définir la source de l'image du logo dynamiquement si besoin
    # if ($script:Controls.LogoImage) {
    #     $logoPath = Join-Path $global:imgPath "votre_icone_annuaire.png" # Adaptez le nom
    #     if (Test-Path $logoPath) {
    #         $script:Controls.LogoImage.Source = [System.Windows.Media.Imaging.BitmapImage]::new([uri]$logoPath)
    #     }
    # }

    Populate-FilterComboBoxes
    $script:Controls.DataGridUsers.ItemsSource = $script:AllUsersData 
    Update-StatusLabel

    $script:Filters_Changed = { Apply-Filters }
    $script:TextBoxRecherche_TextChanged = {
        param($sender, $e) # $sender est le TextBoxRecherche
        Write-Verbose "DEBUG: TextChanged event triggered. Sender Text: $($sender.Text)"
        Apply-Filters -TriggeringControl $sender # Passer le contrôle déclencheur
    }
    $script:ButtonResetFilters_Click = { Reset-Filters }
    $script:RoutedButtonInfo_Click = {
        param($sender, $e) 
        if ($e.OriginalSource -is [System.Windows.Controls.Button] -and $e.OriginalSource.Name -eq "ButtonInfo") {
            $buttonClicked = $e.OriginalSource
            $clickedUser = $buttonClicked.Tag
            if ($clickedUser) { Show-UserDetails -User $clickedUser }
        }
    }
    $script:ButtonExport_Click = { Export-Data }

    $script:Controls.ComboBoxPoste.Add_SelectionChanged($script:Filters_Changed)
    $script:Controls.ComboBoxDepartement.Add_SelectionChanged($script:Filters_Changed)
    $script:Controls.TextBoxRecherche.Add_TextChanged($script:TextBoxRecherche_TextChanged)
    $script:Controls.ButtonResetFilters.Add_Click($script:ButtonResetFilters_Click)
    $eventHandler = [System.Windows.RoutedEventHandler]$script:RoutedButtonInfo_Click
    $script:Controls.DataGridUsers.AddHandler([System.Windows.Controls.Button]::ClickEvent, $eventHandler)
    $script:Controls.ButtonExport.Add_Click($script:ButtonExport_Click)
    
    Write-Verbose "INFO: Interface utilisateur initialisée et gestionnaires d'événements attachés."
}

function Connect-ToGraph {
    try {
        $mgContext = Get-MgContext -ErrorAction SilentlyContinue
        if (-not $mgContext) {
            Write-Verbose "Tentative de connexion à Microsoft Graph..."
            Connect-MgGraph -ClientID $global:ClientID -TenantId $global:TenantID -Certificate $global:cert -NoWelcome
            Write-Verbose "INFO: Connexion à Microsoft Graph établie."
        } else {
            Write-Verbose "INFO: Déjà connecté à Microsoft Graph en tant que $($mgContext.Account)."
        }
        return $true
    } catch {
        Write-Error "ERREUR: Échec de la connexion à Microsoft Graph : $($_.Exception.Message)"
        return $false
    }
}

function Get-GraphUsersData {
    param(
        [string]$CompanyNameForFilter = $global:societe 
    )
    Write-Verbose "INFO: Début de la récupération des données utilisateur."
    $userProperties = @(
        "id", "displayName", "givenName", "surname", "userPrincipalName", "userType",
        "mail", "businessPhones", "mobilePhone", "jobTitle", "department", "companyName",
        "employeeId", "streetAddress", "city", "state", "postalCode", "country", "accountEnabled"
    )
    $expandProperties = "manager(`$select=id,displayName,userPrincipalName)"
    $graphApiFilter = "accountEnabled eq true"
    Write-Verbose "Récupération des utilisateurs depuis Graph avec le filtre serveur : $graphApiFilter"
    try {
        $usersFromGraph = Get-MgUser -Filter $graphApiFilter -All -Property $userProperties -ExpandProperty $expandProperties -ConsistencyLevel eventual -CountVariable totalUsersBeforeClientFilter -ErrorAction Stop
    } catch {
        Write-Error "ERREUR: Impossible de récupérer les utilisateurs depuis Graph. $($_.Exception.Message)"
        return $null
    }
    Write-Verbose "INFO: Nombre total d'utilisateurs récupérés de Graph avant filtre client : $totalUsersBeforeClientFilter"

    $allUsersFiltered = $usersFromGraph | Where-Object {
        ($_.mail -ne $null) -and
        ($_.JobTitle -ne $null) -and # Garder ce filtre pour avoir des postes dans la ComboBox
        ($_.CompanyName -eq $CompanyNameForFilter)
    }
    $finalUserCount = $allUsersFiltered.Count
    Write-Verbose "INFO: Nombre total d'utilisateurs après TOUS les filtres client : $finalUserCount"

    if ($finalUserCount -eq 0) {
        Write-Warning "AVERTISSEMENT: Aucun utilisateur ne correspond à tous les critères de filtre."
        return [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    }

    $transformedUsers = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    foreach ($user in $allUsersFiltered) {
        $userObject = [PSCustomObject]@{
            Id                   = $user.Id
            DisplayName          = $user.DisplayName
            GivenName            = $user.GivenName
            Surname              = $user.Surname
            UserPrincipalName    = if ($user.UserPrincipalName) { $user.UserPrincipalName.ToLower() } else { $null }
            UserType             = $user.UserType
            Mail                 = if ($user.Mail) { $user.Mail.ToLower() } else { $null }
            PrimaryBusinessPhone = if ($user.BusinessPhones -and $user.BusinessPhones.Count -gt 0) { Format-PhoneNumberForDisplay $user.BusinessPhones[0] } else { "" } # Appeler le formateur
            MobilePhone          = Format-PhoneNumberForDisplay $user.MobilePhone # Appeler le formateur
            JobTitle             = $user.JobTitle
            Department           = $user.Department 
            CompanyName          = $user.CompanyName
            EmployeeId           = $user.EmployeeId
            StreetAddress        = $user.StreetAddress
            City                 = $user.City
            State                = $user.State 
            PostalCode           = $user.PostalCode
            Country              = $user.Country
            ManagerDisplayName   = if ($user.Manager) { $user.Manager.AdditionalProperties.displayName } else { $null }
            ManagerId            = if ($user.Manager) { $user.Manager.Id } else { $null }
            ManagerUserPrincipalName = if ($user.Manager -and $user.Manager.AdditionalProperties.userPrincipalName) { $user.Manager.AdditionalProperties.userPrincipalName.ToLower() } else { $null }
        }
        $transformedUsers.Add($userObject)
    }
    Write-Verbose "INFO: Transformation des données utilisateur terminée."
    return $transformedUsers
}

function Validate-UserData {
    param([System.Collections.ObjectModel.ObservableCollection[object]]$UsersData)
    if (-not $UsersData -or $UsersData.Count -eq 0) {
        Write-Warning "VALIDATION: Aucune donnée utilisateur à valider."; return
    }
    # ... (Validation inchangée pour l'instant, mais peut être commentée pour accélerer les tests UI) ...
}

function Populate-FilterComboBoxes {
    Write-Verbose "Peuplement des ComboBox de filtres..."
    # Poste : Utiliser OriginalAllUsersData pour que les listes de filtres soient complètes
    $distinctJobTitles = $script:OriginalAllUsersData | 
                         Where-Object {$_.JobTitle} | 
                         Select-Object -ExpandProperty JobTitle | 
                         Sort-Object -Unique # Sort-Object -Unique gère déjà la distinction de casse correctement pour des chaînes différentes
    $script:Controls.ComboBoxPoste.ItemsSource = ,"Tous" + $distinctJobTitles
    $script:Controls.ComboBoxPoste.SelectedIndex = 0

    # Département
    $distinctDepartments = $script:OriginalAllUsersData | 
                           Where-Object {$_.Department} | 
                           Select-Object -ExpandProperty Department -Unique | 
                           Sort-Object
    $script:Controls.ComboBoxDepartement.ItemsSource = ,"Tous" + $distinctDepartments
    $script:Controls.ComboBoxDepartement.SelectedIndex = 0
    Write-Verbose "ComboBox de filtres peuplées."
}

function Update-StatusLabel {
    $currentView = $script:Controls.DataGridUsers.ItemsSource
    $count = 0
    if ($currentView -is [System.Collections.IEnumerable] -and $currentView -ne $null) {
        if ($currentView -is [System.Collections.ICollection]) { $count = $currentView.Count } 
        else { $count = ($currentView | Measure-Object).Count }
    }
    $script:Controls.LabelStatus.Text = "$count utilisateur(s) affiché(s)" # .Text
}

function Apply-Filters {
    param($TriggeringControl) 

    Write-Verbose "Début Apply-Filters"
    
    $selectedJobTitle = $script:Controls.ComboBoxPoste.SelectedItem
    $selectedDepartment = $script:Controls.ComboBoxDepartement.SelectedItem
    
    $searchText = ""
    if ($TriggeringControl -and $TriggeringControl.Name -eq "TextBoxRecherche") {
        $searchText = $TriggeringControl.Text.Trim()
    } elseif ($script:Controls.TextBoxRecherche) { 
        $searchText = $script:Controls.TextBoxRecherche.Text.Trim()
    }
    Write-Verbose "DEBUG (Apply-Filters Values): ComboBoxPoste='$selectedJobTitle', ComboBoxDepartement='$selectedDepartment', SearchText='$searchText'"

    $filteredData = $script:OriginalAllUsersData 
    Write-Verbose "DEBUG (Apply-Filters): Initial count for filteredData: $($filteredData.Count)"

    if ($selectedJobTitle -ne "Tous" -and $selectedJobTitle -ne $null) {
        $filteredData = $filteredData | Where-Object { $_.JobTitle -eq $selectedJobTitle }
        Write-Verbose "DEBUG (Apply-Filters): Count after JobTitle filter: $($filteredData.Count)"
    }

    if ($selectedDepartment -ne "Tous" -and $selectedDepartment -ne $null) {
        $filteredData = $filteredData | Where-Object { $_.Department -eq $selectedDepartment }
        Write-Verbose "DEBUG (Apply-Filters): Count after Department filter: $($filteredData.Count)"
    }

    Write-Verbose "DEBUG: Avant bloc SearchText. Length de '$searchText' est $($searchText.Length)"
    if ($searchText.Length -ge 3) {
        # Préparer la version nettoyée de searchText pour les numéros UNE SEULE FOIS
        $cleanedSearchTextForPhones = $searchText -replace '[^0-9+]', ''
        Write-Verbose "DEBUG: Cleaned SearchText for phones: '$cleanedSearchTextForPhones'"

        $filteredData = $filteredData | Where-Object {
            $match = $false # Indicateur de correspondance pour cet utilisateur
            if ($_.DisplayName -like "*$searchText*") { $match = $true }
            if (-not $match -and $_.Mail -like "*$searchText*") { $match = $true }
            if (-not $match -and $_.JobTitle -like "*$searchText*") { $match = $true }
            if (-not $match -and $_.Department -like "*$searchText*") { $match = $true }
            
            # Condition pour les téléphones seulement si cleanedSearchTextForPhones n'est pas vide
            if (-not $match -and -not [string]::IsNullOrEmpty($cleanedSearchTextForPhones)) {
                if (($_.PrimaryBusinessPhone -replace '[^0-9+]', '') -like "*$cleanedSearchTextForPhones*") { $match = $true }
                if (-not $match -and ($_.MobilePhone -replace '[^0-9+]', '') -like "*$cleanedSearchTextForPhones*") { $match = $true }
            }
            $match # Retourne $true si une correspondance a été trouvée
        }
        Write-Verbose "DEBUG (Apply-Filters): Count after SearchText filter ('$searchText'): $($filteredData.Count)"
    } else {
        Write-Verbose "DEBUG: HORS bloc SearchText. Longueur de '$searchText' est $($searchText.Length) - Filtre texte non appliqué."
    }
    
    $displayCollection = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    if ($null -ne $filteredData) {
        $filteredData | ForEach-Object { $displayCollection.Add($_) }
    }
    
    Write-Verbose "DEBUG: Premier élément de displayCollection AVANT assignation DataGrid:"
    if ($displayCollection.Count -gt 0) {
        $displayCollection[0] | Format-List DisplayName, Mail, JobTitle, Department, PrimaryBusinessPhone, MobilePhone
    } else {
        Write-Verbose "DEBUG: displayCollection est vide."
    }

    $script:Controls.DataGridUsers.ItemsSource = $displayCollection
    Write-Verbose "DEBUG (Apply-Filters): New displayCollection created with $($displayCollection.Count) items and assigned to DataGrid."
    
    Update-StatusLabel
    Write-Verbose "Fin Apply-Filters. DataGrid ItemsSource count: $($script:Controls.DataGridUsers.ItemsSource.Count)"
}

function Reset-Filters {
    Write-Verbose "Réinitialisation des filtres..."
    $script:Controls.ComboBoxPoste.SelectedIndex = 0
    $script:Controls.ComboBoxDepartement.SelectedIndex = 0
    $script:Controls.TextBoxRecherche.Text = ""
    Apply-Filters 
    Write-Verbose "Filtres réinitialisés."
}

function Show-UserDetails {
    param($User) # $User est l'objet PSCustomObject de notre DataGrid

    if (-not $User -or -not $User.Id) {
        Write-Warning "Données utilisateur ou ID utilisateur manquant pour afficher les détails."
        return
    }
    # Appeler la fonction externe en passant l'ID et la fenêtre principale comme propriétaire
    Show-UserDetailsDialog -UserId $User.Id -OwnerWindow $script:UI_ListUsersGraph
}

function Export-Data {
    Write-Verbose "Début de l'exportation des données..."
    $ownerMsgBox = if ($script:UI_ListUsersGraph -and $script:UI_ListUsersGraph.IsLoaded) { $script:UI_ListUsersGraph } else { $null }

    if (-not $script:Controls.DataGridUsers.ItemsSource -or $script:Controls.DataGridUsers.ItemsSource.Count -eq 0) {
        [System.Windows.MessageBox]::Show($ownerMsgBox, "Aucune donnée à exporter dans la vue actuelle.", "Exportation", "OK", "Information")
        return
    }

    $dataToExport = [System.Collections.Generic.List[object]]::new($script:Controls.DataGridUsers.ItemsSource)
    Write-Verbose "INFO: Nombre d'éléments à exporter: $($dataToExport.Count)"

    $allAvailableFields = $null
    if ($script:OriginalAllUsersData -and $script:OriginalAllUsersData.Count -gt 0) {
        $allAvailableFields = $script:OriginalAllUsersData[0].PSObject.Properties | ForEach-Object { $_.Name } | Sort-Object
    } else {
        [System.Windows.MessageBox]::Show($ownerMsgBox, "Impossible de déterminer les champs disponibles.", "Erreur Export", "OK", "Error"); return
    }
    
    $defaultFieldsForExport = @("DisplayName", "Mail", "JobTitle", "Department", "PrimaryBusinessPhone", "MobilePhone")
    $validDefaultFields = $defaultFieldsForExport | Where-Object { $allAvailableFields -contains $_ }

    $userExportOptions = Show-ExportOptionsDialog -AllAvailableFields $allAvailableFields `
                                                 -DefaultSelectedFields $validDefaultFields
    
    if (-not $userExportOptions -or [string]::IsNullOrWhiteSpace($userExportOptions.FilePath)) { # Vérifier aussi FilePath
        Write-Verbose "Exportation annulée (fenêtre d'options ou choix du fichier annulé)."
        return
    }
    
    # Le FilePath est maintenant DÉJÀ DANS $userExportOptions
    $filePathToSave = $userExportOptions.FilePath 
    Write-Verbose "INFO: Exportation vers $filePathToSave au format $($userExportOptions.Format)"

    $selectedDataToExport = $dataToExport | Select-Object -Property $userExportOptions.SelectedFields
    
    try {
        if ($userExportOptions.Format -eq "CSV") {
            $selectedDataToExport | Export-Csv -Path $filePathToSave -NoTypeInformation -Encoding UTF8 -Delimiter ";"
            $msg = "Données exportées avec succès en CSV !"
        } elseif ($userExportOptions.Format -eq "HTML") {
            $htmlHeader = "<!DOCTYPE html><html><head><meta charset='UTF-8'><title>Export Utilisateurs</title><style>body{font-family: Segoe UI, Arial, sans-serif;} table, th, td {border: 1px solid #ccc; border-collapse: collapse; padding: 8px; text-align: left;} th {background-color: #f2f2f2; color: #333;} tr:nth-child(even) {background-color: #f9f9f9;}</style></head><body>"
            $htmlFooter = "</body></html>"
            $htmlTable = $selectedDataToExport | ConvertTo-Html -As Table -Fragment
            $htmlContent = $htmlHeader + "<h1>Liste des Utilisateurs (Export du $(Get-Date))</h1>" + $htmlTable + $htmlFooter
            Set-Content -Path $filePathToSave -Value $htmlContent -Encoding UTF8
            $msg = "Données exportées avec succès en HTML !"
        }
        [System.Windows.MessageBox]::Show($ownerMsgBox, $msg, "Exportation Réussie", "OK", "Information")
    } catch {
        Write-Error "ERREUR lors de l'écriture du fichier d'export : $($_.Exception.Message)"
        [System.Windows.MessageBox]::Show($ownerMsgBox, "Erreur lors de l'écriture du fichier d'export:`n$($_.Exception.Message)", "Erreur Export", "OK", "Error")
    }
}


# --- Script Principal ---
if (-not (Connect-ToGraph)) {
    Write-Error "Impossible de continuer sans connexion à Graph."
} else {
    $script:OriginalAllUsersData = Get-GraphUsersData -CompanyNameForFilter $global:societe
    # Validate-UserData -UsersData $script:OriginalAllUsersData # Peut être commenté pour accélerer

    if ($script:OriginalAllUsersData -and $script:OriginalAllUsersData.Count -gt 0) {
        $script:AllUsersData = [System.Collections.ObjectModel.ObservableCollection[object]]::new($script:OriginalAllUsersData)
        Initialize-UI 
        $script:UI_ListUsersGraph.ShowDialog() | Out-Null
    } else {
        Write-Warning "Aucune donnée utilisateur à afficher. L'interface ne sera pas lancée."
        if ($script:UI_ListUsersGraph) { # Si l'UI a eu le temps de se charger
            [System.Windows.MessageBox]::Show("Aucun utilisateur trouvé correspondant aux critères initiaux. L'application va se fermer.", "Données Manquantes", "OK", "Warning")
        } else { # Si l'UI n'a pas pu se charger (e.g. erreur XAML avant)
            Write-Host "Aucun utilisateur trouvé correspondant aux critères initiaux. L'application va se fermer."
        }
    }
}
Write-Verbose "Script ListUsersGraph.ps1 terminé."