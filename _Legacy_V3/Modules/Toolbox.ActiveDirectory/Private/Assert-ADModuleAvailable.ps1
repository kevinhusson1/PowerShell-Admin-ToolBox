function Assert-ADModuleAvailable {
    [CmdletBinding()]
    param()

    # On vérifie si le module est déjà chargé ou disponible
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        # Si le module n'est pas trouvé, on lève une exception bloquante avec un message clair.
        throw "Prérequis manquant : Le module PowerShell 'ActiveDirectory' (faisant partie des Outils d'administration de serveur distant - RSAT) n'est pas installé sur ce poste. Veuillez l'installer pour utiliser cette fonctionnalité."
    }
    
    # Si on arrive ici, le prérequis est satisfait.
}