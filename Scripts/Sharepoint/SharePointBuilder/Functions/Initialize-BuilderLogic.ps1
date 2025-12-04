function Initialize-BuilderLogic {
    param($Context)

    $Window = $Context.Window
    $ScriptRoot = $Context.ScriptRoot

    # 1. Chargement des sous-fonctions logiques
    $logicPath = Join-Path $ScriptRoot "Functions\Logic"
    if (Test-Path $logicPath) {
        Get-ChildItem -Path $logicPath -Filter "*.ps1" | ForEach-Object { 
            Write-Verbose "Chargement logique : $($_.Name)"
            . $_.FullName 
        }
    }

    # 2. Récupération centralisée des contrôles
    $Ctrl = Get-BuilderControls -Window $Window
    if (-not $Ctrl) { return }

    # 3. Initialisation UX
    $Ctrl.CbSites.IsEnabled = $false
    $Ctrl.CbLibs.IsEnabled = $false
    $Ctrl.BtnDeploy.IsEnabled = $false

    # 4. Récupération de la logique de Validation (EXTERNALISÉE)
    # C'est ici la correction : on appelle la fonction au lieu d'écrire le code en dur
    $PreviewLogic = Get-PreviewLogic -Ctrl $Ctrl -Window $Window

    # 5. Câblage avec passage du CONTEXTE
    Register-TemplateEvents -Ctrl $Ctrl -PreviewLogic $PreviewLogic -Window $Window -Context $Context
    Register-SiteEvents     -Ctrl $Ctrl -PreviewLogic $PreviewLogic -Window $Window -Context $Context
    Register-DeployEvents   -Ctrl $Ctrl -Window $Window
    # NOUVEAU : Câblage de l'éditeur
    Register-EditorLogic    -Ctrl $Ctrl -Window $Window
}