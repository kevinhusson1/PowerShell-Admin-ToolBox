# Modules/Localization/Functions/Merge-PSCustomObject.ps1

# =====================================================================
# FONCTION D'AIDE PRIVÉE (non exportée par le module)
# =====================================================================
<#
.SYNOPSIS
    (Fonction interne) Fusionne récursivement un objet PSCustomObject dans un autre.
.DESCRIPTION
    Cette fonction parcourt les propriétés d'un objet "superposé" ($overlay)
    et les ajoute ou les met à jour dans un objet de "base" ($base).
    Si une propriété est elle-même un objet PSCustomObject dans les deux sources,
    la fonction s'appelle elle-même pour effectuer une fusion en profondeur.
.NOTES
    Cette fonction modifie directement l'objet $base.
#>
function Merge-PSCustomObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$base,

        [Parameter(Mandatory)]
        [psobject]$overlay
    )

    # Sécurité de base
    if ($null -eq $base -or $null -eq $overlay) { return }

    foreach ($key in $overlay.PSObject.Properties.Name) {
        # Si la clé existe dans les deux et que les deux valeurs sont des objets, on continue la fusion en profondeur (récursivité)
        if ($base.PSObject.Properties[$key] -and $base.$key -is [psobject] -and $overlay.$key -is [psobject]) {
            Write-Verbose "Fusion en profondeur pour la clé '$key'."
            Merge-PSCustomObject -base $base.$key -overlay $overlay.$key
        } 
        # Sinon, on ajoute ou on écrase simplement la valeur
        else {
            if ($base.PSObject.Properties[$key]) {
                Write-Verbose "Mise à jour de la clé '$key'."
                $base.$key = $overlay.$key
            } else {
                Write-Verbose "Ajout de la nouvelle clé '$key'."
                Add-Member -InputObject $base -MemberType NoteProperty -Name $key -Value $overlay.$key
            }
        }
    }
}