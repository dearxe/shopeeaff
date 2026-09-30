# Run this yourself in PowerShell. It never prints or requests a GitHub token.
param([switch]$UseDeviceCode)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$runtimeGit = Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/native/git'
$git = Join-Path $runtimeGit 'cmd/git.exe'
$manager = Join-Path $runtimeGit 'mingw64/bin/git-credential-manager.exe'
if (-not (Test-Path -LiteralPath $git) -or -not (Test-Path -LiteralPath $manager)) {
    throw 'Bundled Git tools were not found. Install Git for Windows with Git Credential Manager first.'
}
$oldPath = $env:PATH
$oldExecPath = $env:GIT_EXEC_PATH
try {
    $env:PATH = (Join-Path $runtimeGit 'cmd') + ';' + (Join-Path $runtimeGit 'mingw64/bin') + ';' + $oldPath
    $env:GIT_EXEC_PATH = Join-Path $runtimeGit 'mingw64/bin'
    $helper = '"' + $manager.Replace('\','/') + '"'
    & $git -C $root config --local credential.helper $helper
    if ($LASTEXITCODE -ne 0) { throw 'Could not configure the repository credential helper.' }
    if ($UseDeviceCode) {
        Write-Output 'Sign in as dearxe at https://github.com/login/device using the code shown below.'
        & $manager github login --username dearxe --device --no-ui
    } else {
        Write-Output 'Complete GitHub sign-in as dearxe in the browser window. No device code is needed.'
        & $manager github login --username dearxe --browser
    }
    if ($LASTEXITCODE -ne 0) { throw 'GitHub sign-in did not complete.' }
    Write-Output 'GitHub sign-in completed. Return to the chat and tell Codex to retry the push. No code was pushed by this script.'
} finally {
    $env:PATH = $oldPath
    $env:GIT_EXEC_PATH = $oldExecPath
}
