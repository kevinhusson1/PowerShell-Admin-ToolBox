function Get-AppSPSites {
    [CmdletBinding()]
    param()

    try {
        # Utilisation de la syntaxe standard PnP Search
        # On retire -RowLimit qui posait problème et on utilise une requête KQL standard
        $results = Submit-PnPSearchQuery -Query "contentclass:STS_Site" -SelectProperties "Title","Path","SiteId" -All -ErrorAction Stop
        
        $sites = @()
        foreach ($res in $results) {
            # La structure de retour peut varier (ResultRows ou directement l'objet)
            # On gère les deux cas
            $row = if ($res.ResultRows) { $res.ResultRows } else { $res }
            
            # Si c'est une liste de résultats
            foreach ($r in $row) {
                $sites += [PSCustomObject]@{
                    Title = $r["Title"]
                    Url   = $r["Path"]
                    Id    = $r["SiteId"]
                }
            }
        }
        return $sites | Sort-Object Title
    }
    catch {
        Write-Warning "Erreur recherche sites : $($_.Exception.Message)"
        return @()
    }
}