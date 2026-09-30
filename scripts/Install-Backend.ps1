$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$venv = Join-Path $root '.venv/Scripts/python.exe'
if (-not (Test-Path -LiteralPath $venv)) {
    $bundled = Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
    if (-not (Test-Path -LiteralPath $bundled)) {
        $available = Get-Command python -ErrorAction SilentlyContinue
        if (-not $available) { throw 'Install Python 3.12+ before creating the virtual environment.' }
        $bundled = $available.Source
    }
    & $bundled -c 'import sys; assert sys.version_info >= (3,12), "Python 3.12 or newer is required"'
    if ($LASTEXITCODE -ne 0) { throw 'Python 3.12 or newer is required' }
    & $bundled -m venv (Join-Path $root '.venv')
    if ($LASTEXITCODE -ne 0) { throw 'Virtual environment creation failed' }
}
& $venv -m pip install -r (Join-Path $root 'backend/requirements.lock')
if ($LASTEXITCODE -ne 0) { throw 'Backend dependency installation failed' }
Write-Output 'Backend dependencies installed. Run scripts/Start-Backend.ps1.'
