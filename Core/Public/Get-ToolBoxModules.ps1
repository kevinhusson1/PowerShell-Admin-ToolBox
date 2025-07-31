<#
.SYNOPSIS
    Système d'auto-découverte et chargement des modules ToolBox

.DESCRIPTION
    Scanne le répertoire Modules/, charge les manifests .psd1 et valide
    les modules selon le pattern Show-Function avec XAML.

.NOTES
    Auteur: PowerShell Admin ToolBox Team
    Version: 1.0
    Création: 30 Juillet 2025
#>

# Variables pour le cache des modules (scope script local)
$Script:ToolBoxDiscoveredModules = $null

function Get-ToolBoxModules {
    <#
    .SYNOPSIS
        Découvre et retourne tous les modules ToolBox disponibles
    
    .DESCRIPTION
        Scanne le répertoire Modules/, valide les manifests et retourne
        la liste des modules conformes au standard ToolBox.
    
    .PARAMETER Force
        Force la redécouverte même si les modules sont déjà chargés en cache
    
    .PARAMETER ModulesPath
        Chemin personnalisé vers le répertoire des modules
    
    .EXAMPLE
        Get-ToolBoxModules
        
    .EXAMPLE
        Get-ToolBoxModules -Force
        
    .EXAMPLE
        Get-ToolBoxModules -ModulesPath "C:\Custom\Modules"
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [switch]$Force,
        
        [Parameter(Mandatory = $false)]
        [string]$ModulesPath
    )
    
    try {
        # Utilisation du cache si disponible et pas de force
        if ($Script:ToolBoxDiscoveredModules -and -not $Force) {
            Write-Verbose "Modules déjà découverts, utilisation du cache. Utilisez -Force pour redécouvrir."
            return $Script:ToolBoxDiscoveredModules
        }
        
        # Chargement du logger si disponible
        if (Get-Command Write-ToolBoxLog -ErrorAction SilentlyContinue) {
            Write-ToolBoxLog -Level "Debug" -Message "Début de la découverte des modules" -Component "ModuleDiscovery"
        }
        
        # Détermination du chemin des modules
        if (-not $ModulesPath) {
            $scriptRoot = $PSScriptRoot
            if (-not $scriptRoot) {
                $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
            }
            $rootPath = Split-Path -Parent $scriptRoot
            $ModulesPath = Join-Path $rootPath "Modules"
        }
        
        # Vérification de l'existence du répertoire Modules
        if (-not (Test-Path $ModulesPath)) {
            $warningMsg = "Répertoire Modules introuvable : $ModulesPath"
            Write-Warning $warningMsg
            if (Get-Command Write-ToolBoxLog -ErrorAction SilentlyContinue) {
                Write-ToolBoxLog -Level "Warning" -Message $warningMsg -Component "ModuleDiscovery" -Console $true -File $false -UI $false
            }
            return @()
        }
        
        Write-Verbose "Recherche des modules dans : $ModulesPath"
        
        # Découverte des modules
        $discoveredModules = @()
        $moduleDirectories = Get-ChildItem -Path $ModulesPath -Directory
        
        foreach ($moduleDir in $moduleDirectories) {
            $moduleInfo = Test-ToolBoxModule -ModulePath $moduleDir.FullName
            if ($moduleInfo) {
                $discoveredModules += $moduleInfo
            }
        }
        
        # Mise en cache des résultats
        $Script:ToolBoxDiscoveredModules = $discoveredModules
        
        # Logging des résultats
        $enabledCount = ($discoveredModules | Where-Object { $_.Enabled }).Count
        $totalCount = $discoveredModules.Count
        
        $summary = "Découverte terminée : $enabledCount/$totalCount modules activés"
        Write-Verbose $summary
        
        if (Get-Command Write-ToolBoxLog -ErrorAction SilentlyContinue) {
            Write-ToolBoxLog -Level "Info" -Message $summary -Component "ModuleDiscovery"
        }
        
        return $discoveredModules
    }
    catch {
        $errorMsg = "Erreur lors de la découverte des modules : $($_.Exception.Message)"
        Write-Error $errorMsg
        
        if (Get-Command Write-ToolBoxLog -ErrorAction SilentlyContinue) {
            Write-ToolBoxLog -Level "Error" -Message $errorMsg -Component "ModuleDiscovery"
        }
        
        return @()
    }
}

function Test-ToolBoxModule {
    <#
    .SYNOPSIS
        Valide qu'un module respecte le standard ToolBox
    
    .DESCRIPTION
        Vérifie la présence et la validité du manifest .psd1,
        de la fonction Show-ModuleName et du fichier XAML.
    
    .PARAMETER ModulePath
        Chemin vers le répertoire du module à valider
    
    .EXAMPLE
        Test-ToolBoxModule -ModulePath "C:\Modules\UserManagement"
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModulePath
    )
    
    try {
        $moduleName = Split-Path -Leaf $ModulePath
        Write-Verbose "Test du module : $moduleName"
        
        # 1. Vérification du manifest .psd1
        $manifestPath = Join-Path $ModulePath "$moduleName.psd1"
        if (-not (Test-Path $manifestPath)) {
            $warningMsg = "Manifest manquant pour le module $moduleName : $manifestPath"
            if (Get-Command Write-ToolBoxLog -ErrorAction SilentlyContinue) {
                Write-ToolBoxLog -Level "Warning" -Message $warningMsg -Component "ModuleDiscovery" -Console $true -UI $false
            } else {
                Write-Warning $warningMsg
            }
            return $null
        }
        
        # 2. Chargement et validation du manifest
        try {
            $manifest = Import-PowerShellDataFile -Path $manifestPath
        }
        catch {
            $errorMsg = "Erreur lors du chargement du manifest pour $moduleName : $($_.Exception.Message)"
            Write-Warning $errorMsg
            if (Get-Command Write-ToolBoxLog -ErrorAction SilentlyContinue) {
                Write-ToolBoxLog -Level "Warning" -Message $errorMsg -Component "ModuleDiscovery"
            }
            return $null
        }
        
        # 3. Vérification de la configuration ToolBox dans PrivateData
        $toolBoxConfig = $null
        if ($manifest.PrivateData -and $manifest.PrivateData.ToolBox) {
            $toolBoxConfig = $manifest.PrivateData.ToolBox
        } else {
            # Configuration par défaut si pas spécifiée
            $toolBoxConfig = @{
                Enabled = $true
                RequiredRoles = @('User')
                DisplayName = $moduleName
                Description = $manifest.Description
            }
        }
        
        # 4. Vérification de la fonction Show-ModuleName
        $showFunctionPath = Join-Path $ModulePath "Show-$moduleName.ps1"
        if (-not (Test-Path $showFunctionPath)) {
            $warningMsg = "Fonction Show-$moduleName.ps1 manquante pour le module $moduleName"
            Write-Warning $warningMsg
            if (Get-Command Write-ToolBoxLog -ErrorAction SilentlyContinue) {
                Write-ToolBoxLog -Level "Warning" -Message $warningMsg -Component "ModuleDiscovery"
            }
            return $null
        }
        
        # 5. Vérification du fichier XAML
        $xamlPath = Join-Path $ModulePath "$moduleName.xaml"
        if (-not (Test-Path $xamlPath)) {
            $warningMsg = "Fichier XAML manquant pour le module $moduleName : $xamlPath"
            Write-Warning $warningMsg
            if (Get-Command Write-ToolBoxLog -ErrorAction SilentlyContinue) {
                Write-ToolBoxLog -Level "Warning" -Message $warningMsg -Component "ModuleDiscovery"
            }
            return $null
        }
        
        # 6. Construction de l'objet module
        $moduleInfo = [PSCustomObject]@{
            Name = $moduleName
            Path = $ModulePath
            ManifestPath = $manifestPath
            ShowFunctionPath = $showFunctionPath
            XamlPath = $xamlPath
            Version = $manifest.ModuleVersion
            Author = $manifest.Author
            Description = $manifest.Description -or "Aucune description"
            Enabled = if ($toolBoxConfig.ContainsKey('Enabled')) { [bool]$toolBoxConfig.Item('Enabled') } else { $true }
            RequiredRoles = if ($toolBoxConfig.ContainsKey('RequiredRoles')) { $toolBoxConfig.Item('RequiredRoles') } else { @('User') }
            DisplayName = if ($toolBoxConfig.ContainsKey('DisplayName')) { $toolBoxConfig.Item('DisplayName') } else { $moduleName }
            Category = if ($toolBoxConfig.ContainsKey('Category')) { $toolBoxConfig.Item('Category') } else { "Général" }
            SortOrder = if ($toolBoxConfig.ContainsKey('SortOrder')) { [int]$toolBoxConfig.Item('SortOrder') } else { 999 }
            Manifest = $manifest
            ToolBoxConfig = $toolBoxConfig
        }
        
        $successMsg = "Module $moduleName validé avec succès (Enabled: $($moduleInfo.Enabled))"
        Write-Verbose $successMsg
        
        if (Get-Command Write-ToolBoxLog -ErrorAction SilentlyContinue) {
            Write-ToolBoxLog -Level "Debug" -Message $successMsg -Component "ModuleDiscovery"
        }
        
        return $moduleInfo
    }
    catch {
        $errorMsg = "Erreur lors de la validation du module $moduleName : $($_.Exception.Message)"
        Write-Warning $errorMsg
        
        if (Get-Command Write-ToolBoxLog -ErrorAction SilentlyContinue) {
            Write-ToolBoxLog -Level "Error" -Message $errorMsg -Component "ModuleDiscovery"
        }
        
        return $null
    }
}

function Invoke-ToolBoxModule {
    <#
    .SYNOPSIS
        Lance un module ToolBox spécifique
    
    .DESCRIPTION
        Charge et exécute la fonction Show-ModuleName d'un module validé.
    
    .PARAMETER ModuleName
        Nom du module à lancer
    
    .PARAMETER ModuleInfo
        Objet module retourné par Get-ToolBoxModules
    
    .EXAMPLE
        Invoke-ToolBoxModule -ModuleName "UserManagement"
        
    .EXAMPLE
        $module = Get-ToolBoxModules | Where-Object { $_.Name -eq "UserManagement" }
        Invoke-ToolBoxModule -ModuleInfo $module
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, ParameterSetName = 'ByName')]
        [string]$ModuleName,
        
        [Parameter(Mandatory = $false, ParameterSetName = 'ByObject')]
        [PSCustomObject]$ModuleInfo
    )
    
    try {
        # Récupération du module par nom si nécessaire
        if ($ModuleName) {
            $modules = Get-ToolBoxModules
            $ModuleInfo = $modules | Where-Object { $_.Name -eq $ModuleName }
            
            if (-not $ModuleInfo) {
                throw "Module '$ModuleName' introuvable"
            }
        }
        
        if (-not $ModuleInfo) {
            throw "Aucune information de module fournie"
        }
        
        # Vérification que le module est activé
        if (-not $ModuleInfo.Enabled) {
            $warningMsg = "Module $($ModuleInfo.Name) est désactivé"
            if (Get-Command Write-ToolBoxLog -ErrorAction SilentlyContinue) {
                Write-ToolBoxLog -Level "Warning" -Message $warningMsg -Component "ModuleDiscovery" -Console $true -File $false -UI $true
            } else {
                Write-Warning $warningMsg
            }
            return
        }
        
        # Chargement de la fonction Show-ModuleName
        if (Test-Path $ModuleInfo.ShowFunctionPath) {
            . $ModuleInfo.ShowFunctionPath
            
            $functionName = "Show-$($ModuleInfo.Name)"
            if (Get-Command $functionName -ErrorAction SilentlyContinue) {
                $launchMsg = "Lancement du module $($ModuleInfo.Name)"
                Write-Verbose $launchMsg
                
                if (Get-Command Write-ToolBoxLog -ErrorAction SilentlyContinue) {
                    Write-ToolBoxLog -Level "Info" -Message $launchMsg -Component "ModuleDiscovery"
                }
                
                # Exécution de la fonction
                & $functionName
            } else {
                throw "Fonction $functionName introuvable après chargement"
            }
        } else {
            throw "Fichier Show-Function introuvable : $($ModuleInfo.ShowFunctionPath)"
        }
    }
    catch {
        $errorMsg = "Erreur lors du lancement du module $($ModuleInfo.Name) : $($_.Exception.Message)"
        Write-Error $errorMsg
        
        if (Get-Command Write-ToolBoxLog -ErrorAction SilentlyContinue) {
            Write-ToolBoxLog -Level "Error" -Message $errorMsg -Component "ModuleDiscovery"
        }
    }
}

function Get-ToolBoxModulesByCategory {
    <#
    .SYNOPSIS
        Retourne les modules groupés par catégorie
    
    .DESCRIPTION
        Organise les modules découverts par catégorie pour affichage dans l'interface.
    
    .EXAMPLE
        Get-ToolBoxModulesByCategory
    #>
    
    [CmdletBinding()]
    param()
    
    $modules = Get-ToolBoxModules | Where-Object { $_.Enabled }
    
    $categorizedModules = $modules | Group-Object -Property Category | ForEach-Object {
        [PSCustomObject]@{
            Category = $_.Name
            Modules = ($_.Group | Sort-Object SortOrder, DisplayName)
        }
    } | Sort-Object Category
    
    return $categorizedModules
}

function Clear-ToolBoxModuleCache {
    <#
    .SYNOPSIS
        Vide le cache des modules découverts
    
    .DESCRIPTION
        Force la redécouverte des modules au prochain appel de Get-ToolBoxModules
    #>
    
    $Script:ToolBoxDiscoveredModules = $null
    Write-Verbose "Cache des modules vidé"
    
    if (Get-Command Write-ToolBoxLog -ErrorAction SilentlyContinue) {
        Write-ToolBoxLog -Level "Debug" -Message "Cache des modules vidé" -Component "ModuleDiscovery"
    }
}

function Show-ToolBoxModulesSummary {
    <#
    .SYNOPSIS
        Affiche un résumé des modules découverts
    
    .DESCRIPTION
        Fonction utilitaire pour afficher un résumé formaté des modules
    #>
    
    $modules = Get-ToolBoxModules
    
    Write-Host "`n=== MODULES TOOLBOX DÉCOUVERTS ===" -ForegroundColor Cyan
    Write-Host "Total : $($modules.Count) modules" -ForegroundColor Gray
    
    $enabledModules = $modules | Where-Object { $_.Enabled }
    $disabledModules = $modules | Where-Object { -not $_.Enabled }
    
    if ($enabledModules) {
        Write-Host "`n✅ MODULES ACTIVÉS ($($enabledModules.Count)) :" -ForegroundColor Green
        $enabledModules | Sort-Object Category, DisplayName | ForEach-Object {
            Write-Host "   [$($_.Category)] $($_.DisplayName) (v$($_.Version))" -ForegroundColor White
        }
    }
    
    if ($disabledModules) {
        Write-Host "`n❌ MODULES DÉSACTIVÉS ($($disabledModules.Count)) :" -ForegroundColor Red
        $disabledModules | Sort-Object Category, DisplayName | ForEach-Object {
            Write-Host "   [$($_.Category)] $($_.DisplayName) (v$($_.Version))" -ForegroundColor Gray
        }
    }
    
    Write-Host ""
}

# Les fonctions sont disponibles après dot-sourcing du script