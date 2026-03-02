#Requires -Version 7.0

<#
.SYNOPSIS
    SQUELETTE DE RÉFÉRENCE (TEMPLATE) v2.0
    Ce script sert de base pour toute nouvelle application intégrée à la Toolbox.
#>

param(
    [string]$LauncherPID,
    [string]$AuthContext,
    [string]$AuthUPN,     # Nouvelle méthode (Secure)
    [string]$TenantId,    # ID du Tenant pour l'auth
    [string]$ClientId     # ID de l'App (AppId)
)

# =====================================================================
# 1. PRÉ-CHARGEMENT (BOILERPLATE)
# =====================================================================
# FIX MSAL CRITIQUE
Import-Module Microsoft.Graph.Authentication -MinimumVersion 2.32.0 -ErrorAction SilentlyContinue

try {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
}
catch {
    Write-Error "WPF non disponible."; exit 1
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = (Get-Item $scriptRoot).Parent.Parent.Parent.FullName
$Global:ProjectRoot = $projectRoot
$env:PSModulePath = "$($projectRoot)\Modules;$($projectRoot)\Vendor;$($env:PSModulePath)"

# =====================================================================
# 2. CHARGEMENT DES MODULES & PROGRESSION (10%)
# =====================================================================
# Fonction locale pour le feedback Launcher
function Send-Progress { param([int]$Percent, [string]$Msg) if ($LauncherPID) { Set-AppScriptProgress -OwnerPID $PID -ProgressPercentage $Percent -StatusMessage $Msg } }

Send-Progress 10 "Initialisation des modules..."
try {
    Import-Module "PSSQLite", "Core", "UI", "Localization", "Logging", "Database", "Azure" -Force
}
catch {
    [System.Windows.MessageBox]::Show("Erreur critique import modules :`n$($_.Exception.Message)", "Erreur", "OK", "Error"); exit 1
}

# =====================================================================
# 3. VERROUILLAGE & CONTEXTE (30%)
# =====================================================================
Send-Progress 30 "Vérification des droits et verrous..."
try {
    Initialize-AppDatabase -ProjectRoot $projectRoot
    $manifest = Get-Content (Join-Path $scriptRoot "manifest.json") -Raw | ConvertFrom-Json
    
    # Vérification Concurrence BDD
    if (-not (Test-AppScriptLock -Script $manifest)) {
        [System.Windows.MessageBox]::Show((Get-AppText 'messages.execution_limit_reached'), (Get-AppText 'messages.execution_forbidden_title'), "OK", "Error"); exit 1
    }
    Add-AppScriptLock -Script $manifest -OwnerPID $PID

    # Chargement Config & Langue
    $Global:AppConfig = Get-AppConfiguration
    $VerbosePreference = if ($Global:AppConfig.enableVerboseLogging) { "Continue" } else { "SilentlyContinue" }
    
    # Localisation "Mille-Feuille" (Global -> Modules -> Local)
    Initialize-AppLocalization -ProjectRoot $projectRoot -Language $Global:AppConfig.defaultLanguage
    $localLang = "$scriptRoot\Localization\$($Global:AppConfig.defaultLanguage).json"
    if (Test-Path $localLang) { Add-AppLocalizationSource -FilePath $localLang }

}
catch {
    [System.Windows.MessageBox]::Show("Erreur démarrage :`n$($_.Exception.Message)", "Erreur", "OK", "Error"); exit 1
}

# =====================================================================
# 4. CHARGEMENT UI (60% -> 80%)
# =====================================================================
Send-Progress 60 "Chargement de l'interface..."
if ($LauncherPID) { Start-Sleep -Milliseconds 200 } # Simulation charge utile

try {
    # Import XAML
    $window = Import-AppXamlTemplate -XamlPath (Join-Path $scriptRoot "DefaultUI.xaml")
    
    # Injection Styles
    Initialize-AppUIComponents -Window $window -ProjectRoot $projectRoot -Components 'Buttons', 'Inputs', 'Layouts', 'Display', 'ProfileButton'

    Send-Progress 80 "Configuration visuelle..."
    if ($LauncherPID) { Start-Sleep -Milliseconds 200 } # Simulation charge utile

    # --- LOGIQUE DE PRÉSENTATION (En-tête dynamique) ---
    # On peuple l'en-tête automatiquement avec les infos du Manifeste
    $imgBrush = $window.FindName("HeaderIconBrush")
    if ($imgBrush -and $manifest.icon) {
        $iconPath = Join-Path $projectRoot "Templates\Resources\Icons\PNG\$($manifest.icon.value)"
        if (Test-Path $iconPath) {
            $imgBrush.ImageSource = [System.Windows.Media.Imaging.BitmapImage]::new([Uri]$iconPath)
        }
    }

    # ===============================================================
    # 5. GESTION DE L'IDENTITÉ (Standard v3.0)
    # ===============================================================
    
    # Stratégie d'authentification :
    # 1. Mode "Secure Token" (Priorité) : Le Launcher a pré-authentifié l'utilisateur et partagé le Token Cache.
    # 2. Mode "Legacy" (Fallback) : Le Launcher a passé un contexte Base64 (Déprécié à terme).
    # 3. Mode "Autonome" : L'utilisateur gère sa connexion via les boutons UI.

    # Récupération de la config globale si les paramètres ne sont pas passés (Robustesse)
    if (-not $TenantId) { $TenantId = $Global:AppConfig.azure.tenantId }
    if (-not $ClientId) { $ClientId = $Global:AppConfig.azure.authentication.userAuth.appId }
    
    # A. Initialisation de l'identité
    $userIdentity = $null

    # PRIORITÉ 1: Nouvelle méthode Secure (UPN via Token Cache)
    if (-not [string]::IsNullOrWhiteSpace($AuthUPN)) {
        Write-Verbose "[DefaultUI] AuthUPN reçu : $AuthUPN. Tentative de reprise de session..."
        try {
            $userIdentity = Connect-AppChildSession -AuthUPN $AuthUPN -TenantId $TenantId -ClientId $ClientId
            if (-not $userIdentity.Connected) {
                Write-Warning "[DefaultUI] Connect-AppChildSession a retourné Connected=$false (Erreur: $($userIdentity.Error))"
            }
        }
        catch {
            Write-Warning "[DefaultUI] Exception Auth Secure: $_" 
            $userIdentity = @{ Connected = $false }
        }
    } 
    # PRIORITÉ 2: Ancienne méthode (Fallback Legacy)
    elseif (-not [string]::IsNullOrWhiteSpace($AuthContext)) {
        Write-Verbose "[DefaultUI] AuthContext Legacy détecté."
        try {
            $json = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($AuthContext))
            $rawObj = $json | ConvertFrom-Json
            $userIdentity = $rawObj.UserAuth 
        }
        catch { 
            Write-Warning "[DefaultUI] Echec Auth Legacy: $_"
            $userIdentity = @{ Connected = $false } 
        }
    }
    else {
        # Aucune info -> Non connecté
        Write-Verbose "[DefaultUI] Aucun contexte d'authentification initial."
        $userIdentity = @{ Connected = $false }
    }

    # Définition des actions pour le mode autonome
    $OnConnect = {
        # Chargement à la volée des configs si nécessaire (si non passé par Launcher)
        if (-not $Global:AppConfig) { $Global:AppConfig = Get-AppConfiguration -ProjectRoot $ProjectRoot }
        
        $newIdentity = Connect-AppAzureWithUser -AppId $Global:AppConfig.azure.authentication.userAuth.appId -TenantId $Global:AppConfig.azure.tenantId
        
        if (-not $newIdentity.Connected) {
            Write-Warning "[DefaultUI] Authentification échouée ou annulée : $($newIdentity.ErrorMessage)"
            $msg = Get-AppText 'messages.auth_failed'
            if (-not $msg) { $msg = "L'authentification a échoué." }
            [System.Windows.MessageBox]::Show("$msg`nErreur : $($newIdentity.ErrorMessage)", "Erreur de Connexion", "OK", "Warning") | Out-Null
        }

        # Mise à jour immédiate de l'UI après tentative de connexion
        Set-AppWindowIdentity -Window $window -UserSession $newIdentity -LauncherPID $LauncherPID -OnConnect $OnConnect -OnDisconnect $OnDisconnect
    }

    $OnDisconnect = {
        Disconnect-AppAzureUser
        $nullIdentity = @{ Connected = $false }
        Set-AppWindowIdentity -Window $window -UserSession $nullIdentity -LauncherPID $LauncherPID -OnConnect $OnConnect -OnDisconnect $OnDisconnect
    }

    # 2. Application Visuelle (Module UI)
    Set-AppWindowIdentity -Window $window -UserSession $userIdentity -LauncherPID $LauncherPID -OnConnect $OnConnect -OnDisconnect $OnDisconnect

    # Optionnel : Forcer le titre/sous-titre si on ne veut pas utiliser le Binding XAML ##loc:##
    # $window.FindName("HeaderTitleText").Text = Get-AppText $manifest.name
    # $window.FindName("HeaderSubtitleText").Text = Get-AppText $manifest.description

    # --- INITIALISATION DU SCRIPT (Event Handlers) ---
    # C'est ici que vous feriez : . (Join-Path $scriptRoot "Functions\Initialize-MyUI.ps1")
    # $controls = Initialize-MyUI -Window $window

}
catch {
    [System.Windows.MessageBox]::Show("Erreur UI :`n$($_.Exception.Message)", "Erreur", "OK", "Error")
    Unlock-AppScriptLock -OwnerPID $PID
    exit 1
}

# =====================================================================
# 5. AFFICHAGE (100%) & NETTOYAGE
# =====================================================================
Send-Progress 100 "Prêt."
if ($LauncherPID) { Start-Sleep -Milliseconds 300 } # Juste pour voir le 100%

try {
    $window.ShowDialog() | Out-Null
}
finally {
    Unlock-AppScriptLock -OwnerPID $PID
}