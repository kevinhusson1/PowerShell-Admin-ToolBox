function Get-AppAzureDirectoryUsers {
    <#
    .SYNOPSIS
        Récupère les utilisateurs depuis Microsoft Graph avec filtrage optimisé.
    
    .DESCRIPTION
        Cette fonction permet de récupérer l'annuaire utilisateur en utilisant le filtrage Server-Side 
        pour les propriétés comme 'companyName'. Elle gère automatiquement les spécificités
        des Advanced Queries de Microsoft Graph (ConsistencyLevel: eventual).

    .PARAMETER CompanyNameFilter
        Filtre optionnel pour ne récupérer que les utilisateurs d'une société spécifique.
        Le filtrage est effectué côté serveur.

    .PARAMETER Properties
    Liste des propriétés à récupérer. Par défaut : liste standard pour l'annuaire.
        
    .EXAMPLE
        Get-AppAzureDirectoryUsers -CompanyNameFilter "MyCompany" -Properties "id","displayName","mail"
    #>
    param(
        [string]$CompanyNameFilter,
        [string[]]$Properties = @(
            "id", "displayName", "givenName", "surname", "userPrincipalName", "userType",
            "mail", "businessPhones", "mobilePhone", "jobTitle", "department", "companyName",
            "employeeId", "streetAddress", "city", "state", "postalCode", "country", "accountEnabled"
        )
    )

    # Fonction locale pour le formatage (interne)
    function Format-PhoneNumberForDisplay {
        param([string]$phone)
        if ([string]::IsNullOrWhiteSpace($phone)) { return "" }
    
        $cleanedPhone = $phone -replace '[^\d+]', ''
        if ($cleanedPhone.IndexOf('+') -gt 0) { $cleanedPhone = $cleanedPhone -replace '[+]', '' }
    
        if ($cleanedPhone.StartsWith("+33") -and $cleanedPhone.Length -eq 12) {
            $numPart = $cleanedPhone.Substring(3)
            return "+33 $($numPart[0]) $($numPart.Substring(1,2)) $($numPart.Substring(3,2)) $($numPart.Substring(5,2)) $($numPart.Substring(7,2))"
        }
        elseif ($cleanedPhone.StartsWith("0") -and $cleanedPhone.Length -eq 10) {
            return "$($cleanedPhone.Substring(0,2)).$($cleanedPhone.Substring(2,2)).$($cleanedPhone.Substring(4,2)).$($cleanedPhone.Substring(6,2)).$($cleanedPhone.Substring(8,2))"
        }
        return $phone
    }

    Write-Verbose "[Get-AppAzureDirectoryUsers] Début extraction Microsoft Graph..."
    
    # 1. Tentative avec filtrage Server-Side (Optimisé via Invoke-MgGraphRequest)
    $usersFromGraph = $null
    $usedServerSideFilter = $false
    
    # Mapping des propriétés pour le $select (Graph API utilise des noms camelCase)
    $selectProps = $Properties | ForEach-Object { $_.Trim() }
    $selectString = $selectProps -join ','

    # Filtre de base
    $baseFilter = "accountEnabled eq true"
    
    # Filtre optimisé
    # Filtre optimisé (Désactivé : Conflit Graph v1.0 avec Expand Manager)
    # On laisse le client-side filtering faire le travail.

    
    # 2. Fallback Filtrage Client (Standard) si échec ou pas de filtre société
    if ($null -eq $usersFromGraph) {
        Write-Verbose "[Get-AppAzureDirectoryUsers] Requête standard (Filter: $baseFilter)"
        try {
            $usersFromGraph = Get-MgUser -Filter $baseFilter -All -Property $Properties -ExpandProperty "manager" -ErrorAction Stop
        }
        catch {
            throw "Erreur Critique Get-MgUser: $($_.Exception.Message)"
        }
    }

    # 3. Filtrage Client Final (Logique Métier + Fallback CompanyName) et Mapping
    $results = [System.Collections.Generic.List[object]]::new()
    
    foreach ($user in $usersFromGraph) {
        # Gestion des propriétés (supporte MgUser object et PSCustomObject from JSON)
        # Note: Invoke-MgGraphRequest retourne souvent des HashTables ou PSCustomObject avec propriétés case-sensitive selon context
        
        $uMail = if ($user.PSObject.Properties['mail']) { $user.mail } elseif ($user.PSObject.Properties['Mail']) { $user.Mail } else { $null }
        $uJob = if ($user.PSObject.Properties['jobTitle']) { $user.jobTitle } elseif ($user.PSObject.Properties['JobTitle']) { $user.JobTitle } else { $null }
        $uComp = if ($user.PSObject.Properties['companyName']) { $user.companyName } elseif ($user.PSObject.Properties['CompanyName']) { $user.CompanyName } else { $null }

        $hasMail = -not [string]::IsNullOrWhiteSpace($uMail)
        $hasJob = -not [string]::IsNullOrWhiteSpace($uJob)
        
        # Filtre Client Company si nécessaire
        $matchCompany = $true
        if (-not $usedServerSideFilter -and -not [string]::IsNullOrWhiteSpace($CompanyNameFilter)) {
            $matchCompany = ($uComp -eq $CompanyNameFilter)
        }
        
        if ($hasMail -and $hasJob -and $matchCompany) {
            
            # Mapping final
            $PIDs = if ($user.PSObject.Properties['id']) { $user.id } else { $user.Id }
            $pDispName = if ($user.PSObject.Properties['displayName']) { $user.displayName } else { $user.DisplayName }
            $pDept = if ($user.PSObject.Properties['department']) { $user.department } else { $user.Department }
            
            # Phones (Array or List)
            $pPhones = if ($user.PSObject.Properties['businessPhones']) { $user.businessPhones } else { $user.BusinessPhones }
            $pMobile = if ($user.PSObject.Properties['mobilePhone']) { $user.mobilePhone } else { $user.MobilePhone }
            
            $pCity = if ($user.PSObject.Properties['city']) { $user.city } else { $user.City }
            $pCountry = if ($user.PSObject.Properties['country']) { $user.country } else { $user.Country }
            $pUPN = if ($user.PSObject.Properties['userPrincipalName']) { $user.userPrincipalName } else { $user.UserPrincipalName }

            # Manager
            $pManagerName = $null
            if ($user.PSObject.Properties['manager']) {
                $mgr = $user.manager
                if ($mgr -is [string]) { 
                    # Parfois juste l'ID ou URL ref si pas expand ? Non, avec expand c'est un objet
                }
                elseif ($mgr.PSObject.Properties['displayName']) { $pManagerName = $mgr.displayName }
                elseif ($mgr.PSObject.Properties['additionalProperties'] -and $mgr.additionalProperties.ContainsKey('displayName')) { $pManagerName = $mgr.additionalProperties['displayName'] }
                elseif ($mgr.AdditionalProperties -and $mgr.AdditionalProperties.ContainsKey('displayName')) { $pManagerName = $mgr.AdditionalProperties['displayName'] }
            }

            $results.Add([PSCustomObject]@{
                    Id                   = $PIDs
                    DisplayName          = $pDispName
                    Mail                 = if ($uMail) { $uMail.ToLower() } else { $null }
                    JobTitle             = $uJob
                    Department           = $pDept
                    CompanyName          = $uComp
                    PrimaryBusinessPhone = if ($pPhones) { Format-PhoneNumberForDisplay $pPhones[0] } else { "" }
                    MobilePhone          = Format-PhoneNumberForDisplay $pMobile
                
                    ManagerDisplayName   = $pManagerName
            
                    UserPrincipalName    = $pUPN
                    City                 = $pCity
                    Country              = $pCountry
                })
        }
    }

    Write-Verbose "[Get-AppAzureDirectoryUsers] $($results.Count) utilisateurs retournés."
    return $results
}
