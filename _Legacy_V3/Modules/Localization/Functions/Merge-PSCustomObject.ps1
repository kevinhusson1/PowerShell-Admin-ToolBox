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

    if ($null -eq $base -or $null -eq $overlay) { return }

    foreach ($key in $overlay.PSObject.Properties.Name) {
        $baseValue = $base.$key
        $overlayValue = $overlay.$key

        # --- CORRECTION CRITIQUE ---
        # On vérifie si les valeurs sont des OBJETS COMPLEXES (Conteneurs) et non des types simples.
        # En PowerShell, [string] est un [psobject], ce qui causait une récursivité infinie sur le texte.
        $isBaseComplex = ($baseValue -is [psobject]) -and ($baseValue -isnot [string]) -and ($baseValue -isnot [System.ValueType])
        $isOverlayComplex = ($overlayValue -is [psobject]) -and ($overlayValue -isnot [string]) -and ($overlayValue -isnot [System.ValueType])

        # Si la clé existe et que les DEUX valeurs sont des objets complexes (ex: sous-sections JSON), on fusionne.
        if ($base.PSObject.Properties[$key] -and $isBaseComplex -and $isOverlayComplex) {
            Write-Verbose "Fusion en profondeur pour la clé '$key'."
            Merge-PSCustomObject -base $baseValue -overlay $overlayValue
        } 
        # Sinon, on écrase ou on ajoute (cas des Textes, Booléens, Entiers)
        else {
            if ($base.PSObject.Properties[$key]) {
                Write-Verbose "Mise à jour de la clé '$key'."
                $base.$key = $overlayValue
            } else {
                Write-Verbose "Ajout de la nouvelle clé '$key'."
                Add-Member -InputObject $base -MemberType NoteProperty -Name $key -Value $overlayValue
            }
        }
    }
}