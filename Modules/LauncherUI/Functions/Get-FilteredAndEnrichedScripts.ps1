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

    # --- Fonction d'aide interne pour créer les icônes ---
    # En la définissant ici, elle n'est visible que par Get-FilteredAndEnrichedScripts
    function New-ScriptIcon {
        param($manifest, $iconFolderPath)
        
        if (-not ($manifest.icon -and $manifest.icon.type -eq 'png' -and -not [string]::IsNullOrEmpty($manifest.icon.value))) {
            return $null
        }
        
        $iconFullPath = Join-Path -Path $iconFolderPath -ChildPath $manifest.icon.value
        if (Test-Path $iconFullPath) {
            try {
                $bitmap = [System.Windows.Media.Imaging.BitmapImage]::new()
                $bitmap.BeginInit()
                $bitmap.UriSource = [System.Uri]::new($iconFullPath, [System.UriKind]::Absolute)
                $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
                $bitmap.EndInit()
                $bitmap.Freeze() # Important pour la performance et le multi-threading
                return $bitmap
            } catch {
                Write-Warning "Impossible de charger l'image d'icône '$iconFullPath'."
                return $null
            }
        }
        return $null
    }
    # ----------------------------------------------------

    try {
        # --- 1. RÉCUPÉRATION DES DONNÉES BRUTES ---
        $allManifests = Get-AppAvailableScript -ProjectRoot $ProjectRoot
        
        $userGroups = @()
        if ($Global:AppAzureAuth.UserAuth.Connected) {
            $userGroups = Get-AppUserAzureGroups
            Write-Verbose (("{0} : {1}" -f (Get-AppText 'modules.launcherui.user_groups'), ($userGroups -join ', ')))
        }

        # --- 2. FILTRAGE DES SCRIPTS ---
        $allowedManifests = @(foreach ($manifest in $allManifests) {
            $isAllowed = $false
            # Cas 1 : Mode Système, on voit tout
            if (-not $Global:AppAzureAuth.UserAuth.Connected) {
                $isAllowed = $true
            } 
            # Cas 2 : Le script n'a pas de restriction
            elseif (-not ($manifest.PSObject.Properties['security'] -and $manifest.security.allowedADGroups)) {
                $isAllowed = $true
            }
            # Cas 3 : Le script a des restrictions, on vérifie les groupes
            else {
                foreach ($requiredGroup in $manifest.security.allowedADGroups) {
                    if (($userGroups | ForEach-Object { $_.Trim() }) -contains $requiredGroup.Trim()) {
                        $isAllowed = $true
                        break
                    }
                }
            }
            
            if ($isAllowed) { $manifest }
        })

        $logMsg = "{0} {1} {2} {3}." -f $allowedManifests.Count, (Get-AppText 'modules.launcherui.scripts_authorized_1'), $allManifests.Count, (Get-AppText 'modules.launcherui.scripts_authorized_2')
        Write-Verbose $logMsg

        # --- 3. ENRICHISSEMENT DES SCRIPTS FILTRÉS ---
        $iconFolderPath = Join-Path -Path $ProjectRoot -ChildPath "Templates\Resources\Icons\PNG"
        
        $enrichedScripts = @(foreach ($manifest in $allowedManifests) {
            # On vérifie la présence des propriétés obligatoires du manifeste
            if (-not ($manifest.id -and $manifest.scriptFile -and $manifest.name)) {
                Write-Warning (("{0} '{1}' {2}" -f (Get-AppText 'modules.launcherui.manifest_incomplete_1'), $manifest.PSPath, (Get-AppText 'modules.launcherui.manifest_incomplete_2')))
                continue # On ignore ce manifeste corrompu
            }

            [PSCustomObject]@{
                id                  = $manifest.id
                scriptFile          = $manifest.scriptFile
                lockFile            = $manifest.lockFile
                name                = Get-AppText -Key $manifest.name
                description         = Get-AppText -Key $manifest.description
                ScriptPath          = $manifest.ScriptPath
                version             = $manifest.version
                enabled             = if ($manifest.PSObject.Properties['enabled']) { $manifest.enabled } else { $true }
                IsRunning           = $false
                pid                 = $null
                sessionId           = $null
                IconSource          = New-ScriptIcon -manifest $manifest -iconFolderPath $iconFolderPath
                IconBackgroundColor = $manifest.icon.backgroundColor
                requiredPermissions = $manifest.requiredPermissions
                maxConcurrentRuns   = if ($manifest.PSObject.Properties['maxConcurrentRuns']) { $manifest.maxConcurrentRuns } else { 1 }
            }
        })
        
        return $enrichedScripts
    }
    catch {
        $errorMsg = Get-AppText -Key 'modules.launcherui.scan_filter_error'
        [System.Windows.MessageBox]::Show("$errorMsg :`n$($_.Exception.Message)", "Erreur de Données", "OK", "Error")
        return @() 
    }
}