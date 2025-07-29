# Classe RelayCommand pour PowerShell Admin ToolBox
# Implémentation de ICommand pour le pattern MVVM
# Permet de binder des scriptblocks aux commandes WPF

using namespace System.Windows.Input

class RelayCommand : ICommand {
    # Actions définies par l'utilisateur
    [scriptblock] $ExecuteAction
    [scriptblock] $CanExecuteAction
    
    # Référence au ViewModel parent (optionnelle, pour logging/debug)
    [object] $Parent = $null
    
    # Événement CanExecuteChanged (requis par ICommand)
    [EventHandler] $CanExecuteChanged
    
    # État interne
    [bool] $IsExecuting = $false
    [string] $CommandName = ""
    
    # Constructeur simple
    RelayCommand([scriptblock] $executeAction) {
        $this.Initialize($executeAction, $null, $null, "")
    }
    
    # Constructeur avec CanExecute
    RelayCommand([scriptblock] $executeAction, [scriptblock] $canExecuteAction) {
        $this.Initialize($executeAction, $canExecuteAction, $null, "")
    }
    
    # Constructeur avec parent ViewModel
    RelayCommand([scriptblock] $executeAction, [scriptblock] $canExecuteAction, [object] $parent) {
        $this.Initialize($executeAction, $canExecuteAction, $parent, "")
    }
    
    # Constructeur complet avec nom
    RelayCommand([scriptblock] $executeAction, [scriptblock] $canExecuteAction, [object] $parent, [string] $commandName) {
        $this.Initialize($executeAction, $canExecuteAction, $parent, $commandName)
    }
    
    # Initialisation commune
    [void] Initialize([scriptblock] $executeAction, [scriptblock] $canExecuteAction, [object] $parent, [string] $commandName) {
        if (-not $executeAction) {
            throw [ArgumentNullException]::new("executeAction", "L'action Execute ne peut pas être null")
        }
        
        $this.ExecuteAction = $executeAction
        $this.CanExecuteAction = $canExecuteAction
        $this.Parent = $parent
        $this.CommandName = if ([string]::IsNullOrEmpty($commandName)) { "UnnamedCommand" } else { $commandName }
        
        # Log d'initialisation si parent avec logging disponible
        $this.LogDebug("RelayCommand '$($this.CommandName)' initialisée")
    }
    
    # Implémentation ICommand.Execute
    [void] Execute([object] $parameter) {
        if (-not $this.CanExecute($parameter)) {
            $this.LogWarning("Tentative d'exécution de '$($this.CommandName)' alors que CanExecute = false")
            return
        }
        
        if ($this.IsExecuting) {
            $this.LogWarning("Commande '$($this.CommandName)' déjà en cours d'exécution")
            return
        }
        
        try {
            $this.IsExecuting = $true
            $this.LogDebug("Exécution de la commande '$($this.CommandName)'")
            
            # Notification changement état avant exécution
            $this.RaiseCanExecuteChanged()
            
            # Mesure du temps d'exécution pour debug
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            
            # Exécution de l'action
            if ($this.ExecuteAction) {
                & $this.ExecuteAction $parameter
            }
            
            $stopwatch.Stop()
            $this.LogDebug("Commande '$($this.CommandName)' exécutée en $($stopwatch.ElapsedMilliseconds) ms")
            
        }
        catch {
            $this.LogError("Erreur lors de l'exécution de '$($this.CommandName)': $($_.Exception.Message)")
            
            # Possibilité d'ajouter une gestion d'erreur personnalisée
            $this.OnExecuteError($parameter, $_.Exception)
            
            # Re-lancer l'exception pour que l'UI puisse la gérer si nécessaire
            throw
        }
        finally {
            $this.IsExecuting = $false
            
            # Notification changement état après exécution
            $this.RaiseCanExecuteChanged()
        }
    }
    
    # Implémentation ICommand.CanExecute
    [bool] CanExecute([object] $parameter) {
        try {
            # Si la commande est en cours d'exécution, elle ne peut pas être re-exécutée
            if ($this.IsExecuting) {
                return $false
            }
            
            # Si aucune condition CanExecute définie, la commande est toujours exécutable
            if (-not $this.CanExecuteAction) {
                return $true
            }
            
            # Évaluation de la condition personnalisée
            $result = & $this.CanExecuteAction $parameter
            
            # Conversion en bool si nécessaire
            if ($result -is [bool]) {
                return $result
            } else {
                # Conversion implicite (null, 0, "", $false -> false, tout le reste -> true)
                return [bool]$result
            }
        }
        catch {
            $this.LogError("Erreur lors de l'évaluation CanExecute pour '$($this.CommandName)': $($_.Exception.Message)")
            
            # En cas d'erreur dans CanExecute, on considère que la commande n'est pas exécutable
            # pour éviter des comportements imprévisibles
            return $false
        }
    }
    
    # Méthode pour déclencher l'événement CanExecuteChanged
    [void] RaiseCanExecuteChanged() {
        try {
            if ($this.CanExecuteChanged) {
                # Exécution sur le thread UI si nécessaire
                if ([System.Windows.Application]::Current -and 
                    [System.Windows.Application]::Current.Dispatcher -and
                    -not [System.Windows.Application]::Current.Dispatcher.CheckAccess()) {
                    
                    [System.Windows.Application]::Current.Dispatcher.BeginInvoke([Action]{
                        $this.CanExecuteChanged.Invoke($this, [System.EventArgs]::Empty)
                    })
                } else {
                    $this.CanExecuteChanged.Invoke($this, [System.EventArgs]::Empty)
                }
            }
        }
        catch {
            $this.LogError("Erreur lors de RaiseCanExecuteChanged pour '$($this.CommandName)': $($_.Exception.Message)")
        }
    }
    
    # Méthode appelée en cas d'erreur d'exécution (extensible)
    [void] OnExecuteError([object] $parameter, [System.Exception] $exception) {
        # Méthode virtuelle - peut être override si nécessaire
        # Par défaut, ne fait rien de spécial
    }
    
    # Helpers pour logging (délègue au parent s'il a un LoggingService)
    [void] LogDebug([string] $message) {
        if ($this.Parent -and 
            $this.Parent.PSObject.Properties['LoggingService'] -and 
            $this.Parent.LoggingService) {
            $this.Parent.LoggingService.Debug("[RelayCommand] $message")
        }
    }
    
    [void] LogInfo([string] $message) {
        if ($this.Parent -and 
            $this.Parent.PSObject.Properties['LoggingService'] -and 
            $this.Parent.LoggingService) {
            $this.Parent.LoggingService.Info("[RelayCommand] $message")
        }
    }
    
    [void] LogWarning([string] $message) {
        if ($this.Parent -and 
            $this.Parent.PSObject.Properties['LoggingService'] -and 
            $this.Parent.LoggingService) {
            $this.Parent.LoggingService.Warning("[RelayCommand] $message")
        }
    }
    
    [void] LogError([string] $message) {
        if ($this.Parent -and 
            $this.Parent.PSObject.Properties['LoggingService'] -and 
            $this.Parent.LoggingService) {
            $this.Parent.LoggingService.Error("[RelayCommand] $message")
        }
    }
    
    # Propriétés utilitaires pour debug et monitoring
    [bool] GetIsExecuting() {
        return $this.IsExecuting
    }
    
    [string] GetCommandName() {
        return $this.CommandName
    }
    
    [void] SetCommandName([string] $name) {
        $this.CommandName = $name
    }
    
    # Méthode ToString() pour debug
    [string] ToString() {
        $canExecuteStatus = if ($this.CanExecuteAction) { "with condition" } else { "always enabled" }
        $executingStatus = if ($this.IsExecuting) { "executing" } else { "idle" }
        
        return "RelayCommand '$($this.CommandName)' ($canExecuteStatus, $executingStatus)"
    }
    
    # Méthode pour tester la commande (utile pour les tests unitaires)
    [hashtable] TestCommand([object] $parameter = $null) {
        $result = @{
            CommandName = $this.CommandName
            CanExecute = $this.CanExecute($parameter)
            IsExecuting = $this.IsExecuting
            HasCanExecuteAction = $this.CanExecuteAction -ne $null
            HasExecuteAction = $this.ExecuteAction -ne $null
            ExecutionResult = $null
            ExecutionError = $null
            ExecutionTime = $null
        }
        
        if ($result.CanExecute) {
            try {
                $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                $this.Execute($parameter)
                $stopwatch.Stop()
                
                $result.ExecutionResult = "Success"
                $result.ExecutionTime = $stopwatch.ElapsedMilliseconds
            }
            catch {
                $result.ExecutionResult = "Error"
                $result.ExecutionError = $_.Exception.Message
            }
        }
        
        return $result
    }
    
    # Factory methods statiques pour création simplifiée
    static [RelayCommand] Create([scriptblock] $executeAction) {
        return [RelayCommand]::new($executeAction)
    }
    
    static [RelayCommand] CreateWithCondition([scriptblock] $executeAction, [scriptblock] $canExecuteAction) {
        return [RelayCommand]::new($executeAction, $canExecuteAction)
    }
    
    static [RelayCommand] CreateNamed([scriptblock] $executeAction, [string] $name) {
        return [RelayCommand]::new($executeAction, $null, $null, $name)
    }
}

# Classe d'extension pour commandes asynchrones (bonus)
class AsyncRelayCommand : RelayCommand {
    [bool] $IsAsync = $true
    [System.Threading.Tasks.Task] $CurrentTask = $null
    
    AsyncRelayCommand([scriptblock] $executeAction) : base($executeAction) {
        $this.CommandName = "AsyncCommand"
    }
    
    AsyncRelayCommand([scriptblock] $executeAction, [scriptblock] $canExecuteAction) : base($executeAction, $canExecuteAction) {
        $this.CommandName = "AsyncCommand"
    }
    
    # Override Execute pour exécution asynchrone
    [void] Execute([object] $parameter) {
        if (-not $this.CanExecute($parameter)) {
            return
        }
        
        if ($this.CurrentTask -and -not $this.CurrentTask.IsCompleted) {
            $this.LogWarning("Commande asynchrone '$($this.CommandName)' déjà en cours")
            return
        }
        
        $this.IsExecuting = $true
        $this.RaiseCanExecuteChanged()
        
        # Création d'une tâche PowerShell asynchrone
        $this.CurrentTask = [System.Threading.Tasks.Task]::Run({
            try {
                $this.LogDebug("Début exécution asynchrone '$($this.CommandName)'")
                & $this.ExecuteAction $parameter
                $this.LogDebug("Fin exécution asynchrone '$($this.CommandName)'")
            }
            catch {
                $this.LogError("Erreur exécution asynchrone '$($this.CommandName)': $($_.Exception.Message)")
                throw
            }
            finally {
                $this.IsExecuting = $false
                $this.RaiseCanExecuteChanged()
            }
        })
    }
    
    # Méthode pour attendre la fin de l'exécution
    [void] Wait() {
        if ($this.CurrentTask) {
            $this.CurrentTask.Wait()
        }
    }
    
    # Méthode pour annuler l'exécution (si possible)
    [void] Cancel() {
        if ($this.CurrentTask -and -not $this.CurrentTask.IsCompleted) {
            $this.LogInfo("Tentative d'annulation de la commande asynchrone '$($this.CommandName)'")
            # Note: L'annulation réelle dépend de l'implémentation du scriptblock
            $this.IsExecuting = $false
            $this.RaiseCanExecuteChanged()
        }
    }
}