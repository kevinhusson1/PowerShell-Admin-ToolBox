# Audit-Translations.ps1
param($ProjectRoot = $PSScriptRoot)

Write-Host "--- DÉBUT DE L'AUDIT DE TRADUCTION ---" -ForegroundColor Cyan
$issues = @()

# 1. ANALYSE DES FICHIERS XAML
# On cherche les attributs d'affichage (Text, Content, Header, Title, ToolTip)
# qui ne commencent PAS par ##loc:, {Binding, {DynamicResource, etc.
$xamlFiles = Get-ChildItem -Path $ProjectRoot -Recurse -Include *.xaml | Where-Object { $_.FullName -notmatch "\\Vendor\\" }

foreach ($file in $xamlFiles) {
    $content = Get-Content $file.FullName
    $lineNum = 0
    foreach ($line in $content) {
        $lineNum++
        # Regex : Cherche Text="Bla bla" mais ignore Text="##loc:..." ou Text="{Binding..."
        if ($line -match '(Text|Content|Header|Title|ToolTip)="(?!(##loc:|{Binding|{DynamicResource|{StaticResource|{x:Null|Auto|\*))[^\"]+"') {
            $issues += [PSCustomObject]@{
                Type = "XAML"
                File = $file.Name
                Line = $lineNum
                Text = $matches[0].Trim()
            }
        }
    }
}

# 2. ANALYSE DES FICHIERS POWERSHELL
# On cherche des chaînes de caractères contenant des espaces (indice de phrase humaine)
# dans des commandes spécifiques d'UI ou de Log.
$psFiles = Get-ChildItem -Path $ProjectRoot -Recurse -Include *.ps1, *.psm1 | Where-Object { $_.FullName -notmatch "\\Vendor\\" -and $_.Name -ne "Audit-Translations.ps1" }

foreach ($file in $psFiles) {
    $content = Get-Content $file.FullName
    $lineNum = 0
    foreach ($line in $content) {
        $lineNum++
        
        # Cibles : MessageBox, Write-Warning, Write-LauncherLog...
        # On cherche ce qui est entre guillemets, contient un espace, et ne ressemble pas à une clé de trad (pas de points)
        if ($line -match '(MessageBox]|Write-Warning|Write-Verbose|Write-LauncherLog|StatusMessage).*"(?![^"]*##loc:)(?![^"]*\.[^"]*\.)([^"]*\s[^"]*)"') {
            $issues += [PSCustomObject]@{
                Type = "POWERSHELL"
                File = $file.Name
                Line = $lineNum
                Text = $matches[0].Trim()
            }
        }
    }
}

# AFFICHAGE DES RÉSULTATS
if ($issues.Count -eq 0) {
    Write-Host "Aucun texte en dur détecté ! Félicitations." -ForegroundColor Green
} else {
    $issues | Format-Table -AutoSize
    Write-Host "$($issues.Count) textes potentiellement non traduits trouvés." -ForegroundColor Yellow
}