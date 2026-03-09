# Scripts/SharePoint/SharePointBuilder/Functions/Logic/Register-EditorLogic.ps1

<#
.SYNOPSIS
    Orchestrateur de la logique de l'éditeur graphique de modèles.
    
.DESCRIPTION
    Ce fichier agit désormais comme un point d'entrée unique qui délègue
    la logique métier aux sous-composants situés dans 'Functions/Logic/Editor/'.
    
    - Register-EditorSelectionHandler : Gère la sélection et les panneaux de propriétés.
    - Register-EditorActionHandlers   : Gère les boutons (Toolbar) et les dialogues.

.PARAMETER Ctrl
    La Hashtable des contrôles UI.

.PARAMETER Window
    La fenêtre WPF principale.
    
.PARAMETER Context
    Le contexte global de l'application (ScriptRoot, etc.).
#>
function Register-EditorLogic {
    param(
        [hashtable]$Ctrl,
        [System.Windows.Window]$Window,
        [hashtable]$Context
    )

    Write-Verbose "Initialisation de l'éditeur (Mode Refactorisé)..."

    # 1. Gestion de la Sélection (Panneaux de propriétés dynamiques)
    if (Get-Command Register-EditorSelectionHandler -ErrorAction SilentlyContinue) {
        Register-EditorSelectionHandler -Ctrl $Ctrl -Window $Window
    }
    else {
        Write-Warning "Register-EditorSelectionHandler introuvable !"
    }

    # 2. Gestion des Actions (Boutons, Toolbar, Dialogues, Persistance)
    if (Get-Command Register-EditorActionHandlers -ErrorAction SilentlyContinue) {
        Register-EditorActionHandlers -Ctrl $Ctrl -Window $Window -Context $Context
    }
    else {
        Write-Warning "Register-EditorActionHandlers introuvable !"
    }
}