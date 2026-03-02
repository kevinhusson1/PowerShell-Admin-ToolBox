# Generate-ToolboxCert.ps1

# 1. Configuration
$certName = "Toolbox-AppOnly-Cert"
$validityYears = 5
$password = ConvertTo-SecureString "id7SZXK6Vg6LepLjF$!8#92eXUVKctOfX^%Pif95" -AsPlainText -Force # Mot de passe pour le PFX (backup)
$exportPath = "C:\TEMP\ToolboxCert"

# Création dossier
New-Item -ItemType Directory -Force -Path $exportPath | Out-Null

# 2. Génération dans le magasin Personnel (CurrentUser)
Write-Host "Génération du certificat '$certName'..." -ForegroundColor Cyan
$cert = New-SelfSignedCertificate `
    -Subject "CN=$certName" `
    -KeySpec KeyExchange `
    -Provider "Microsoft RSA SChannel Cryptographic Provider" `
    -KeyExportPolicy Exportable `
    -HashAlgorithm SHA256 `
    -KeyLength 2048 `
    -NotAfter (Get-Date).AddYears($validityYears) `
    -CertStoreLocation "Cert:\CurrentUser\My"

# 3. Export de la Clé Publique (.cer) -> POUR AZURE
$cerFile = Join-Path $exportPath "$certName.cer"
Export-Certificate -Cert $cert -FilePath $cerFile | Out-Null

# 4. Export de la Clé Privée (.pfx) -> POUR BACKUP (Optionnel car déjà installé)
$pfxFile = Join-Path $exportPath "$certName.pfx"
Export-PfxCertificate -Cert $cert -FilePath $pfxFile -Password $password | Out-Null

# 5. Résultat
Write-Host "---------------------------------------------------" -ForegroundColor Green
Write-Host "✅ Certificat généré et installé." -ForegroundColor Green
Write-Host "📂 Fichiers exportés dans : $exportPath"
Write-Host "🔑 EMPREINTE (THUMBPRINT) À COPIER DANS L'APPLI :" -ForegroundColor Yellow
Write-Host $cert.Thumbprint -ForegroundColor Yellow
Write-Host "---------------------------------------------------" -ForegroundColor Green
Set-Clipboard -Value $cert.Thumbprint
Write-Host "(L'empreinte a été copiée dans votre presse-papiers)" -ForegroundColor Gray