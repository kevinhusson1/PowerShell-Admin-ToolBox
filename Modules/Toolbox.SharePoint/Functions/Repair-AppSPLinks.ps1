# Modules/Toolbox.SharePoint/Functions/Repair-AppSPLinks.ps1

<#
.SYNOPSIS
    Répare les liens (.url) cassés à l'intérieur d'un dossier renommé.

.DESCRIPTION
    Scanne récursivement un dossier racine pour trouver tous les fichiers .url.
    Pour chaque lien, vérifie si sa cible pointe vers l'ancien chemin (OldRootUrl).
    Si oui, met à jour la cible vers le nouveau chemin (NewRootUrl).

.PARAMETER RootFolderUrl
    Chemin (ServerRelative) du dossier racine où effectuer le scan (ex: /sites/x/Lib/NewName).

.PARAMETER OldRootUrl
    L'ancien chemin (ServerRelative) qui n'est plus valide (ex: /sites/x/Lib/OldName).

.PARAMETER NewRootUrl
    Le nouveau chemin valide (ex: /sites/x/Lib/NewName).

.PARAMETER Connection
    Connexion PnP SharePoint active.

.OUTPUTS
    [Hashtable] { Success, ProcessedCount, FixedCount, Errors }
#>
function Repair-AppSPLinks {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$RootFolderUrl,
        [Parameter(Mandatory)] [string]$OldRootUrl,
        [Parameter(Mandatory)] [string]$NewRootUrl,
        [Parameter(Mandatory)] [PnP.PowerShell.Commands.Base.PnPConnection]$Connection
    )

    $result = @{ Success = $true; ProcessedCount = 0; FixedCount = 0; Errors = [System.Collections.Generic.List[string]]::new() }
    
    # Nettoyage des URLs pour comparaison (Trim slash final)
    $cleanOld = $OldRootUrl.TrimEnd('/')
    $cleanNew = $NewRootUrl.TrimEnd('/')

    Write-Verbose "[Repair] Scan started on '$RootFolderUrl'. Target: Replace '$cleanOld' -> '$cleanNew'"

    try {
        # 1. Scan Récursif : Trouver tous les .url
        # On utilise Get-PnPFileInFolder (ou equivalent) via CAML Query ou Get-PnPListItem recursif
        # La méthode la plus fiable en PnP est Get-PnPListItem avec requête CAML pour FileRef like .url
        
        # Récupération de la liste parente via URL (un peu hacky mais universel)
        # On assume que RootFolderUrl est dans une Lib
        # On va plutôt utiliser 'Get-PnPFolderItem' récursif ? Non, lourd.
        # Utilisons Get-PnPListItem sur la lib entière et filtrons par Path.
        
        # (Optimisation V1 : Scan Simple via Get-PnPFolderItem mais ça ne retourne pas le contenu fichier)
        # Meilleure approche : Get-PnPListItem sur toute la liste, filter where FileRef startswith NewFolder AND FileRef endswith .url
        
        # Trouver la liste
        # Pour faire simple, on demande à l'utilisateur de passer le ListItem, mais ici on a juste l'URL.
        # On va tenter de résoudre la liste.
        
        # Alternative : Lister tous les fichiers du dossier
        # Get-PnPFolderItem -FolderSiteRelativeUrl ... -ItemType File -Recursive
        
        $items = Get-PnPFolderItem -FolderServerRelativeUrl $RootFolderUrl -ItemType File -Recursive -Connection $Connection -ErrorAction Stop
        
        foreach ($file in $items) {
            try {
                if ($file.Name -like "*.url") {
                    $result.ProcessedCount++
                    $fileUrl = $file.ServerRelativeUrl
                    
                    try {
                        # 2. Lire le contenu du fichier .url
                        $content = Get-PnPFile -Url $fileUrl -AsString -Connection $Connection -ErrorAction Stop
                        
                        if ($content -match "URL=(.+)") {
                            $currentTarget = $matches[1].Trim()
                            
                            if ($currentTarget.StartsWith($cleanOld, [System.StringComparison]::InvariantCultureIgnoreCase)) {
                                $newTarget = $currentTarget -replace [regex]::Escape($cleanOld), $cleanNew
                                $newContent = $content -replace "URL=.+", "URL=$newTarget"
                                
                                $stream = [System.IO.MemoryStream]::new([System.Text.Encoding]::UTF8.GetBytes($newContent))
                                $parentFolder = $fileUrl.Substring(0, $fileUrl.LastIndexOf('/'))
                                
                                Add-PnPFile -Folder $parentFolder -FileName $file.Name -Stream $stream -Connection $Connection -ErrorAction Stop | Out-Null
                                
                                $result.FixedCount++
                                Write-Verbose "[Repair] Fixed '$($file.Name)' -> $newTarget"
                            }
                        }
                    }
                    catch {
                        $err = "Erreur lecture/écriture fichier '$($file.Name)': $_"
                        Write-Warning $err
                        $result.Errors.Add($err)
                    }
                }
            }
            catch [Microsoft.SharePoint.Client.PropertyOrFieldNotInitializedException] {
                # Ignore this specific error as it often triggers on 'Title' access for some file types/views
                Write-Verbose "Ignored 'Title' initialization error on item."
            }
            catch {
                Write-Warning "Error processing item: $_"
            }
        }
    
    }
    catch {
        $result.Success = $false
        $result.Errors.Add("Erreur globale : $($_.Exception.Message)")
    }

    return $result
}
