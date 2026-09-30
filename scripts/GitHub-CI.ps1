param([ValidateSet('Status','Start')][string]$Mode = 'Status')
$ErrorActionPreference = 'Stop'
$runtime = Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/native/git'
$manager = Join-Path $runtime 'mingw64/bin/git-credential-manager.exe'
$oldPath = $env:PATH
$oldExecPath = $env:GIT_EXEC_PATH
$credentialLines = $null
$token = $null
$headers = $null
try {
    $env:PATH = (Join-Path $runtime 'cmd') + ';' + (Join-Path $runtime 'mingw64/bin') + ';' + $oldPath
    $env:GIT_EXEC_PATH = Join-Path $runtime 'mingw64/bin'
    # Capture credentials in memory only. Never emit the helper output or headers.
    $credentialLines = "protocol=https`nhost=github.com`nusername=dearxe`n`n" | & $manager get
    if ($LASTEXITCODE -ne 0) { throw 'GitHub authentication unavailable; run Login-GitHub.ps1 first.' }
    foreach ($line in $credentialLines) {
        if ($line.StartsWith('password=')) { $token = $line.Substring(9) }
    }
    if (-not $token) { throw 'GitHub credential helper did not return authentication.' }
    $headers = @{ Authorization = "Bearer $token"; 'User-Agent' = 'AffiliateHelper-CI'; Accept = 'application/vnd.github+json'; 'X-GitHub-Api-Version' = '2022-11-28' }
    $api = 'https://api.github.com/repos/dearxe/shopeeaff'
    $permissions = Invoke-RestMethod -Uri "$api/actions/permissions" -Headers $headers -MaximumRedirection 0
    if ($Mode -eq 'Start') {
        if (-not $permissions.enabled) {
            Invoke-RestMethod -Uri "$api/actions/permissions" -Method Put -Headers $headers -ContentType 'application/json' -Body '{"enabled":true}' -MaximumRedirection 0 | Out-Null
        }
        $body = @{ ref = 'codex/affiliate-helper-ios' } | ConvertTo-Json
        Invoke-RestMethod -Uri "$api/actions/workflows/ios-validate.yml/dispatches" -Method Post -Headers $headers -ContentType 'application/json' -Body $body -MaximumRedirection 0 | Out-Null
        Write-Output 'Requested iOS Build and Tests. No signing workflow or TestFlight upload was started.'
    }
    $workflows = Invoke-RestMethod -Uri "$api/actions/workflows" -Headers $headers -MaximumRedirection 0
    $runs = Invoke-RestMethod -Uri "$api/actions/runs?branch=codex%2Faffiliate-helper-ios&per_page=3" -Headers $headers -MaximumRedirection 0
    [pscustomobject]@{
        actionsEnabled = $permissions.enabled
        workflows = @($workflows.workflows | Select-Object id,name,state)
        runs = @($runs.workflow_runs | Select-Object id,name,status,conclusion,html_url)
    } | ConvertTo-Json -Depth 5
} finally {
    $credentialLines = $null
    $token = $null
    $headers = $null
    $env:PATH = $oldPath
    $env:GIT_EXEC_PATH = $oldExecPath
}
