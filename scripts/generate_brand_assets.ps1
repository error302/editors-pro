param()

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$projectRoot = Split-Path $PSScriptRoot -Parent
$resourceRoot = Join-Path $projectRoot 'android/app/src/main/res'
$symbol = [System.Drawing.Bitmap]::FromFile((Join-Path $projectRoot 'assets/icons/editors_pro_mark.png'))

function Export-BrandPng {
    param([string]$Path, [int]$Size, [double]$Scale, [bool]$Opaque)
    $canvas = [System.Drawing.Bitmap]::new($Size, $Size)
    $graphics = [System.Drawing.Graphics]::FromImage($canvas)
    try {
        $background = if ($Opaque) { [System.Drawing.ColorTranslator]::FromHtml('#111214') } else { [System.Drawing.Color]::Transparent }
        $graphics.Clear($background)
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $extent = [int][Math]::Round($Size * $Scale)
        $offset = [int][Math]::Round(($Size - $extent) / 2)
        $graphics.DrawImage($symbol, $offset, $offset, $extent, $extent)
        $canvas.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $graphics.Dispose()
        $canvas.Dispose()
    }
}

try {
    # Adaptive foregrounds use a 108dp canvas; keep the symbol inside
    # the central safe circle for circular and rounded launcher masks.
    $densities = @(
        @{ Name = 'mdpi'; Scale = 1 },
        @{ Name = 'hdpi'; Scale = 1.5 },
        @{ Name = 'xhdpi'; Scale = 2 },
        @{ Name = 'xxhdpi'; Scale = 3 },
        @{ Name = 'xxxhdpi'; Scale = 4 }
    )
    foreach ($density in $densities) {
        $directory = Join-Path $resourceRoot ('mipmap-' + $density.Name)
        Export-BrandPng -Path (Join-Path $directory 'ic_launcher.png') -Size ([int](48 * $density.Scale)) -Scale 0.96 -Opaque $true
        Export-BrandPng -Path (Join-Path $directory 'ic_launcher_foreground.png') -Size ([int](108 * $density.Scale)) -Scale 0.56 -Opaque $false
    }
    $drawableDirectory = Join-Path $resourceRoot 'drawable-nodpi'
    New-Item -ItemType Directory -Path $drawableDirectory -Force | Out-Null
    Export-BrandPng -Path (Join-Path $drawableDirectory 'brand_splash.png') -Size 512 -Scale 1 -Opaque $false
    Write-Output 'Exported launcher icons for five Android densities and the native splash symbol.'
} finally {
    $symbol.Dispose()
}
