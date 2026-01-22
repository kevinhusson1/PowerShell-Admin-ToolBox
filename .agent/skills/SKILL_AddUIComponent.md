---
name: add_ui_component
description: Ajoute un nouveau composant UI (ResourceDictionary) et l'intègre au système de thèmes.
---

# Ajout d'un Composant UI (XAML)

Ce skill explique comment ajouter un style ou un contrôle réutilisable.

## Structure
Les composants sont stockés dans `Templates/Components/` ou `Templates/Styles/`.

## Étapes

1.  **Création du Fichier XAML**
    *   Créer un fichier `.xaml` dans le sous-dossier approprié (ex: `Templates/Components/Inputs/MyNewInput.xaml`).
    *   Le fichier doit être un `ResourceDictionary`.

2.  **Définition du Style**
    ```xml
    <ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
        <Style x:Key="MyNewInputStyle" TargetType="{x:Type TextBox}">
            <!-- Setters -->
        </Style>
    </ResourceDictionary>
    ```

3.  **Enregistrement Global**
    *   Pour que le style soit disponible partout, il doit être chargé par le Launcher ou le script.
    *   Modifier `Modules/UI/Functions/Initialize-AppUIComponents.ps1` pour inclure le nouveau fichier dans la liste de chargement si c'est un composant Core.

4.  **Utilisation**
    *   Dans vos pages XAML : `Style="{StaticResource MyNewInputStyle}"`.
