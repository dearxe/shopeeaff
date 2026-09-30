param([ValidateSet('operator','client')][string]$Purpose = 'operator')
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$config = Get-Content -Raw -LiteralPath (Join-Path $root '.local/backend/connection-codes.json') | ConvertFrom-Json
$value = if ($Purpose -eq 'operator') { $config.adminAccessCode } else { $config.clientConnectionCode }
if (-not $value) { throw 'Connection code unavailable; start Backend first.' }
Set-Clipboard -Value $value
Write-Output "Copied $Purpose code to clipboard. Paste it into the local operator login or your private iPhone setup; never paste it into chat."
