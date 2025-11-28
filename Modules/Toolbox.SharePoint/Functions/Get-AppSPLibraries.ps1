function Get-AppSPLibraries {
    [CmdletBinding()]
    param([string]$SiteUrl)

    try {
        # On doit se connecter au site spécifique pour lister ses listes
        # Astuce : On utilise le Connect-PnPOnline interactif qui utilisera le token en cache
        # Attention : C'est une opération lente, faudra la mettre dans un Job côté UI
        $conn = Connect-PnPOnline -Url $SiteUrl -Interactive -ErrorAction Stop -ReturnConnection
        
        $libs = Get-PnPList -Connection $conn | Where-Object { $_.BaseTemplate -eq 101 -and $_.Hidden -eq $false } | Select-Object Title, Id, RootFolder
        
        return $libs | Sort-Object Title
    }
    catch {
        return @()
    }
}