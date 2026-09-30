# Requires PowerShell 7.2+; run locally only when preparing an Apple Distribution certificate.
param(
    [Parameter(Mandatory = $true)][string]$Email,
    [ValidatePattern('^[A-Za-z0-9 ._-]+$')][string]$CommonName = 'Affiliate Helper Distribution'
)
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion -lt [version]'7.2') { throw 'Use PowerShell 7.2 or newer.' }
$address = [System.Net.Mail.MailAddress]::new($Email)
if ($address.Address -ne $Email -or $Email -match '[,\r\n]') { throw 'Use a plain email address.' }
$root = Split-Path -Parent $PSScriptRoot
$directory = Join-Path $root '.signing'
New-Item -ItemType Directory -Force -Path $directory | Out-Null
$keyPath = Join-Path $directory 'distribution-private.pem'
$csrPath = Join-Path $directory 'distribution.certSigningRequest'
if ((Test-Path -LiteralPath $keyPath) -or (Test-Path -LiteralPath $csrPath)) { throw 'Existing signing files found; refusing to overwrite the key.' }
$rsa = [System.Security.Cryptography.RSA]::Create(2048)
try {
    $subject = [System.Security.Cryptography.X509Certificates.X500DistinguishedName]::new("CN=$CommonName, E=$Email")
    $request = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new($subject,$rsa,[System.Security.Cryptography.HashAlgorithmName]::SHA256,[System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
    [System.IO.File]::WriteAllText($keyPath,$rsa.ExportPkcs8PrivateKeyPem())
    [System.IO.File]::WriteAllText($csrPath,$request.CreateSigningRequestPem())
    Write-Output "Created CSR: $csrPath"
    Write-Output 'Keep .signing/distribution-private.pem private. Upload ONLY the CSR to Apple; never paste the private key in chat or commit it.'
} finally { $rsa.Dispose() }
