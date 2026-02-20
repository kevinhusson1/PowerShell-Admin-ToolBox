<#
.SYNOPSIS
    Utilitaires de formatage et parsing des résultats pour le SharePoint Renamer.

.DESCRIPTION
    Transforme les chaînes brutes renvoyées par l'analyse de dérive (Drift) en objets structurés (DTO)
    afin de simplifier leur exploitation dans l'interface WPF sans imbriquer la logique métier dans la vue.
#>

function Global:Format-RenamerMetadataDrift {
    param(
        [string[]]$MetaDrifts
    )
    
    $driftData = @{}
    if (-not $MetaDrifts) { return $driftData }

    foreach ($d in $MetaDrifts) {
        # Pattern attendu de Toolbox.SharePoint : "Key : Expected 'X' but found 'Y'"
        if ($d -match "^(.+?) : Expected '(.+?)' but found '(.+?)'") {
            $key = $Matches[1].Trim()
            $driftData[$key] = @{ 
                Expected = $Matches[2]
                Found    = $Matches[3]
            }
        }
        # Pattern d'erreur / incomplet
        elseif ($d -match "^(.+?) : Expected '(.+?)'") {
            $key = $Matches[1].Trim()
            $driftData[$key] = @{ 
                Expected = $Matches[2]
                Found    = "(inconnu/vide)"
            }
        }
        elseif ($d -match "^(.+?) :") {
            $key = $Matches[1].Trim()
            $driftData[$key] = @{ 
                Expected = "N/A"
                Found    = "Erreur structurelle"
            }
        }
    }
    
    return $driftData
}

function Global:Format-RenamerStructureDrift {
    param(
        [string[]]$StructureMisses
    )
    
    $missList = @()
    if (-not $StructureMisses) { return $missList }

    foreach ($miss in $StructureMisses) {
        # Retrait de l'emoji initial pour affichage propre
        $clean = $miss -replace "^❌\s*", ""
        $missList += [PSCustomObject]@{
            Raw     = $miss
            Clean   = $clean
            IsError = $true
        }
    }
    
    return $missList
}
