# Classe ViewModelBase pour PowerShell Admin ToolBox
# Implémente INotifyPropertyChanged et fournit la base pour tous les ViewModels
# Respecte strictement le pattern MVVM

using namespace System.ComponentModel
using namespace System.Windows.Input

class ViewModelBase : INotifyPropertyChanged {
    # Événement standard INotifyPropertyChanged
    [PropertyChangedEventHandler] $PropertyChanged
    
    # Services injectés (seront définis dans les classes dérivées)
    [object] $LoggingService = $null
    [object] $EventAggregator = $null
    [object] $ConfigurationService = $null
    
    # État du ViewModel
    [bool] $IsInitialized = $false
    [bool] $IsDisposed = $false
    
    # Constructeur par défaut
    ViewModelBase() {
        $this.Initialize()
    }
    
    # Constructeur avec injection de services
    ViewModelBase([object] $loggingService, [object] $eventAggregator, [object] $configurationService) {
        $this.LoggingService = $loggingService
        $this.EventAggregator = $eventAggregator  
        $this.ConfigurationService = $configurationService
        $this.Initialize()
    }
    
    # Initialisation virtuelle (à override dans les classes dérivées)
    [void] Initialize() {
        if ($this.IsInitialized) {
            return
        }
        
        try {
            $this.OnInitializing()
            $this.IsInitialized = $true
            $this.OnInitialized()
            
            if ($this.LoggingService) {
                $this.LoggingService.Debug("ViewModel $($this.GetType().Name) initialisé")
            }
        }
        catch {
            if ($this.LoggingService) {
                $this.LoggingService.Error("Erreur initialisation ViewModel $($this.GetType().Name): $($_.Exception.Message)")
            }
            throw
        }
    }
    
    # Méthodes virtuelles pour le cycle de vie
    [void] OnInitializing() {
        # Override dans les classes dérivées si nécessaire
    }
    
    [void] OnInitialized() {
        # Override dans les classes dérivées si nécessaire
    }
    
    # Implémentation de INotifyPropertyChanged.PropertyChanged
    [void] OnPropertyChanged([string] $propertyName) {
        if ($this.PropertyChanged -and -not [string]::IsNullOrEmpty($propertyName)) {
            try {
                $eventArgs = [PropertyChangedEventArgs]::new($propertyName)
                $this.PropertyChanged.Invoke($this, $eventArgs)
                
                # Log optionnel pour debug
                if ($this.LoggingService -and $this.LoggingService.IsLevelEnabled("Debug")) {
                    $this.LoggingService.Debug("PropertyChanged: $($this.GetType().Name).$propertyName")
                }
            }
            catch {
                if ($this.LoggingService) {
                    $this.LoggingService.Warning("Erreur PropertyChanged pour $propertyName : $($_.Exception.Message)")
                }
            }
        }
    }
    
    # Méthode utilitaire pour setter une propriété avec notification
    [bool] SetProperty([ref] $field, [object] $value, [string] $propertyName) {
        if (-not [object]::Equals($field.Value, $value)) {
            $oldValue = $field.Value
            $field.Value = $value
            
            $this.OnPropertyChanged($propertyName)
            $this.OnPropertyChangedWithValues($propertyName, $oldValue, $value)
            
            return $true
        }
        return $false
    }
    
    # Méthode virtuelle appelée après changement de propriété avec valeurs
    [void] OnPropertyChangedWithValues([string] $propertyName, [object] $oldValue, [object] $newValue) {
        # Override dans les classes dérivées si nécessaire pour logique métier
    }
    
    # Validation des propriétés (extensible)
    [hashtable] ValidateProperty([string] $propertyName, [object] $value) {
        # Retourne @{ IsValid = $true/$false; ErrorMessage = "..." }
        # Override dans les classes dérivées pour validation spécifique
        return @{ IsValid = $true; ErrorMessage = "" }
    }
    
    # Setter avec validation
    [bool] SetPropertyWithValidation([ref] $field, [object] $value, [string] $propertyName) {
        $validationResult = $this.ValidateProperty($propertyName, $value)
        
        if (-not $validationResult.IsValid) {
            if ($this.LoggingService) {
                $this.LoggingService.Warning("Validation échouée pour $propertyName : $($validationResult.ErrorMessage)")
            }
            
            # Notifier l'erreur de validation (peut être capturé par l'UI)
            $this.OnValidationError($propertyName, $validationResult.ErrorMessage)
            return $false
        }
        
        return $this.SetProperty($field, $value, $propertyName)
    }
    
    # Méthode virtuelle pour les erreurs de validation
    [void] OnValidationError([string] $propertyName, [string] $errorMessage) {
        # Override dans les classes dérivées pour gestion des erreurs UI
    }
    
    # Notification de changements multiples
    [void] OnPropertiesChanged([string[]] $propertyNames) {
        foreach ($propertyName in $propertyNames) {
            $this.OnPropertyChanged($propertyName)
        }
    }
    
    # Refresh général (force la notification de toutes les propriétés publiques)
    [void] RefreshAllProperties() {
        try {
            $properties = $this.GetType().GetProperties() | Where-Object { $_.CanRead -and $_.GetGetMethod().IsPublic }
            
            foreach ($property in $properties) {
                if ($property.PropertyType -ne [PropertyChangedEventHandler]) {
                    $this.OnPropertyChanged($property.Name)
                }
            }
            
            if ($this.LoggingService) {
                $this.LoggingService.Debug("RefreshAllProperties appelé sur $($this.GetType().Name)")
            }
        }
        catch {
            if ($this.LoggingService) {
                $this.LoggingService.Error("Erreur RefreshAllProperties: $($_.Exception.Message)")
            }
        }
    }
    
    # Gestion des commandes (helper pour ICommand)
    [ICommand] CreateCommand([scriptblock] $executeAction) {
        return $this.CreateCommand($executeAction, $null)
    }
    
    [ICommand] CreateCommand([scriptblock] $executeAction, [scriptblock] $canExecuteAction) {
        return [RelayCommand]::new($executeAction, $canExecuteAction, $this)
    }
    
    # Helpers pour logging (si service disponible)
    [void] LogDebug([string] $message) {
        if ($this.LoggingService) {
            $this.LoggingService.Debug("[$($this.GetType().Name)] $message")
        }
    }
    
    [void] LogInfo([string] $message) {
        if ($this.LoggingService) {
            $this.LoggingService.Info("[$($this.GetType().Name)] $message")
        }
    }
    
    [void] LogWarning([string] $message) {
        if ($this.LoggingService) {
            $this.LoggingService.Warning("[$($this.GetType().Name)] $message")
        }
    }
    
    [void] LogError([string] $message) {
        if ($this.LoggingService) {
            $this.LoggingService.Error("[$($this.GetType().Name)] $message")
        }
    }
    
    # Helper pour publier des événements (si EventAggregator disponible)
    [void] PublishEvent([string] $eventType, [object] $eventData) {
        if ($this.EventAggregator) {
            try {
                $this.EventAggregator.Publish($eventType, $eventData)
                $this.LogDebug("Événement publié: $eventType")
            }
            catch {
                $this.LogError("Erreur publication événement $eventType : $($_.Exception.Message)")
            }
        }
    }
    
    # Helper pour s'abonner à des événements
    [void] SubscribeToEvent([string] $eventType, [scriptblock] $handler) {
        if ($this.EventAggregator) {
            try {
                $this.EventAggregator.Subscribe($eventType, $handler)
                $this.LogDebug("Abonnement à l'événement: $eventType")
            }
            catch {
                $this.LogError("Erreur abonnement événement $eventType : $($_.Exception.Message)")
            }
        }
    }
    
    # État occupé (binding pour ProgressBar, etc.)
    [bool] $IsBusy = $false
    
    [void] SetBusy([bool] $isBusy) {
        if ($this.SetProperty([ref]$this.IsBusy, $isBusy, "IsBusy")) {
            $this.OnBusyStateChanged($isBusy)
        }
    }
    
    [void] OnBusyStateChanged([bool] $isBusy) {
        # Override dans les classes dérivées si logique spécifique nécessaire
        if ($isBusy) {
            $this.LogDebug("ViewModel occupé")
        } else {
            $this.LogDebug("ViewModel libre")
        }
    }
    
    # Nettoyage des ressources
    [void] Cleanup() {
        if ($this.IsDisposed) {
            return
        }
        
        try {
            $this.OnCleanup()
            
            # Déconnexion des événements
            $this.PropertyChanged = $null
            
            # Nettoyage des services
            $this.LoggingService = $null
            $this.EventAggregator = $null
            $this.ConfigurationService = $null
            
            $this.IsDisposed = $true
            
        }
        catch {
            Write-Warning "Erreur nettoyage ViewModel $($this.GetType().Name): $($_.Exception.Message)"
        }
    }
    
    # Méthode virtuelle pour nettoyage spécifique
    [void] OnCleanup() {
        # Override dans les classes dérivées
    }
    
    # Implémentation IDisposable (optionnelle)
    [void] Dispose() {
        $this.Cleanup()
    }
    
    # Méthodes utilitaires pour binding
    [bool] IsPropertyNull([string] $propertyName) {
        try {
            $property = $this.GetType().GetProperty($propertyName)
            if ($property) {
                $value = $property.GetValue($this)
                return $value -eq $null
            }
        }
        catch {
            $this.LogError("Erreur IsPropertyNull pour $propertyName : $($_.Exception.Message)")
        }
        return $false
    }
    
    [bool] IsPropertyNullOrEmpty([string] $propertyName) {
        try {
            $property = $this.GetType().GetProperty($propertyName)
            if ($property) {
                $value = $property.GetValue($this)
                return [string]::IsNullOrEmpty($value)
            }
        }
        catch {
            $this.LogError("Erreur IsPropertyNullOrEmpty pour $propertyName : $($_.Exception.Message)")
        }
        return $true
    }
    
    # Méthode ToString() override pour debug
    [string] ToString() {
        return "$($this.GetType().Name) (Initialized: $($this.IsInitialized), Busy: $($this.IsBusy))"
    }
}