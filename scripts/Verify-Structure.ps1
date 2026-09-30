$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$pbx = Get-Content -Raw -LiteralPath (Join-Path $root 'LinkAff.xcodeproj/project.pbxproj')
$definitions = [regex]::Matches($pbx, '(?m)^([A-F0-9]{24}) =') | ForEach-Object { $_.Groups[1].Value }
if (($definitions | Sort-Object -Unique).Count -ne $definitions.Count) { throw 'Duplicate PBX object IDs' }
$allIdentifiers = [regex]::Matches($pbx, '\b[A-F0-9]{24}\b') | ForEach-Object { $_.Value } | Sort-Object -Unique
foreach ($identifier in $allIdentifiers) {
    if ($identifier -notin $definitions) { throw "Unresolved PBX reference: $identifier" }
}
$appGroup = [regex]::Match($pbx, 'D00000000000000000000002 = .*children = \((.*?)\);').Groups[1].Value
$swiftNames = [regex]::Matches($pbx, 'path = ([A-Za-z]+\.swift);') | ForEach-Object { $_.Groups[1].Value }
foreach ($name in $swiftNames) {
    $folder = if ($name -eq 'LinkAffTests.swift') { 'LinkAffTests' } else { 'LinkAff' }
    if (-not (Test-Path -LiteralPath (Join-Path $root "$folder/$name"))) { throw "Missing source: $name" }
}
[xml]$scheme = Get-Content -Raw -LiteralPath (Join-Path $root 'LinkAff.xcodeproj/xcshareddata/xcschemes/LinkAff.xcscheme')
[xml]$privacy = Get-Content -Raw -LiteralPath (Join-Path $root 'LinkAff/PrivacyInfo.xcprivacy')
if ($scheme.Scheme.BuildAction.BuildActionEntries.BuildActionEntry.BuildableReference.BlueprintIdentifier -notin $definitions) { throw 'Invalid scheme target' }
$yaml = Get-Content -Raw -LiteralPath (Join-Path $root 'openapi.yaml')
$schemaNames = @('CreateRequest','TrackingRequest','Job','ErrorDetail','ErrorEnvelope')
$responseNames = @('BadRequest','Unauthorized','Forbidden','NotFound','Conflict','RateLimited','Unavailable','GenericError')
foreach ($match in [regex]::Matches($yaml, '#/components/(schemas|responses|headers)/([A-Za-z]+)')) {
    $known = switch ($match.Groups[1].Value) { 'schemas' { $schemaNames } 'responses' { $responseNames } 'headers' { @('RetryAfter') } }
    if ($match.Groups[2].Value -notin $known) { throw 'Unknown OpenAPI component reference' }
}
foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object { $_.Extension -in '.swift','.yaml','.md','.ps1','.pbxproj','.xcscheme','.xcprivacy' }) {
    $text = Get-Content -Raw -LiteralPath $file.FullName
    if ($text -match '(?m)[\t ]+$') { throw "Trailing whitespace: $($file.Name)" }
}
$sources = (Get-ChildItem -LiteralPath (Join-Path $root 'LinkAff') -Filter '*.swift' | Get-Content -Raw) -join "`n"
foreach ($forbidden in @('NSAllowsArbitraryLoads', 'serverTrust', 'print\(', 'contains\("shopee"\)')) {
    if ($sources -match $forbidden) { throw "Unexpected source pattern: $forbidden" }
}
Write-Output "PASS: $($definitions.Count) unique/resolved PBX objects; $($swiftNames.Count) source files; scheme and privacy XML; OpenAPI references; whitespace and selected source safety checks."
Write-Output 'This is a static structure check, not Swift compilation, XCTest, OpenAPI schema validation, or UI testing.'
$config = Get-Content -Raw -LiteralPath (Join-Path $root 'deployment/owner-config.example.json') | ConvertFrom-Json
if ($pbx -notmatch [regex]::Escape("PRODUCT_BUNDLE_IDENTIFIER = $($config.bundleId);")) { throw 'Bundle ID mismatch' }
if ($pbx -notmatch 'ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;') { throw 'AppIcon not configured' }
foreach ($asset in Get-ChildItem -LiteralPath (Join-Path $root 'LinkAff/Assets.xcassets') -Recurse -Filter 'Contents.json') {
    $content = Get-Content -Raw -LiteralPath $asset.FullName | ConvertFrom-Json
    foreach ($entry in $content.images) {
        if ($entry.filename -and -not (Test-Path -LiteralPath (Join-Path $asset.DirectoryName $entry.filename))) { throw 'Missing asset image' }
    }
}
Add-Type -AssemblyName System.Drawing
$icon = [System.Drawing.Image]::FromFile((Join-Path $root 'LinkAff/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png'))
try {
    if ($icon.Width -ne 1024 -or $icon.Height -ne 1024 -or $icon.PixelFormat -ne [System.Drawing.Imaging.PixelFormat]::Format24bppRgb) { throw 'Icon must be 1024 square opaque RGB' }
} finally { $icon.Dispose() }
foreach ($script in Get-ChildItem -LiteralPath (Join-Path $root 'scripts') -Filter '*.ps1') {
    $scriptTokens = $null
    $scriptErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($script.FullName,[ref]$scriptTokens,[ref]$scriptErrors)
    if ($scriptErrors.Count -gt 0) { throw "PowerShell parse failure: $($script.Name)" }
}
Write-Output 'PASS: Bundle ID, asset JSON/image paths, opaque RGB AppIcon 1024x1024, PowerShell syntax.'
