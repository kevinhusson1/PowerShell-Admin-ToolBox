# Modules/Core/Functions/Get-AppConfiguration.ps1

<#
.SYNOPSIS
    Construit l'objet de configuration global de l'application à partir de la base de données.
.DESCRIPTION
    Cette fonction lit tous les paramètres nécessaires depuis la table 'settings' de la base de données
    et les assemble en un objet PSCustomObject structuré.
    Elle fournit des valeurs par défaut pour chaque paramètre afin de garantir que l'application
    puisse démarrer même avec une base de données vide.
.EXAMPLE
    $Global:AppConfig = Get-AppConfiguration
.OUTPUTS
    [pscustomobject] - L'objet de configuration complet de l'application, ou $null en cas d'erreur critique.
#>

function Get-AppConfiguration {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()
    
    try {
        # Étape 1: On définit une structure de configuration de base avec des valeurs par défaut.
        $config = [PSCustomObject]@{
            # --- Section [app] ---
            companyName          = "Mon Entreprise"
            applicationVersion   = "1.0.0"
            defaultLanguage      = "fr-FR"
            availableLanguages   = @("fr-FR", "en-US")
            enableVerboseLogging = $false

            # --- Section [ui] ---
            ui = [PSCustomObject]@{
                launcherWidth  = 800
                launcherHeight = 700
            }

            # --- Section [azure] ---
            azure = [PSCustomObject]@{
                tenantId       = ""
                authentication = [PSCustomObject]@{
                    certificateAuth = [PSCustomObject]@{
                        enabled    = $false
                        thumbprint = ""
                        appId      = ""
                    }
                    userAuth = [PSCustomObject]@{
                        enabled = $true
                        appId   = ""
                        scopes  = @("User.Read") # Un scope minimal par défaut
                    }
                }
            }

            # --- Section [security] ---
            security = [PSCustomObject]@{
                adminGroupName = ""
                startupAuthMode = "System"
            }
        }

        # Étape 2: On peuple cet objet avec les valeurs de la base de données.
        # La valeur par défaut de Get-AppSetting est maintenant la valeur par défaut de notre structure.
        $config.companyName          = Get-AppSetting -Key 'app.companyName' -DefaultValue $config.companyName
        $config.applicationVersion   = Get-AppSetting -Key 'app.version' -DefaultValue $config.applicationVersion
        $config.defaultLanguage      = Get-AppSetting -Key 'app.defaultLanguage' -DefaultValue $config.defaultLanguage
        $config.enableVerboseLogging = Get-AppSetting -Key 'app.enableVerboseLogging' -DefaultValue $config.enableVerboseLogging
        
        $config.ui.launcherWidth  = Get-AppSetting -Key 'ui.launcherWidth' -DefaultValue $config.ui.launcherWidth
        $config.ui.launcherHeight = Get-AppSetting -Key 'ui.launcherHeight' -DefaultValue $config.ui.launcherHeight

        $config.azure.tenantId = Get-AppSetting -Key 'azure.tenantId' -DefaultValue $config.azure.tenantId
        
        $config.azure.authentication.userAuth.appId = Get-AppSetting -Key 'azure.auth.user.appId' -DefaultValue $config.azure.authentication.userAuth.appId
        $scopesFromDb = Get-AppSetting -Key 'azure.auth.user.scopes' -DefaultValue ($config.azure.authentication.userAuth.scopes -join ',')
        $config.azure.authentication.userAuth.scopes = $scopesFromDb -split ',' | ForEach-Object { $_.Trim() }

        $config.azure.authentication.certificateAuth.appId = Get-AppSetting -Key 'azure.auth.cert.appId' -DefaultValue $config.azure.authentication.certificateAuth.appId
        $config.azure.authentication.certificateAuth.thumbprint = Get-AppSetting -Key 'azure.auth.cert.thumbprint' -DefaultValue $config.azure.authentication.certificateAuth.thumbprint

        $config.security.adminGroupName = Get-AppSetting -Key 'security.adminGroupName' -DefaultValue $config.security.adminGroupName
        $config.security.startupAuthMode = Get-AppSetting -Key 'security.startupAuthMode' -DefaultValue $config.security.startupAuthMode

        # On retourne l'objet final, entièrement peuplé et structuré.
        return $config
    }
    catch {
        $errorMessage = Get-AppText -Key 'modules.core.config_build_error'
        Write-Warning "$errorMessage : $($_.Exception.Message)"
        # En cas d'échec total (ex: DB corrompue), on retourne null pour que le test dans Launcher.ps1 puisse l'attraper.
        return $null
    }
}