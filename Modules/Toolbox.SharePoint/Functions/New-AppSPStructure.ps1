function New-AppSPStructure {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$TargetSiteUrl,
        [Parameter(Mandatory)] [string]$TargetLibraryName,
        [Parameter(Mandatory)] [string]$RootFolderName,
        [Parameter(Mandatory)] [string]$StructureJson,
        [Parameter(Mandatory)] [string]$ClientId
    )

    $result = @{
        Success = $true
        Logs = [System.Collections.Generic.List[string]]::new()
        Errors = [System.Collections.Generic.List[string]]::new()
    }

    # Fonction locale de log pour le rapport de fin
    function Log { param($m) $result.Logs.Add("[$(Get-Date -Format 'HH:mm:ss')] $m") }
    function Err { param($m) $result.Errors.Add($m); $result.Success = $false }

    try {
        Log "Connexion au site : $TargetSiteUrl"
        
        # On utilise le mode Interactif pour bénéficier du cache token chaud du Job d'auth
        # C'est la magie du SSO Windows
        Connect-PnPOnline -Url $TargetSiteUrl -ClientId $ClientId -Interactive -ErrorAction Stop

        # 1. Vérification / Création Racine
        $targetLib = Get-PnPList -Identity $TargetLibraryName -Includes RootFolder
        $libUrl = $targetLib.RootFolder.ServerRelativeUrl
        
        Log "Cible : $libUrl/$RootFolderName"
        
        # On tente de créer le dossier racine
        # Resolve-PnPFolder est génial car il crée tout le chemin s'il manque et renvoie l'objet dossier
        $rootFolder = Resolve-PnPFolder -SiteRelativePath "$libUrl/$RootFolderName"
        Log "Dossier racine validé."

        # 2. Parsing du JSON
        $structure = $StructureJson | ConvertFrom-Json
        
        # 3. Fonction Récursive de Création
        function Process-Folder {
            param($CurrentPath, $FolderObj)

            # A. Création du dossier physique
            $folderName = $FolderObj.Name
            $fullPath = "$CurrentPath/$folderName"
            Log "Traitement : $fullPath"
            
            Resolve-PnPFolder -SiteRelativePath $fullPath | Out-Null

            # B. Traitement des sous-dossiers
            if ($FolderObj.Folders) {
                foreach ($sub in $FolderObj.Folders) {
                    Process-Folder -CurrentPath $fullPath -FolderObj $sub
                }
            }
            
            # C. TODO: Permissions & Tags (Prochaine étape)
        }

        # Lancement de la récursion
        if ($structure.Root.Folders) {
            foreach ($f in $structure.Root.Folders) {
                Process-Folder -CurrentPath "$libUrl/$RootFolderName" -FolderObj $f
            }
        }

        Log "Déploiement terminé."

    } catch {
        Err "ERREUR CRITIQUE : $($_.Exception.Message)"
    }

    return $result
}