# Modules/Toolbox.SharePoint/Functions/Rename-AppSPFolder.ps1

<#
.SYNOPSIS
    Renomme un dossier SharePoint racine et met à jour ses métadonnées.

.DESCRIPTION
    Cette fonction réalise une opération atomique de maintenance :
    1. Renommage du dossier via FileLeafRef (si le nom a changé).
    2. Mise à jour des champs de métadonnées (ListItemAllFields).
    
    Elle ne gère pas la réparation des liens (voir Repair-AppSPLinks).

.PARAMETER TargetFolderUrl
    L'URL ServerRelative du dossier à renommer (ex: /sites/mysite/Shared Documents/OldName).

.PARAMETER NewFolderName
    Le nouveau nom souhaité pour le dossier.

.PARAMETER Metadata
    Hashtable contenant les nouvelles valeurs des colonnes (Clé = InternalName, Valeur = Valeur).

.PARAMETER Connection
    Connexion PnP SharePoint active (déjà authentifiée).

.OUTPUTS
    [Hashtable] { Success, Message, NewUrl }
#>
function Rename-AppSPFolder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$TargetFolderUrl,
        [Parameter(Mandatory)] [string]$NewFolderName,
        [Parameter(Mandatory = $false)] [hashtable]$Metadata,
        [Parameter(Mandatory)] [PnP.PowerShell.Commands.Base.PnPConnection]$Connection
    )

    $result = @{ Success = $true; Message = ""; NewUrl = "" }

    try {
        Write-Verbose "[Rename] Cible : $TargetFolderUrl"
        
        # 1. Récupération Item with explicit ParentList loading to avoid "Property not initialized"
        $folder = Get-PnPFolder -Url $TargetFolderUrl -Includes ListItemAllFields.ParentList, ListItemAllFields.Id, ServerRelativeUrl -Connection $Connection -ErrorAction Stop
        if (-not $folder) { throw "Dossier introuvable : $TargetFolderUrl" }
        
        $item = $folder.ListItemAllFields
        if (-not $item) { throw "Impossible d'accéder aux métadonnées (ListItem) du dossier." }

        # 2. Renommage (Si nécessaire)
        $currentName = $folder.Name
        $finalUrl = $folder.ServerRelativeUrl
        
        if ($currentName -ne $NewFolderName) {
            Write-Verbose "[Rename] Changement nom : '$currentName' -> '$NewFolderName'"
            
            # Utilisation de FileLeafRef pour renommer le dossier via son Item
            Set-PnPListItem -List $item.ParentList -Identity $item.Id -Values @{ "FileLeafRef" = $NewFolderName } -Connection $Connection -ErrorAction Stop
            
            # Calcul Nouvelle URL
            $parentUrl = $folder.ServerRelativeUrl.Substring(0, $folder.ServerRelativeUrl.LastIndexOf('/'))
            # Gérer racine (si parent est vide ou /)
            if ([string]::IsNullOrWhiteSpace($parentUrl)) { $finalUrl = "/$NewFolderName" }
            else { $finalUrl = "$parentUrl/$NewFolderName" }
            
            $result.Message += "Renommage effectué ($currentName -> $NewFolderName). "
        }
        else {
            Write-Verbose "[Rename] Nom inchangé."
            $result.Message += "Nom inchangé. "
        }
        
        $result.NewUrl = $finalUrl

        # 3. Mise à jour Métadonnées (Si fournies)
        if ($Metadata -and $Metadata.Count -gt 0) {
            Write-Verbose "[Rename] Mise à jour de $($Metadata.Count) métadonnées..."
            
            # On recupère l'item (peut-être a-t-il changé si renommé ? Normalement l'ID reste bon)
            # Par sécurité re-fetch avec l'ID qui est constant
            Set-PnPListItem -List $item.ParentList -Identity $item.Id -Values $Metadata -Connection $Connection -ErrorAction Stop
            
            $result.Message += "Métadonnées mises à jour. "
        }

    }
    catch {
        $result.Success = $false
        $result.Message = "Erreur : $($_.Exception.Message)"
        Write-Error $result.Message
    }

    return $result
}
