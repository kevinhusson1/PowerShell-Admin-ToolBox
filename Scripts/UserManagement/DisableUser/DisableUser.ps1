#Requires -Version 5.1

# ... (Synopsis, Description, etc.)

param(
    # Le SessionId est maintenant optionnel
    [string]$SessionId
)

# Définir les chemins de base
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = (Get-Item $scriptRoot).Parent.Parent.Parent.FullName # Méthode plus robuste

# On met TOUT le script dans un bloc try/finally
try {
    # =====================================================================
    # 1. IMPORTATION DES MODULES (TOUJOURS EXÉCUTÉ)
    # =====================================================================
    #region Imports
    try {
        Import-Module "$projectRoot\Modules\Core" -Force
        Import-Module "$projectRoot\Modules\UI" -Force
        Import-Module "$projectRoot\Modules\Localization" -Force
    } catch {
        [System.Windows.MessageBox]::Show("Erreur critique lors de l'import des modules : $($_.Exception.Message)", "Erreur de Démarrage", "OK", "Error")
        exit 1
    }
    #endregion
    # =====================================================================

    # =====================================================================
    # 2. GESTION DU CONTEXTE (Chargement des données)
    # =====================================================================
    #region Contexte
    try {
        # MODE DIRECT / DÉVELOPPEMENT
        if ([string]::IsNullOrWhiteSpace($SessionId)) {
            # Importer le module Core manuellement pour accéder à la fonction de dev
            Import-Module "$projectRoot\Modules\Core" -Force
            # Appeler la fonction qui construit tout le contexte pour nous
            Initialize-AppDevSession -ProjectRoot $projectRoot
        } 
        # MODE LAUNCHER / PRODUCTION
        else {
            # --- C'EST ICI QUE NOUS AJOUTONS LA LOGIQUE ---
            Write-Verbose "[PROD] Démarrage en mode Launcher avec SessionId: $SessionId"
            
            # 1. Importer les modules nécessaires
            Import-Module "$projectRoot\Modules\Core" -Force
            Import-Module "$projectRoot\Modules\UI" -Force
            Import-Module "$projectRoot\Modules\Localization" -Force
            # (Ajoutez Azure, Logging, etc. quand ils seront utilisés)

            # 2. Restaurer le contexte depuis le fichier de session
            $sessionFile = "$projectRoot\Logs\.sessions\$SessionId.json"
            if (-not (Test-Path $sessionFile)) {
                throw "Fichier de session introuvable : $SessionId. Le script ne peut pas démarrer."
            }
            $sessionData = Get-Content $sessionFile -Raw | ConvertFrom-Json
            
            # 3. Appliquer le contexte restauré aux variables globales
            $Global:AppConfig = $sessionData.config
            # $Global:AppAzureAuth = $sessionData.azureAuth # Pour le futur

            # 4. Initialiser la localisation avec la langue fournie par le lanceur
            Initialize-AppLocalization -Language $Global:AppConfig.defaultLanguage

            # 5. Fusionner les traductions spécifiques au script (si elles existent)
            $scriptLangFile = "$scriptRoot\Localization\$($Global:AppConfig.language).json"
            if(Test-Path $scriptLangFile){
                Add-AppLocalizationSource -FilePath $scriptLangFile
            }
        }
    }
    catch {
        [System.Windows.MessageBox]::Show("Erreur critique lors de l'initialisation du contexte : $($_.Exception.Message)", "Erreur", "OK", "Error")
        exit 1
    }
    #endregion
    # =====================================================================

    #region Initialisation logging
    # ... (le reste du script ne change pas)
    #endregion

    # =====================================================================
    # CHARGEMENT DE L'INTERFACE (XAML)
    # =====================================================================
    #region Chargement XAML
    try {
        # On définit le chemin vers notre nouveau fichier XAML
        $xamlPath = Join-Path -Path $scriptRoot -ChildPath "DisableUser.xaml"
        
        # On charge le XAML. C'EST ICI QUE LA VARIABLE $window EST CRÉÉE.
        $window = Import-AppXamlTemplate -XamlPath $xamlPath
        
        # Ici, on récupérera les contrôles (boutons, etc.) plus tard
        # $btnExecute = $window.FindName("btnExecute")

    } catch {
        [System.Windows.MessageBox]::Show("Erreur critique lors du chargement de l'interface du script : $($_.Exception.Message)", "Erreur XAML", "OK", "Error")
        exit 1
    }
    #endregion
    # =====================================================================


    # =====================================================================
    # GESTION DES ÉVÉNEMENTS DE L'UI
    # =====================================================================
    #region Event handlers

    # Maintenant que $window existe, on peut lui attacher des événements sans erreur.
    $window.Add_Closing({
        # Nettoyer le fichier de session avant de fermer
        $sessionFile = "$projectRoot\Logs\.sessions\$SessionId.json"
        if (-not [string]::IsNullOrWhiteSpace($SessionId) -and (Test-Path $sessionFile)) {
            Remove-Item $sessionFile -Force -ErrorAction SilentlyContinue
            Write-Verbose "Fichier de session '$SessionId.json' nettoyé."
        }
    })

    # Ici on ajoutera les Add_Click pour les boutons
    # $btnExecute.Add_Click({ ... })

    #endregion
    # =====================================================================

    # =====================================================================
    # AFFICHAGE DE LA FENÊTRE
    # =====================================================================
    $window.ShowDialog() | Out-Null

    Write-Verbose "Le script CreateUser a été fermé."

} catch {
    # Si quoi que ce soit échoue, cette boîte de dialogue s'affichera
    [System.Windows.MessageBox]::Show("Une erreur fatale est survenue :`n$($_.Exception.Message)`n$($_.ScriptStackTrace)", "Erreur Script Enfant", "OK", "Error")
}