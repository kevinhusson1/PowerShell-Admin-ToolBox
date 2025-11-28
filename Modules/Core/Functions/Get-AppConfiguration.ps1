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
                tenantName     = ""
                tenantId       = ""
                certThumbprint = ""
                authentication = [PSCustomObject]@{
                    # Suppression complète de l'objet certificateAuth
                    userAuth = [PSCustomObject]@{
                        enabled = $true
                        appId   = ""
                        scopes  = @("User.Read") 
                    }
                }
            }

            # --- Section [security] ---
            security = [PSCustomObject]@{
                adminGroupName = ""
                # Suppression de startupAuthMode (sera toujours User)
            }

            # --- Section AD ---
            ad = [PSCustomObject]@{
                serviceUser         = ""
                servicePassword     = "" 
                tempServer          = ""
                connectServer       = ""
                domainName          = ""
                userOUPath          = ""
                pdcName             = ""
                domainUserGroup     = ""
                excludedGroups      = @()
            }
        }

        # Étape 2: On peuple cet objet avec les valeurs de la base de données.
        # La valeur par défaut de Get-AppSetting est maintenant la valeur par défaut de notre structure.
        $config.companyName          = Get-AppSetting -Key 'app.companyName' -DefaultValue $config.companyName
        try {
            $config.applicationVersion = (Get-Module Core).Version.ToString()
        } catch {
            $config.applicationVersion = "N/A" # Fallback en cas d'erreur
        }
        $config.defaultLanguage      = Get-AppSetting -Key 'app.defaultLanguage' -DefaultValue $config.defaultLanguage
        $config.enableVerboseLogging = Get-AppSetting -Key 'app.enableVerboseLogging' -DefaultValue $config.enableVerboseLogging
        
        $config.ui.launcherWidth  = Get-AppSetting -Key 'ui.launcherWidth' -DefaultValue $config.ui.launcherWidth
        $config.ui.launcherHeight = Get-AppSetting -Key 'ui.launcherHeight' -DefaultValue $config.ui.launcherHeight

        $config.azure.tenantName = Get-AppSetting -Key 'azure.tenantName' -DefaultValue ""
        $config.azure.tenantId = Get-AppSetting -Key 'azure.tenantId' -DefaultValue $config.azure.tenantId
        $config.azure.certThumbprint = Get-AppSetting -Key 'azure.cert.thumbprint' -DefaultValue ""
        
        $config.azure.authentication.userAuth.appId = Get-AppSetting -Key 'azure.auth.user.appId' -DefaultValue $config.azure.authentication.userAuth.appId
        $scopesFromDb = Get-AppSetting -Key 'azure.auth.user.scopes' -DefaultValue ($config.azure.authentication.userAuth.scopes -join ',')
        $config.azure.authentication.userAuth.scopes = $scopesFromDb -split ',' | ForEach-Object { $_.Trim() }

        $config.security.adminGroupName = Get-AppSetting -Key 'security.adminGroupName' -DefaultValue $config.security.adminGroupName

        # --- NOUVEAU : Peuplement de la section [ad] ---
        $config.ad.serviceUser = Get-AppSetting -Key 'ad.serviceUser' -DefaultValue $config.ad.serviceUser
        $config.ad.servicePassword = Get-AppSetting -Key 'ad.servicePassword' -DefaultValue $config.ad.servicePassword
        $config.ad.tempServer = Get-AppSetting -Key 'ad.tempServer' -DefaultValue $config.ad.tempServer
        $config.ad.connectServer = Get-AppSetting -Key 'ad.connectServer' -DefaultValue $config.ad.connectServer
        $config.ad.domainName = Get-AppSetting -Key 'ad.domainName' -DefaultValue $config.ad.domainName
        $config.ad.userOUPath = Get-AppSetting -Key 'ad.userOUPath' -DefaultValue $config.ad.userOUPath
        $config.ad.pdcName = Get-AppSetting -Key 'ad.pdcName' -DefaultValue $config.ad.pdcName
        $config.ad.domainUserGroup = Get-AppSetting -Key 'ad.domainUserGroup' -DefaultValue $config.ad.domainUserGroup
        $excludedGroupsFromDb = Get-AppSetting -Key 'ad.excludedGroups' -DefaultValue ""
        $config.ad.excludedGroups = $excludedGroupsFromDb -split ',' | ForEach-Object { $_.Trim() }
        
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