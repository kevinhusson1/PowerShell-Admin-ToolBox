#Requires -Version 7.0

param(
    [string]$LauncherPID,
    [string]$AuthContext,
    [string]$AuthUPN,     # Nouvelle méthode (Secure)
    [string]$TenantId,    # ID du Tenant pour l'auth
    [string]$ClientId     # ID de l'App (AppId)
)

# =====================================================================
# 1. PRÉ-CHARGEMENT DES ASSEMBLAGES WPF REQUIS
# =====================================================================
try { 
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase 
}
catch { 
    Write-Error "Impossible de charger les assemblages WPF."; exit 1 
}

# =====================================================================
# 2. DÉFINITION DES CHEMINS ET IMPORTS
# =====================================================================
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = (Get-Item $scriptRoot).Parent.Parent.Parent.FullName
$Global:ProjectRoot = $projectRoot
$env:PSModulePath = "$($projectRoot)\Modules;$($projectRoot)\Vendor;$($env:PSModulePath)"

try { 
    Import-Module "PSSQLite", "Core", "UI", "Localization", "Logging", "Database", "Azure" -Force
    . (Join-Path $scriptRoot "Functions\Initialize-CreateUserUI.ps1")
}
catch { 
    [System.Windows.MessageBox]::Show("Erreur critique lors de l'import des modules :`n$($_.Exception.Message)", "Erreur", "OK", "Error"); exit 1 
}

# =====================================================================
# 3. GESTION DU VERROU (LOCK) VIA BASE DE DONNÉES
# =====================================================================
try {
    Initialize-AppDatabase -ProjectRoot $projectRoot
    $manifest = Get-Content (Join-Path $scriptRoot "manifest.json") -Raw | ConvertFrom-Json
    if (-not (Test-AppScriptLock -Script $manifest)) { 
        [System.Windows.MessageBox]::Show((Get-AppText -Key 'messages.execution_limit_reached'), (Get-AppText -Key 'messages.execution_forbidden_title'), "OK", "Error"); exit 1 
    }
    Add-AppScriptLock -Script $manifest -OwnerPID $PID
}
catch { 
    [System.Windows.MessageBox]::Show("Erreur critique lors du verrouillage :`n$($_.Exception.Message)", "Erreur", "OK", "Error"); exit 1 
}

# =====================================================================
# 4. BLOC D'EXÉCUTION PRINCIPAL
# =====================================================================
try {
    # --- Étape 1 : Initialisation du contexte et du logging ---
    $Global:AppConfig = Get-AppConfiguration
    $VerbosePreference = if ($Global:AppConfig.enableVerboseLogging) { "Continue" } else { "SilentlyContinue" }
    
    # --- Étape 2 : Détermination du mode et rapport de progression initial ---
    $isLauncherMode = -not ([string]::IsNullOrEmpty($LauncherPID))
    if ($isLauncherMode) { 
        Write-Verbose "Mode Lanceur détecté." 
        Set-AppScriptProgress -OwnerPID $PID -ProgressPercentage 10 -StatusMessage "10% Initialisation du contexte..."
    }
    else {
        Write-Verbose "Mode Autonome détecté."
    }

    Initialize-AppLocalization -ProjectRoot $projectRoot -Language $Global:AppConfig.defaultLanguage
    $scriptLangFile = "$scriptRoot\Localization\$($Global:AppConfig.defaultLanguage).json"
    if (Test-Path $scriptLangFile) { Add-AppLocalizationSource -FilePath $scriptLangFile }
    if ($isLauncherMode) {
        Set-AppScriptProgress -OwnerPID $PID -ProgressPercentage 60 -StatusMessage "60% Contexte d'authentification établi."
    }

    # 1. Chargement de l'interface
    $xamlPath = Join-Path $scriptRoot "CreateUser.xaml"
    $window = Import-AppXamlTemplate -XamlPath $xamlPath
    
    # 2. Chargement des composants de style
    Initialize-AppUIComponents -Window $window -ProjectRoot $projectRoot -Components 'Buttons', 'Inputs', 'Layouts', 'Display', 'ProfileButton'
    
    if ($isLauncherMode) {
        Set-AppScriptProgress -OwnerPID $PID -ProgressPercentage 80 -StatusMessage "80% Chargement de l'interface utilisateur..."
    }
    # 3. Peuplement de l'en-tête (logique de présentation)
    try {
        # CORRECTION : On cible maintenant l'ImageBrush à l'intérieur du masque
        $iconImageBrush = $window.FindName("IconImageBrush")
        $subtitleText = $window.FindName("SubtitleText")

        $iconFullPath = Join-Path -Path $projectRoot -ChildPath "Templates\Resources\Icons\PNG\$($manifest.icon.value)"
        if (Test-Path $iconFullPath) {
            $bitmap = [System.Windows.Media.Imaging.BitmapImage]::new([System.Uri]$iconFullPath)
            # CORRECTION : On définit la propriété ImageSource de l'ImageBrush
            $iconImageBrush.ImageSource = $bitmap
        }
        
        $subtitleText.Text = Get-AppText -Key $manifest.description
    }
    catch {
        Write-Warning "Erreur lors du peuplement de l'en-tête du script : $($_.Exception.Message)"
    }

    # ===============================================================
    # 5. GESTION DE L'IDENTITÉ (Standard v3.0)
    # ===============================================================
    
    # Récupération de la config globale si les paramètres ne sont pas passés (Robustesse)
    if (-not $TenantId) { $TenantId = $Global:AppConfig.azure.tenantId }
    if (-not $ClientId) { $ClientId = $Global:AppConfig.azure.authentication.userAuth.appId }
    
    # A. Initialisation de l'identité
    $userIdentity = $null

    # PRIORITÉ 1: Nouvelle méthode Secure (UPN via Token Cache)
    if (-not [string]::IsNullOrWhiteSpace($AuthUPN)) {
        Write-Verbose "[CreateUser] AuthUPN reçu : $AuthUPN. Tentative de reprise de session..."
        try {
            $userIdentity = Connect-AppChildSession -AuthUPN $AuthUPN -TenantId $TenantId -ClientId $ClientId
            if (-not $userIdentity.Connected) {
                Write-Warning "[CreateUser] Connect-AppChildSession a retourné Connected=$false (Erreur: $($userIdentity.Error))"
            }
        }
        catch {
            Write-Warning "[CreateUser] Exception Auth Secure: $_" 
            $userIdentity = @{ Connected = $false }
        }
    } 
    # PRIORITÉ 2: Ancienne méthode (Fallback Legacy)
    elseif (-not [string]::IsNullOrWhiteSpace($AuthContext)) {
        Write-Verbose "[CreateUser] AuthContext Legacy détecté."
        try {
            $json = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($AuthContext))
            $rawObj = $json | ConvertFrom-Json
            $userIdentity = $rawObj.UserAuth 
        }
        catch { 
            Write-Warning "[CreateUser] Echec Auth Legacy: $_"
            $userIdentity = @{ Connected = $false } 
        }
    }
    else {
        # Aucune info -> Non connecté
        Write-Verbose "[CreateUser] Aucun contexte d'authentification initial."
        $userIdentity = @{ Connected = $false }
    }

    # Définition des actions pour le mode autonome
    $OnConnect = {
        # Chargement à la volée des configs si nécessaire
        if (-not $Global:AppConfig) { $Global:AppConfig = Get-AppConfiguration -ProjectRoot $ProjectRoot }
        
        $newIdentity = Connect-AppAzureWithUser -AppId $Global:AppConfig.azure.authentication.userAuth.appId -TenantId $Global:AppConfig.azure.tenantId
        
        # Mise à jour immédiate de l'UI après connexion réussie
        Set-AppWindowIdentity -Window $window -UserSession $newIdentity -LauncherPID $LauncherPID -OnConnect $OnConnect -OnDisconnect $OnDisconnect
    }

    $OnDisconnect = {
        Disconnect-AppAzureUser
        $nullIdentity = @{ Connected = $false }
        Set-AppWindowIdentity -Window $window -UserSession $nullIdentity -LauncherPID $LauncherPID -OnConnect $OnConnect -OnDisconnect $OnDisconnect
    }

    # 2. Application Visuelle (Module UI)
    Set-AppWindowIdentity -Window $window -UserSession $userIdentity -LauncherPID $LauncherPID -OnConnect $OnConnect -OnDisconnect $OnDisconnect

    # 4. Initialisation de l'UI et attachement des événements
    # La fonction retourne une hashtable des contrôles que nous stockons localement.
    $scriptControls = Initialize-CreateUserUI -Window $window

    # 5. Affichage de la fenêtre
    if ($isLauncherMode) {
        Set-AppScriptProgress -OwnerPID $PID -ProgressPercentage 100 -StatusMessage "100% Interface prête."
    }
    $window.ShowDialog() | Out-Null

}
catch {
    $title = Get-AppText -Key 'messages.fatal_error_title'
    [System.Windows.MessageBox]::Show("Une erreur fatale est survenue :`n$($_.Exception.Message)`n$($_.ScriptStackTrace)", $title, "OK", "Error")
}
finally {
    # --- NETTOYAGE FINAL ---
    Unlock-AppScriptLock -OwnerPID $PID
}