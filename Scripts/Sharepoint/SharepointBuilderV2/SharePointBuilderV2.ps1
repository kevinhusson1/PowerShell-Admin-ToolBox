#Requires -Version 7.0


param(
    [string]$LauncherPID,
    [string]$AuthContext,
    [string]$AuthUPN,     # Nouvelle méthode (Secure)
    [string]$TenantId,    # ID du Tenant pour l'auth
    [string]$ClientId,    # ID de l'App (AppId)

    # Paramètres Autopilot
    [string]$AutoSiteUrl,       # URL du site cible
    [string]$AutoLibraryName,   # Nom de la bibliothèque
    [string]$AutoTemplateId,    # ID du modèle à forcer
    [hashtable]$AutoFormData    # Données pour le formulaire (ex: @{Client="Total"; Year="2024"})
)

# --- CORRECTIF : NETTOYAGE PRÉVENTIF DES VARIABLES GLOBALES ---
# Cela évite que des tests précédents dans la même console ne polluent l'état
$Global:AppAzureAuth = $null
$Global:AppControls = @{}

$VerbosePreference = 'Continue' 

# 1. PRÉ-CHARGEMENT
try { Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase } catch { exit 1 }

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = (Get-Item $scriptRoot).Parent.Parent.Parent.FullName
$Global:ProjectRoot = $projectRoot
$env:PSModulePath = "$($projectRoot)\Modules;$($projectRoot)\Vendor;$($env:PSModulePath)"

# 2. MODULES
function Send-Progress { param([int]$Percent, [string]$Msg) if ($LauncherPID) { Set-AppScriptProgress -OwnerPID $PID -ProgressPercentage $Percent -StatusMessage $Msg } }

Send-Progress 10 "Initialisation des modules..."
try {
    Import-Module "PSSQLite", "Core", "UI", "Localization", "Logging", "Database", "Azure" -Force
}
catch {
    [System.Windows.MessageBox]::Show("Erreur modules : $($_.Exception.Message)", "Fatal", "OK", "Error"); exit 1
}

# 3. INIT & LOCK
Send-Progress 30 "Vérification des droits et verrous..."
try {
    Initialize-AppDatabase -ProjectRoot $projectRoot
    $manifest = Get-Content (Join-Path $scriptRoot "manifest.json") -Raw | ConvertFrom-Json
    
    if (-not (Test-AppScriptLock -Script $manifest)) { 
        [System.Windows.MessageBox]::Show("Déjà en cours d'exécution.", "Stop", "OK", "Warning"); exit 1 
    }
    Add-AppScriptLock -Script $manifest -OwnerPID $PID

    # Chargement Config & Langue
    $Global:AppConfig = Get-AppConfiguration
    $global:VerbosePreference = if ($Global:AppConfig.enableVerboseLogging) { "Continue" } else { "SilentlyContinue" }

    Initialize-AppLocalization -ProjectRoot $projectRoot -Language $Global:AppConfig.defaultLanguage
    
    # Chargement Loc Locale
    $localLang = "$scriptRoot\Localization\$($Global:AppConfig.defaultLanguage).json"
    if (Test-Path $localLang) { Add-AppLocalizationSource -FilePath $localLang }

    # AUTHENTIFICATION GRAPH (SILENCIEUSE APP-ONLY) - NOUVEAU MOTEUR V2
    Send-Progress 45 "Authentification silencieuse Microsoft Graph (App-Only)..."
    $tenantId = $Global:AppConfig.azure.tenantName
    $clientId = $Global:AppConfig.azure.authentication.userAuth.appId
    $thumbprint = $Global:AppConfig.azure.certThumbprint
    
    if ([string]::IsNullOrWhiteSpace($thumbprint)) {
        throw "Empreinte de certificat introuvable dans la configuration."
    }
    
    Connect-AppAzureCert -TenantId $tenantId -ClientId $clientId -Thumbprint $thumbprint | Out-Null
    
    # RESOLUTION GLOBALE DU SITE SI AUTOPILOT
    if (-not [string]::IsNullOrWhiteSpace($AutoSiteUrl)) {
        Send-Progress 48 "Résolution de l'ID Graph du site cible..."
        $Global:SiteId = Get-AppGraphSiteId -SiteUrl $AutoSiteUrl
        if (-not $Global:SiteId) { throw "Impossible de résoudre le SiteId depuis l'URL : $AutoSiteUrl" }
    }

}
catch {
    [System.Windows.MessageBox]::Show("Erreur init : $($_.Exception.Message)", "Fatal", "OK", "Error"); exit 1
}

# 4. UI
Send-Progress 60 "Chargement de l'interface..."
try {
    $window = Import-AppXamlTemplate -XamlPath (Join-Path $scriptRoot "SharePointBuilderV2.xaml")
    Initialize-AppUIComponents -Window $window -ProjectRoot $projectRoot -Components 'Buttons', 'Inputs', 'Layouts', 'Display', 'ProfileButton', 'Navigation'

    # --- INJECTION DYNAMIQUE DES ONGLETS (TABS) ---
    $tabControl = $window.FindName("MainTabControl")
    if ($tabControl) {
        $tabsPath = Join-Path $scriptRoot "Templates\Tabs"
        if (Test-Path $tabsPath) {
            $tabFiles = Get-ChildItem -Path $tabsPath -Filter "Tab_*.xaml" | Sort-Object Name
            foreach ($tabFile in $tabFiles) {
                try {
                    $rawTabXaml = Get-Content $tabFile.FullName -Raw -Encoding UTF8
                    # Remplacement localisation
                    if ($rawTabXaml -match "##loc:(.+?)##") {
                        $rawTabXaml = [System.Text.RegularExpressions.Regex]::Replace($rawTabXaml, "##loc:(.+?)##", {
                            param($m) 
                            $k = $m.Groups[1].Value
                            if (Get-Command "Get-AppLocalizedString" -ErrorAction SilentlyContinue) {
                                return (Get-AppLocalizedString -Key $k)
                            }
                            return $k
                        })
                    }
                    [xml]$tabXml = $rawTabXaml
                    $tabReader = New-Object System.Xml.XmlNodeReader $tabXml
                    $tabItem = [System.Windows.Markup.XamlReader]::Load($tabReader)
                    if ($tabItem -is [System.Windows.Controls.TabItem]) {
                        $tabControl.Items.Add($tabItem) | Out-Null
                    }
                } catch {
                    Write-Warning "[Builder] Erreur chargement onglet $($tabFile.Name) : $($_.Exception.Message)"
                }
            }
        }
    }

    # Icône
    $imgBrush = $window.FindName("HeaderIconBrush")
    if ($imgBrush -and $manifest.icon) {
        $iconPath = Join-Path $projectRoot "Templates\Resources\Icons\PNG\$($manifest.icon.value)"
        if (Test-Path $iconPath) { $imgBrush.ImageSource = [System.Windows.Media.Imaging.BitmapImage]::new([Uri]$iconPath) }
    }

    Send-Progress 80 "Configuration visuelle..."

    # --- LOGIQUE MÉTIER (BuilderLogic) ---
    # On le place AVANT l'auth pour que les champs soient prêts si l'auth est rapide
    $builderLogicPath = Join-Path $scriptRoot "Functions\Initialize-BuilderLogic.ps1"
    if (Test-Path $builderLogicPath) {
        . $builderLogicPath
        $context = @{ 
            Window          = $window;
            ScriptRoot      = $scriptRoot;
            AutoSiteUrl     = $AutoSiteUrl;
            AutoLibraryName = $AutoLibraryName;
            AutoTemplateId  = $AutoTemplateId;
            AutoFormData    = $AutoFormData;
        }
        Initialize-BuilderLogic -Context $context
    }

    # --- GESTION DE L'IDENTITÉ (Standard v3.0) ---
    
    # Récupération de la config globale si les paramètres ne sont pas passés (Robustesse)
    if (-not $TenantId) { $TenantId = $Global:AppConfig.azure.tenantId }
    if (-not $ClientId) { $ClientId = $Global:AppConfig.azure.authentication.userAuth.appId }
    
    # A. Initialisation de l'identité
    $userIdentity = $null

    # PRIORITÉ 1: Nouvelle méthode Secure (UPN via Token Cache)
    if (-not [string]::IsNullOrWhiteSpace($AuthUPN)) {
        Write-Verbose "[Builder] AuthUPN reçu : $AuthUPN. Tentative de reprise de session..."
        try {
            $userIdentity = Connect-AppChildSession -AuthUPN $AuthUPN -TenantId $TenantId -ClientId $ClientId
            if (-not $userIdentity.Connected) {
                Write-Warning "[Builder] Connect-AppChildSession a retourné Connected=$false (Erreur: $($userIdentity.Error))"
            }
        }
        catch {
            Write-Warning "[Builder] Exception Auth Secure: $_" 
            $userIdentity = @{ Connected = $false }
        }
    } 
    # PRIORITÉ 2: Ancienne méthode (Fallback Legacy)
    elseif (-not [string]::IsNullOrWhiteSpace($AuthContext)) {
        Write-Verbose "[Builder] AuthContext Legacy détecté."
        try {
            $json = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($AuthContext))
            $rawObj = $json | ConvertFrom-Json
            $userIdentity = $rawObj.UserAuth 
        }
        catch { 
            Write-Warning "[Builder] Echec Auth Legacy: $_"
            $userIdentity = @{ Connected = $false } 
        }
    }
    else {
        # Aucune info -> Non connecté
        Write-Verbose "[Builder] Aucun contexte d'authentification initial."
        $userIdentity = @{ Connected = $false }
    }

    # Définition des actions pour le mode autonome
    $OnConnect = {
        # Chargement à la volée des configs si nécessaire (si non passé par Launcher)
        if (-not $Global:AppConfig) { $Global:AppConfig = Get-AppConfiguration -ProjectRoot $ProjectRoot }
        
        $newIdentity = Connect-AppAzureWithUser -AppId $Global:AppConfig.azure.authentication.userAuth.appId -TenantId $Global:AppConfig.azure.tenantId
        
        if (-not $newIdentity.Connected) {
            Write-Warning "[Builder] Authentification échouée ou annulée : $($newIdentity.ErrorMessage)"
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

    # Application Visuelle (Module UI)
    Set-AppWindowIdentity -Window $window -UserSession $userIdentity -LauncherPID $LauncherPID -OnConnect $OnConnect -OnDisconnect $OnDisconnect



}
catch {
    [System.Windows.MessageBox]::Show("Erreur UI : $($_.Exception.Message)", "Fatal", "OK", "Error")
    Unlock-AppScriptLock -OwnerPID $PID
    exit 1
}

# --- PROTECTION GLOBALE ANTI-CRASH ---
$window.Dispatcher.add_UnhandledException({
    param($sender, $e)
    # Empêche la propagation du crash vers ShowDialog
    $e.Handled = $true
    
    $crashMsg = "CRASH UI INTERCEPTÉ: $($e.Exception.Message) `n$($e.Exception.StackTrace)"
    Write-Warning $crashMsg
    
    # Tentative d'affichage dans la console interne si disponible
    $logBox = $window.FindName("LogRichTextBox")
    if ($logBox) {
        # On invoque le Write-AppLog délicatement, ou on ajoute du texte
        try {
            Write-AppLog -Message $crashMsg -Level Error -RichTextBox $logBox
        } catch {}
    }
})

# 5. SHOW
Send-Progress 100 "Prêt."
try {
    $window.ShowDialog() | Out-Null
}
finally {
    Unlock-AppScriptLock -OwnerPID $PID
}