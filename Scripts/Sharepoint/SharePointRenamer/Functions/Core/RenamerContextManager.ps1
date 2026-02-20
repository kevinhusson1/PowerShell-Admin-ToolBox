<#
.SYNOPSIS
    Gestionnaire de contexte global pour l'application SharePoint Renamer.

.DESCRIPTION
    Encapsule l'état global du script Renamer (URL, Résultats, Logs...) dans un objet centralisé.
    Remplace les multiples appels à $Global:CurrentAnalysisSiteUrl etc.
#>

$Global:RenamerContext = @{
    SiteUrl     = $null
    FolderUrl   = $null
    Result      = $null
    IsConnected = $false
}

function Global:Set-RenamerContext {
    param(
        [string]$SiteUrl,
        [string]$FolderUrl,
        [PSCustomObject]$Result,
        [switch]$Clear
    )
    if ($Clear) {
        $Global:RenamerContext.SiteUrl = $null
        $Global:RenamerContext.FolderUrl = $null
        $Global:RenamerContext.Result = $null
    }
    else {
        if ($PSBoundParameters.ContainsKey('SiteUrl')) { $Global:RenamerContext.SiteUrl = $SiteUrl }
        if ($PSBoundParameters.ContainsKey('FolderUrl')) { $Global:RenamerContext.FolderUrl = $FolderUrl }
        if ($PSBoundParameters.ContainsKey('Result')) { $Global:RenamerContext.Result = $Result }
    }
}

function Global:Get-RenamerContext {
    return $Global:RenamerContext
}
