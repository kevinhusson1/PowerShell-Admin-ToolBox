# Modules/LauncherUI/Functions/Get-FilteredAndEnrichedScripts.ps1

<#
.SYNOPSIS
    Récupère, filtre et enrichit la liste de tous les scripts disponibles pour l'affichage.
.DESCRIPTION
    Cette fonction est au cœur du lanceur. Elle effectue les opérations suivantes :
    1. Scanne le disque pour trouver tous les manifestes de scripts.
    2. Récupère les groupes Azure de l'utilisateur s'il est connecté.
    3. Filtre la liste des scripts pour ne garder que ceux auxquels l'utilisateur a droit.
    4. Enrichit chaque script restant avec des données prêtes pour l'affichage (icônes, traductions).
.PARAMETER ProjectRoot
    Le chemin racine du projet.
.OUTPUTS
    [System.Array] - Un tableau d'objets PSCustomObject représentant les scripts prêts à être affichés.
#>
function Get-FilteredAndEnrichedScripts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$ProjectRoot,
        [Parameter(Mandatory=$false)] [array]$UserGroups = @()
    )

    # --- Helper: Chargement Icône ---
    function New-ScriptIcon {
        param($manifest, $iconFolderPath)
        if (-not ($manifest.icon -and $manifest.icon.type -eq 'png' -and -not [string]::IsNullOrEmpty($manifest.icon.value))) { return $null }
        $iconFullPath = Join-Path -Path $iconFolderPath -ChildPath $manifest.icon.value
        if (Test-Path $iconFullPath) {
            try {
                $bitmap = [System.Windows.Media.Imaging.BitmapImage]::new()
                $bitmap.BeginInit()
                $bitmap.UriSource = [System.Uri]::new($iconFullPath, [System.UriKind]::Absolute)
                $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
                $bitmap.EndInit()
                $bitmap.Freeze()
                return $bitmap
            } catch { return $null }
        }
        return $null
    }

    try {
        Write-Verbose "[Loader] Scan des manifestes..."
        $allManifests = Get-AppAvailableScript -ProjectRoot $ProjectRoot
        $adminGroup = $Global:AppConfig.security.adminGroupName

        # --- Synchro BDD (Sécurisée) ---
        $timerWasRunning = $false
        if ($Global:uiTimer -and $Global:uiTimer.IsEnabled) {
            $Global:uiTimer.Stop(); $timerWasRunning = $true
        }
        try {
            foreach ($m in $allManifests) { Sync-AppScriptSettings -ScriptId $m.id -AdminGroupName $adminGroup }
        } finally {
            if ($timerWasRunning) { $Global:uiTimer.Start() }
        }

        # --- Maps ---
        $securityMap = Get-AppScriptSecurity
        $settingsMap = Get-AppScriptSettingsMap
        $enrichedScripts = [System.Collections.Generic.List[psobject]]::new()
        $iconFolderPath = Join-Path -Path $ProjectRoot -ChildPath "Templates\Resources\Icons\PNG"
        $currentLang = $Global:AppConfig.defaultLanguage

        foreach ($manifest in $allManifests) {
            if (-not ($manifest.id -and $manifest.scriptFile)) { continue }

            # 1. CHARGEMENT LOCALIZATION AUTOMATIQUE (Le "Blindage")
            # On cherche si le script a son propre fichier de langue et on l'injecte MAINTENANT.
            # Cela permet à Get-AppText de trouver les clés 'scripts.monscript.name' immédiatement.
            $localLangFile = Join-Path $manifest.ScriptPath "Localization\$currentLang.json"
            if (Test-Path $localLangFile) {
                Add-AppLocalizationSource -FilePath $localLangFile
            }

            # 2. Paramètres & Sécurité
            $dbSettings = $settingsMap[$manifest.id]
            $isEnabled = if ($dbSettings) { $dbSettings.IsEnabled } else { $true }
            $maxRuns   = if ($dbSettings) { $dbSettings.MaxConcurrentRuns } else { 1 }

            $isAllowed = $false
            $allowedGroupsDb = $securityMap[$manifest.id]

            if ($null -eq $allowedGroupsDb -or $allowedGroupsDb.Count -eq 0) { $isAllowed = $false }
            elseif ($Global:AppAzureAuth.UserAuth.Connected) {
                foreach ($requiredGroup in $allowedGroupsDb) {
                    if ($UserGroups -contains $requiredGroup) { $isAllowed = $true; break }
                }
            }
            if (-not $isAllowed) { continue }

            # 3. Construction
            try {
                # Tentative de traduction sécurisée
                # Si la clé n'existe pas, Get-AppText renvoie "[Clé]", ce qui est moche mais ne plante pas.
                # Optionnel : On peut ajouter une logique ici pour utiliser le nom technique si la traduction échoue.
                $tName = Get-AppText -Key $manifest.name
                $tDesc = Get-AppText -Key $manifest.description

                $scriptObj = [PSCustomObject]@{
                    id                  = $manifest.id
                    scriptFile          = $manifest.scriptFile
                    lockFile            = $manifest.lockFile
                    name                = $tName
                    description         = $tDesc
                    ScriptPath          = $manifest.ScriptPath
                    version             = $manifest.version
                    enabled             = $isEnabled
                    maxConcurrentRuns   = $maxRuns
                    IsRunning           = $false
                    pid                 = $null
                    IconSource          = New-ScriptIcon -manifest $manifest -iconFolderPath $iconFolderPath
                    IconBackgroundColor = if ($manifest.icon.backgroundColor) { $manifest.icon.backgroundColor } else { "#cccccc" }
                    IsLoading           = $false
                    LoadingProgress     = 0
                    LoadingStatus       = ""
                }
                $enrichedScripts.Add($scriptObj)
            } catch { Write-Warning "Erreur construct script '$($manifest.id)': $_" }
        }
        
        return $enrichedScripts
    }
    catch { Write-Error "[Loader] ERREUR CRITIQUE : $_"; return @() }
}