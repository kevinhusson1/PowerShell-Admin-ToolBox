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
        [Parameter(Mandatory)]
        [string]$ProjectRoot
    )

    # Fonction d'aide interne pour les icônes (Inchangée)
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
        $allManifests = Get-AppAvailableScript -ProjectRoot $ProjectRoot
        $adminGroup = $Global:AppConfig.security.adminGroupName

        # --- A. SYNCHRONISATION BDD ---
        foreach ($m in $allManifests) {
            Sync-AppScriptSettings -ScriptId $m.id -AdminGroupName $adminGroup
        }

        # --- B. CHARGEMENT DES DONNÉES BDD ---
        $securityMap = Get-AppScriptSecurity      # Table de liaison Groupes
        $settingsMap = Get-AppScriptSettingsMap   # Table des paramètres (Enabled, MaxRuns)

        $userGroups = @()
        if ($Global:AppAzureAuth.UserAuth.Connected) {
            $userGroups = Get-AppUserAzureGroups
        }

        $enrichedScripts = [System.Collections.Generic.List[psobject]]::new()
        $iconFolderPath = Join-Path -Path $ProjectRoot -ChildPath "Templates\Resources\Icons\PNG"

        foreach ($manifest in $allManifests) {
            if (-not ($manifest.id -and $manifest.scriptFile)) { continue }

            # Récupération des paramètres BDD
            $dbSettings = $settingsMap[$manifest.id]
            
            # Valeurs par défaut si la BDD a raté (fallback)
            $isEnabled = if ($dbSettings) { $dbSettings.IsEnabled } else { $true }
            $maxRuns   = if ($dbSettings) { $dbSettings.MaxConcurrentRuns } else { 1 }

            # 2. FILTRAGE SÉCURITÉ
            $isAllowed = $false
            $allowedGroupsDb = $securityMap[$manifest.id]

            # Si aucun groupe en BDD => Accès restreint par défaut (ou public selon politique).
            # Avec notre Sync, il y a toujours au moins le groupe Admin.
            if ($null -eq $allowedGroupsDb -or $allowedGroupsDb.Count -eq 0) {
                # Cas orphelin : on masque par sécurité
                $isAllowed = $false 
            }
            elseif ($Global:AppAzureAuth.UserAuth.Connected) {
                foreach ($requiredGroup in $allowedGroupsDb) {
                    if ($userGroups -contains $requiredGroup) {
                        $isAllowed = $true
                        break
                    }
                }
            }
            
            if (-not $isAllowed) { continue }

            # 3. CONSTRUCTION
            # On utilise les variables $maxRuns issue de la BDD
            # On ignore ce qui vient du JSON pour 'enabled' et 'maxConcurrentRuns'
            
            try {
                $scriptObj = [PSCustomObject]@{
                    id                  = $manifest.id
                    scriptFile          = $manifest.scriptFile
                    lockFile            = $manifest.lockFile
                    name                = Get-AppText -Key $manifest.name
                    description         = Get-AppText -Key $manifest.description
                    ScriptPath          = $manifest.ScriptPath
                    version             = $manifest.version
                    
                    # PROPRIÉTÉS BDD
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
            } catch { Write-Warning "Erreur construct : $_" }
        }
        
        return $enrichedScripts
    }
    catch { return @() }
}