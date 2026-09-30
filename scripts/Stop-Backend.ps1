$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$file = Join-Path $root '.local/backend/process.json'
if (-not (Test-Path -LiteralPath $file)) { Write-Output 'No Backend PID file found.'; return }
$record = Get-Content -Raw -LiteralPath $file | ConvertFrom-Json
$process = Get-Process -Id $record.pid -ErrorAction SilentlyContinue
if (-not $process) { Write-Output 'Backend is already stopped.'; return }
$expected = Join-Path $root '.venv/Scripts/python.exe'
$runtimeLine = Get-Content -LiteralPath (Join-Path $root '.venv/pyvenv.cfg') | Where-Object { $_ -match '^executable\s*=' } | Select-Object -First 1
if (-not $runtimeLine) { throw 'Cannot identify the base Python used by this Backend virtual environment.' }
$runtime = $runtimeLine.Split('=',2)[1].Trim()
if ($process.Path -notin @($expected,$runtime) -or $process.Path -ne $record.executable -or [Math]::Abs(($process.StartTime.ToUniversalTime() - [datetime]$record.startedUtc).TotalSeconds) -ge 2) {
    throw 'PID was reused or belongs to another program. Refusing to stop it.'
}
# A Windows venv may keep a launcher parent and a separate serving child.
# Handle the first-version launcher PID file without stopping unrelated children.
$children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$($process.Id)" | Where-Object { $_.ExecutablePath -eq $runtime -and $_.CommandLine -match '\s-m\s+backend(?:\s|$)' })
foreach ($child in $children) { Stop-Process -Id $child.ProcessId }
Stop-Process -Id $process.Id
Write-Output 'Stopped this Backend process only. SQLite retains jobs; interrupted processing is recovered on the next start.'
