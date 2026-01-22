# Modules/UI/Functions/Import-AppXamlTemplate.ps1

<#
.SYNOPSIS
    Charge un template XAML, injecte les traductions et instancie l'objet WPF.
    Inclut des fonctionnalités de débogage avancées pour le développement.

.DESCRIPTION
    1. Lit le XAML en UTF-8.
    2. Remplace les balises '##loc:key##' par leur valeur (via Regex).
    3. Échappe les caractères XML spéciaux pour la sécurité.
    4. Parse le résultat.
    
    EN CAS D'ERREUR DE PARSING :
    Un fichier "Dump" contenant le XAML généré est automatiquement créé dans le dossier
    temporaire de l'utilisateur pour permettre l'analyse de la syntaxe.

.PARAMETER XamlPath
    Chemin complet vers le fichier .xaml.
.PARAMETER DebugMode
    [Switch] Si activé, affiche dans la console chaque clé trouvée et son état (OK/MANQUANT).
    Utile pour tracer les boucles infinies ou les clés orphelines.

.EXAMPLE
    Import-AppXamlTemplate -XamlPath "C:\Test.xaml" -DebugMode
#>
function Import-AppXamlTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$XamlPath,

        [Parameter()]
        [switch]$DebugMode
    )

    if (-not (Test-Path $XamlPath)) { throw "Fichier XAML introuvable : $XamlPath" }
    
    try { Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase -ErrorAction Stop } catch {}

    # --- CHRONO DEBUG ---
    $sw = if ($DebugMode) { [System.Diagnostics.Stopwatch]::StartNew() } else { $null }
    if ($DebugMode) { Write-Host "[XAML-DEBUG] Lecture : $(Split-Path $XamlPath -Leaf)" -ForegroundColor Cyan }

    try {
        $xamlContent = Get-Content -Path $XamlPath -Raw -Encoding UTF8

        # --- MOTEUR DE REMPLACEMENT (REGEX) ---
        if (Get-Command "Get-AppText" -ErrorAction SilentlyContinue) {
            
            $pattern = '##loc:(.*?)##'

            $evaluator = {
                param($match)
                
                $key = $match.Groups[1].Value
                $translatedText = Get-AppText -Key $key
                
                # --- TRACE DEBUG (Si activé) ---
                # Note : On utilise $DebugMode hérité du scope parent
                if ($DebugMode) { 
                    if ($translatedText -eq "[$key]" -or [string]::IsNullOrWhiteSpace($translatedText)) { 
                        Write-Host "   MISSING : '$key'" -ForegroundColor Red 
                    } else { 
                        Write-Host "   FOUND   : '$key'" -ForegroundColor DarkGray 
                    }
                }
                # -------------------------------

                return [System.Security.SecurityElement]::Escape($translatedText)
            }

            $xamlContent = [System.Text.RegularExpressions.Regex]::Replace($xamlContent, $pattern, $evaluator)
        }

        if ($DebugMode) { Write-Host "[XAML-DEBUG] Remplacement terminé en $($sw.ElapsedMilliseconds)ms. Parsing..." -ForegroundColor Cyan }

        # --- PARSING FINAL ---
        try {
            $xamlObject = [System.Windows.Markup.XamlReader]::Parse($xamlContent)
            return $xamlObject
        }
        catch {
            # --- GESTION D'ERREUR INTELLIGENTE (CRASH DUMP) ---
            # Si le XamlReader plante, c'est souvent parce qu'une traduction contenait un caractère invalide
            # ou cassait la structure. On sauvegarde le contenu "hydraté" pour analyse.
            
            $filename = "CrashDump_" + (Split-Path $XamlPath -Leaf) + "_" + (Get-Date -Format "HHmmss") + ".xaml"
            $dumpPath = Join-Path $env:TEMP $filename
            
            $xamlContent | Set-Content -Path $dumpPath -Encoding UTF8
            
            Write-Error "ERREUR CRITIQUE XAML dans '$XamlPath'"
            Write-Error "Le contenu généré fautif a été sauvegardé ici pour analyse : $dumpPath"
            Write-Error "Détail : $($_.Exception.Message)"
            
            # On ouvre le dossier temp pour faire gagner du temps au dev
            if ($DebugMode) { Invoke-Item $env:TEMP }
            
            throw $_
        }
    }
    catch {
        # Catch global pour les autres erreurs (IO, etc.)
        throw
    }
}