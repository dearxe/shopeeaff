param([Parameter(Mandatory = $true)][string]$SourcePath)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Add-Type -AssemblyName System.Drawing
$source = [System.Drawing.Image]::FromFile((Resolve-Path -LiteralPath $SourcePath).Path)
try {
    if ($source.Width -ne $source.Height) { throw 'App icon source must be square; do not crop silently.' }
    $bitmap = [System.Drawing.Bitmap]::new(1024,1024,[System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.Clear([System.Drawing.Color]::White)
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.DrawImage($source,0,0,1024,1024)
        $iconPath = Join-Path $root 'LinkAff/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png'
        $bitmap.Save($iconPath,[System.Drawing.Imaging.ImageFormat]::Png)
        Copy-Item -LiteralPath $iconPath -Destination (Join-Path $root 'LinkAff/Assets.xcassets/BrandMark.imageset/BrandMark.png')
        Write-Output 'Exported opaque RGB 1024x1024 AppIcon and BrandMark.'
    } finally { $graphics.Dispose(); $bitmap.Dispose() }
} finally { $source.Dispose() }
