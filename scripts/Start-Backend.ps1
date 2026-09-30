$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$python = Join-Path $root '.venv/Scripts/python.exe'
$directory = Join-Path $root '.local/backend'
if (-not (Test-Path -LiteralPath $python)) { throw 'Run scripts/Install-Backend.ps1 first.' }
New-Item -ItemType Directory -Force -Path $directory | Out-Null
# Only the current Windows account and SYSTEM inherit access to data and codes.
$identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
$system = [System.Security.Principal.SecurityIdentifier]::new('S-1-5-18')
$aclTool = Join-Path $env:SystemRoot 'System32/icacls.exe'
& $aclTool $directory /inheritance:r /grant:r "*$($identity.Value):(OI)(CI)F" '*S-1-5-18:(OI)(CI)F' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Cannot restrict private Backend data permissions.' }
foreach ($rule in (Get-Acl -LiteralPath $directory).Access) {
    $sid = $rule.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value
    if ($sid -notin @($identity.Value,$system.Value)) {
        & $aclTool $directory /remove:g "*$sid" | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Cannot remove an unexpected private-data ACL.' }
    }
}
$pidFile = Join-Path $directory 'process.json'
if (Test-Path -LiteralPath $pidFile) {
    $record = Get-Content -Raw -LiteralPath $pidFile | ConvertFrom-Json
    $existing = Get-Process -Id $record.pid -ErrorAction SilentlyContinue
    if ($existing -and $existing.Path -eq $record.executable -and [Math]::Abs(($existing.StartTime.ToUniversalTime() - [datetime]$record.startedUtc).TotalSeconds) -lt 2) {
        Write-Output 'Backend is already running. Operator dashboard: http://127.0.0.1:8081'
        return
    }
}
foreach ($port in @(8080,8081)) {
    $occupied = Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue
    if ($occupied) { throw "Port $port is already in use. No existing process will be stopped." }
}
$process = Start-Process -FilePath $python -ArgumentList @('-m','backend') -WorkingDirectory $root -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $directory 'stdout.log') -RedirectStandardError (Join-Path $directory 'stderr.log')
@{ pid = $process.Id; startedUtc = $process.StartTime.ToUniversalTime().ToString('o'); executable = $python } | ConvertTo-Json | Set-Content -LiteralPath $pidFile -Encoding utf8
for ($attempt = 0; $attempt -lt 30; $attempt++) {
    if ($process.HasExited) { throw 'Backend stopped during startup. Read .local/backend/stderr.log (never share connection-codes.json).' }
    try {
        $response = Invoke-WebRequest -Uri 'http://127.0.0.1:8081/' -TimeoutSec 1 -MaximumRedirection 0
        if ($response.StatusCode -eq 200) {
            $listeners = @(Get-NetTCPConnection -State Listen -LocalPort 8080,8081)
            $servingIds = @($listeners.OwningProcess | Sort-Object -Unique)
            if ($servingIds.Count -ne 1) { throw 'API and operator ports are not owned by the same Backend process.' }
            $serving = Get-Process -Id $servingIds[0]
            $details = Get-CimInstance Win32_Process -Filter "ProcessId=$($serving.Id)"
            if ($serving.Id -ne $process.Id -and $details.ParentProcessId -ne $process.Id) { throw 'Listener belongs to another process.' }
            @{ pid = $serving.Id; startedUtc = $serving.StartTime.ToUniversalTime().ToString('o'); executable = $serving.Path; launcherId = $process.Id; launcherStartedUtc = $process.StartTime.ToUniversalTime().ToString('o') } | ConvertTo-Json | Set-Content -LiteralPath $pidFile -Encoding utf8
            Write-Output "Backend started (PID $($serving.Id)). API: http://127.0.0.1:8080 • Operator: http://127.0.0.1:8081"
            Write-Output 'Only local listeners are enabled. Codes are stored privately under .local/backend/connection-codes.json.'
            return
        }
    } catch { Start-Sleep -Milliseconds 500 }
}
throw 'Backend has not become ready; check the private startup log.'
