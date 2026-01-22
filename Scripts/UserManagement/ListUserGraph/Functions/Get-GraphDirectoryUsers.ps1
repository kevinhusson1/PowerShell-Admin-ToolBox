function Get-GraphDirectoryUsers {
    param(
        [string]$CompanyNameFilter
    )

    # Fonction locale pour le formatage (privée à ce scope)
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

    Write-Verbose "[Get-GraphDirectoryUsers] Début extraction Microsoft Graph..."
    
    # 1. Requête Graph
    $userProperties = @(
        "id", "displayName", "givenName", "surname", "userPrincipalName", "userType",
        "mail", "businessPhones", "mobilePhone", "jobTitle", "department", "companyName",
        "employeeId", "streetAddress", "city", "state", "postalCode", "country", "accountEnabled"
    )
    
    # On récupère tout le monde (Server-side filter: enabled only)
    try {
        $usersFromGraph = Get-MgUser -Filter "accountEnabled eq true" -All -Property $userProperties -ExpandProperty "manager" -ConsistencyLevel eventual -ErrorAction Stop
    }
    catch {
        throw "Erreur Get-MgUser: $($_.Exception.Message)"
    }

    # 2. Filtrage Client (Logique Métier)
    $filteredUsers = $usersFromGraph | Where-Object {
        $hasMail = -not [string]::IsNullOrWhiteSpace($_.mail)
        $hasJob = -not [string]::IsNullOrWhiteSpace($_.JobTitle)
        $matchCompany = [string]::IsNullOrWhiteSpace($CompanyNameFilter) -or ($_.CompanyName -eq $CompanyNameFilter)
        
        return ($hasMail -and $hasJob -and $matchCompany)
    }

    # 3. Transformation & Formatage
    $results = [System.Collections.Generic.List[object]]::new()
    
    foreach ($user in $filteredUsers) {
        $results.Add([PSCustomObject]@{
                Id                   = $user.Id
                DisplayName          = $user.DisplayName
                Mail                 = if ($user.Mail) { $user.Mail.ToLower() } else { $null }
                JobTitle             = $user.JobTitle
                Department           = $user.Department
                CompanyName          = $user.CompanyName
                PrimaryBusinessPhone = if ($user.BusinessPhones) { Format-PhoneNumberForDisplay $user.BusinessPhones[0] } else { "" }
                MobilePhone          = Format-PhoneNumberForDisplay $user.MobilePhone
                
                # Manager Handling (Safe navigation)
                ManagerDisplayName   = if ($user.Manager) { $user.Manager.AdditionalProperties['displayName'] } else { $null }
            
                # Champs cachés utiles pour le filtrage ou l'export
                UserPrincipalName    = $user.UserPrincipalName
                City                 = $user.City
                Country              = $user.Country
            })
    }

    Write-Verbose "[Get-GraphDirectoryUsers] $($results.Count) utilisateurs retournés."
    return $results
}
