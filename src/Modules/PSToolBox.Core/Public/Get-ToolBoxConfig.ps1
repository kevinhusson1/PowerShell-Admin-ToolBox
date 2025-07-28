<#
.SYNOPSIS
    Récupère la configuration de l'application depuis le fichier settings.user.json.
.DESCRIPTION
    Cette fonction gère la lecture de la configuration utilisateur.
    Au premier appel, elle vérifie si le fichier de configuration existe dans %APPDATA%\PSToolBox.
    S'il n'existe pas, elle le crée à partir du template fourni avec l'application.
    Les appels suivants retournent une version mise en cache pour des raisons de performance.
.OUTPUTS
    PSCustomObject - Un objet contenant tous les paramètres de configuration.
.NOTES
    Cette fonction est un pilier du module Core.
#>
function Get-ToolBoxConfig {
    # Utiliser une variable de portée "script" pour mettre en cache la configuration.
    # Cela évite de lire le fichier sur le disque à chaque appel.
    if ($script:cachedConfig) {
        return $script:cachedConfig
    }

    try {
        # Définir les chemins de manière robuste
        $appDataPath = Join-Path $env:APPDATA "PSToolBox"
        $configFilePath = Join-Path $appDataPath "settings.user.json"

        # Le chemin du template est relatif à la position du module, pas du script qui l'appelle
        $moduleRoot = (Get-Module PSToolBox.Core).ModuleBase
        $templatePath = Join-Path $moduleRoot "../../Config/settings.template.json" # Remonte de Core -> Modules -> src
        $templatePath = [System.IO.Path]::GetFullPath($templatePath)

        # Étape 1 : S'assurer que le dossier de configuration existe
        if (-not (Test-Path $appDataPath)) {
            Write-Verbose "Création du dossier de configuration : $appDataPath"
            New-Item -Path $appDataPath -ItemType Directory -Force | Out-Null
        }

        # Étape 2 : S'assurer que le fichier de configuration existe, sinon le créer depuis le template
        if (-not (Test-Path $configFilePath)) {
            Write-Verbose "Fichier de configuration non trouvé. Copie depuis le template : $templatePath"
            if (-not (Test-Path $templatePath)) {
                throw "Le fichier template 'settings.template.json' est introuvable à l'emplacement attendu : $templatePath"
            }
            Copy-Item -Path $templatePath -Destination $configFilePath -Force
        }

        # Étape 3 : Lire et parser le fichier de configuration
        Write-Verbose "Lecture du fichier de configuration : $configFilePath"
        $configContent = Get-Content -Path $configFilePath -Raw
        $configObject = $configContent | ConvertFrom-Json

        # Étape 4 : Mettre en cache et retourner le résultat
        $script:cachedConfig = $configObject
        return $script:cachedConfig

    } catch {
        $errorMessage = "Erreur critique lors du chargement de la configuration : $($_.Exception.Message)"
        # Dans une application graphique, on afficherait une MessageBox. Pour l'instant, on lève une exception.
        throw $errorMessage
    }
}