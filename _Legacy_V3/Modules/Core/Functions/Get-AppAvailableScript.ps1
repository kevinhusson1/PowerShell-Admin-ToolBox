# Modules/Core/Functions/Get-AppAvailableScript.ps1

<#
.SYNOPSIS
    Scanne le dossier /Scripts pour trouver tous les manifestes de scripts disponibles.
.DESCRIPTION
    La fonction recherche de manière récursive tous les fichiers 'manifest.json'
    dans le dossier /Scripts. Pour chaque manifest trouvé, elle le lit, y ajoute
    le chemin du dossier du script, et le retourne sous forme d'une liste d'objets.
.PARAMETER ProjectRoot
    Le chemin racine du projet où se trouve le dossier /Scripts.
.OUTPUTS
    [System.Collections.Generic.List[psobject]] - Une liste d'objets, où chaque objet représente un script trouvé.
#>
function Get-AppAvailableScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot
    )

    $scriptsPath = Join-Path -Path $ProjectRoot -ChildPath "Scripts"
    if (-not (Test-Path $scriptsPath)) {
        $warningMsg = Get-AppText -Key 'modules.core.scripts_folder_not_found'
        Write-Warning "$warningMsg : $scriptsPath"

        # Retourner un tableau vide
        return @() 
    }

    # 1. Créer une liste vide et typée.
    $scriptList = [System.Collections.Generic.List[psobject]]::new()

    # 2. Chercher tous les fichiers manifest.json
    $manifestFiles = Get-ChildItem -Path $scriptsPath -Recurse -Filter "manifest.json"

    # 3. Boucler sur chaque fichier trouvé
    foreach ($manifestFile in $manifestFiles) {
        try {
            # Lire et convertir le manifest
            $scriptManifest = Get-Content -Path $manifestFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            
            # Ajouter le chemin du script à l'objet pour une utilisation future
            $scriptManifest | Add-Member -MemberType NoteProperty -Name 'ScriptPath' -Value (Split-Path -Path $manifestFile.FullName -Parent)

            # 4. Ajouter l'objet traité à notre liste
            $scriptList.Add($scriptManifest)
        }
        catch {
            $warningMsg = Get-AppText -Key 'modules.core.manifest_parse_error'
            Write-Warning "$warningMsg '$($manifestFile.FullName)'. Erreur : $($_.Exception.Message)"
        }
    }

    return $scriptList
}