#
# Manifeste pour l'outil "ComponentShowcase"
#
@{
    # Version du format de ce manifeste
    ManifestVersion = '1.0'

    # --- Informations affichées dans le lanceur principal ---
    Name = 'Vitrine des Composants'
    Description = "Un outil de développement qui affiche tous les contrôles graphiques disponibles dans le thème de l'application. Permet de valider la charte graphique."
    Author = 'Développement PSToolBox'
    Version = '1.0.0'
    # L'icône pour l'affichage DANS la grille (un .png de préférence)
    DisplayIcon = 'Assets/palette.png' 
    
    # L'icône pour la fenêtre et la barre des tâches (un .ico)
    WindowIcon = 'Assets/palette.ico'

    # --- Point d'entrée de l'outil (la partie la plus importante) ---
    # Le lanceur principal saura qu'il doit charger cette vue et ce ViewModel.
    RootView = 'Views/ComponentShowcase.View.xaml'
    # Pour l'instant, notre ViewModel est simple et est dans le script de lancement.
    # Plus tard, chaque outil aura son propre fichier ViewModel.
    # Laissons cette clé vide pour le moment.
    RootViewModel = ''
}