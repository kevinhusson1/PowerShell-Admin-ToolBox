function Initialize-ToolBoxEnvironment {
    <#
    .SYNOPSIS
        Initialise l'environnement complet ToolBox
    
    .DESCRIPTION
        Fonction universelle d'initialisation qui :
        - Vérifie les prérequis système
        - Charge les assemblies WPF nécessaires
        - Import le module Core si pas déjà fait
        - Configure les variables globales de statut
        
        Utilisée par tous les modules (autonomes ou via launcher)
    
    .PARAMETER FromLauncher
        Indique si l'initialisation est appelée depuis le launcher principal
    
    .PARAMETER Force
        Force la réinitialisation même si déjà fait
    
    .PARAMETER ShowDetails
        Affiche les détails de l'initialisation (pour debug)
    
    .EXAMPLE
        Initialize-ToolBoxEnvironment
        
    .EXAMPLE
        Initialize-ToolBoxEnvironment -FromLauncher -ShowDetails
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [switch]$FromLauncher,
        
        [Parameter(Mandatory = $false)]
        [switch]$Force,
        
        [Parameter(Mandatory = $false)]
        [switch]$ShowDetails
    )
    
    try {
        # Vérification si déjà initialisé (sauf si Force)
        if ($Global:ToolBoxEnvironmentInitialized -and -not $Force) {
            if ($ShowDetails) {
                Write-ToolBoxLog -Level "Debug" -Message "Environnement ToolBox déjà initialisé" -Component "Environment"
            }
            return $true
        }
        
        # ÉTAPE 1 : Chargement de la configuration ToolBox EN PREMIER
        try {
            Import-ToolBoxConfig
            $logLevel = Get-ToolBoxConfig -Section "Application" -Property "LogLevel"
            if ($logLevel) {
                $Global:ToolBoxLogLevel = $logLevel
            } else {
                $Global:ToolBoxLogLevel = "Info"  # Défaut
            }
        }
        catch {
            $Global:ToolBoxLogLevel = "Info"  # Défaut si config absente
        }
        
        Write-ToolBoxLog -Level "Info" -Message "Initialisation de l'environnement ToolBox..." -Component "Environment" -Console $ShowDetails
        
        # ÉTAPE 2 : Vérification des prérequis système
        Write-ToolBoxLog -Level "Debug" -Message "Vérification des prérequis système" -Component "Environment" -Console $ShowDetails
        
        # PowerShell 7.5+
        $currentVersion = $PSVersionTable.PSVersion
        $requiredVersion = [System.Version]"7.5.0"
        if ($currentVersion -lt $requiredVersion) {
            throw "PowerShell version $currentVersion détectée. Version 7.5+ requise."
        }
        
        # .NET 9.0
        $envVersion = [System.Environment]::Version
        if ($envVersion.Major -lt 9) {
            $psRuntime = $PSVersionTable.PSEdition
            if ($psRuntime -ne "Core") {
                throw ".NET 9.0 ou PowerShell Core requis"
            }
        }
        
        # ExecutionPolicy
        $currentPolicy = Get-ExecutionPolicy -Scope CurrentUser
        $restrictivePolicies = @('Restricted', 'AllSigned')
        if ($currentPolicy -in $restrictivePolicies) {
            throw "ExecutionPolicy '$currentPolicy' trop restrictive. Politique 'RemoteSigned' ou 'Unrestricted' requise."
        }
        
        Write-ToolBoxLog -Level "Debug" -Message "Prérequis système validés" -Component "Environment" -Console $ShowDetails
        
        # ÉTAPE 3 : Chargement des assemblies WPF
        Write-ToolBoxLog -Level "Debug" -Message "Chargement des assemblies WPF" -Component "Environment" -Console $ShowDetails
        
        try {
            Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
            Add-Type -AssemblyName PresentationCore -ErrorAction Stop
            Add-Type -AssemblyName WindowsBase -ErrorAction Stop
            
            Write-ToolBoxLog -Level "Debug" -Message "Assemblies WPF chargées avec succès" -Component "Environment" -Console $ShowDetails
        }
        catch {
            throw "Erreur lors du chargement des assemblies WPF : $($_.Exception.Message)"
        }
        
        # ÉTAPE 4 : Configuration des variables globales
        Write-ToolBoxLog -Level "Debug" -Message "Configuration des variables globales" -Component "Environment" -Console $ShowDetails
        
        $Global:ToolBoxEnvironmentInitialized = $true
        $Global:ToolBoxLaunchedFromLauncher = $FromLauncher.IsPresent
        $Global:ToolBoxCoreLoaded = $true  # Module Core forcément chargé si on exécute cette fonction
        $Global:ToolBoxInitializationTime = Get-Date
        
        # ÉTAPE 5 : Détermination du répertoire racine ToolBox
        $currentScriptPath = $PSScriptRoot
        if (-not $currentScriptPath) {
            $currentScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
        }
        
        # Remonter depuis Core/Public vers la racine
        $Global:ToolBoxRootPath = Split-Path -Parent (Split-Path -Parent $currentScriptPath)
        $Global:ToolBoxConfigPath = Join-Path $Global:ToolBoxRootPath "Config"
        $Global:ToolBoxModulesPath = Join-Path $Global:ToolBoxRootPath "Modules"
        $Global:ToolBoxStylesPath = Join-Path $Global:ToolBoxRootPath "Styles"
        $Global:ToolBoxLogsPath = Join-Path $Global:ToolBoxRootPath "Logs"
        
        Write-ToolBoxLog -Level "Debug" -Message "Répertoire racine ToolBox : $Global:ToolBoxRootPath" -Component "Environment" -Console $ShowDetails
        
        # ÉTAPE 6 : Initialisation du logger avec les chemins corrects
        Initialize-ToolBoxLogger
        
        # ÉTAPE 7 : Logging de fin d'initialisation
        $initMode = if ($FromLauncher) { "depuis le Launcher" } else { "en mode autonome" }
        Write-ToolBoxLog -Level "Info" -Message "Environnement ToolBox initialisé avec succès $initMode" -Component "Environment" -UI $true
        
        if ($ShowDetails) {
            Write-ToolBoxLog -Level "Info" -Message "Variables globales configurées :" -Component "Environment" -Console $true
            Write-ToolBoxLog -Level "Info" -Message "  ToolBoxRootPath: $Global:ToolBoxRootPath" -Component "Environment" -Console $true
            Write-ToolBoxLog -Level "Info" -Message "  LaunchedFromLauncher: $Global:ToolBoxLaunchedFromLauncher" -Component "Environment" -Console $true
        }
        
        return $true
    }
    catch {
        $errorMsg = "Erreur lors de l'initialisation de l'environnement ToolBox : $($_.Exception.Message)"
        Write-Error $errorMsg
        
        # Essayer de logger si possible
        if (Get-Command Write-ToolBoxLog -ErrorAction SilentlyContinue) {
            Write-ToolBoxLog -Level "Error" -Message $errorMsg -Component "Environment" -Console $true
        }
        
        return $false
    }
}