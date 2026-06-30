param(
    [string]$Preset = "publish_4x5_soft",
    [string]$InputPath = "",
    [string]$OutputDir = "",
    [switch]$Overwrite
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Drawing

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$labDir = Split-Path -Parent $scriptDir

if ([string]::IsNullOrWhiteSpace($InputPath)) {
    $InputPath = Join-Path $labDir "inbox"
}

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $labDir "output"
}

$presetPath = Join-Path (Join-Path $labDir "presets") "$Preset.json"
if (-not (Test-Path -LiteralPath $presetPath)) {
    throw "Preset not found: $presetPath"
}

$settings = Get-Content -LiteralPath $presetPath -Raw | ConvertFrom-Json

if (-not (Test-Path -LiteralPath $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir | Out-Null
}

$logDir = Join-Path $labDir "logs"
if (-not (Test-Path -LiteralPath $logDir)) {
    New-Item -ItemType Directory -Path $logDir | Out-Null
}

$supported = @(".jpg", ".jpeg", ".png", ".bmp", ".tif", ".tiff")

function Get-OutputPath {
    param(
        [System.IO.FileInfo]$File,
        [object]$Settings,
        [string]$OutputDir,
        [bool]$Overwrite
    )

    $suffix = $Settings.suffix
    if ([string]::IsNullOrWhiteSpace($suffix)) {
        $suffix = $Settings.name
    }

    $extension = ".jpg"
    if ($Settings.format -eq "png") {
        $extension = ".png"
    }

    $baseName = "{0}_{1}" -f [System.IO.Path]::GetFileNameWithoutExtension($File.Name), $suffix
    $candidate = Join-Path $OutputDir ($baseName + $extension)

    if ($Overwrite -or -not (Test-Path -LiteralPath $candidate)) {
        return $candidate
    }

    $index = 2
    while ($true) {
        $next = Join-Path $OutputDir ("{0}_{1}{2}" -f $baseName, $index, $extension)
        if (-not (Test-Path -LiteralPath $next)) {
            return $next
        }
        $index++
    }
}

function Get-InputFiles {
    param([string]$InputPath)

    if (-not (Test-Path -LiteralPath $InputPath)) {
        throw "Input path not found: $InputPath"
    }

    $item = Get-Item -LiteralPath $InputPath
    if ($item.PSIsContainer) {
        return Get-ChildItem -LiteralPath $InputPath -File |
            Where-Object { $supported -contains $_.Extension.ToLowerInvariant() }
    }

    if ($supported -notcontains $item.Extension.ToLowerInvariant()) {
        throw "Unsupported image type: $($item.Extension)"
    }

    return @($item)
}

function Get-SourceRectangle {
    param(
        [System.Drawing.Image]$Image,
        [object]$Settings
    )

    $sourceWidth = $Image.Width
    $sourceHeight = $Image.Height
    $targetWidth = [int]$Settings.width
    $targetHeight = [int]$Settings.height

    if ($Settings.crop -ne "center" -or $targetWidth -le 0 -or $targetHeight -le 0) {
        return New-Object System.Drawing.Rectangle 0, 0, $sourceWidth, $sourceHeight
    }

    $sourceRatio = $sourceWidth / $sourceHeight
    $targetRatio = $targetWidth / $targetHeight

    if ($sourceRatio -gt $targetRatio) {
        $cropWidth = [int][Math]::Round($sourceHeight * $targetRatio)
        $x = [int][Math]::Round(($sourceWidth - $cropWidth) / 2)
        return New-Object System.Drawing.Rectangle $x, 0, $cropWidth, $sourceHeight
    }

    $cropHeight = [int][Math]::Round($sourceWidth / $targetRatio)
    $y = [int][Math]::Round(($sourceHeight - $cropHeight) / 2)
    return New-Object System.Drawing.Rectangle 0, $y, $sourceWidth, $cropHeight
}

function Get-TargetSize {
    param(
        [System.Drawing.Rectangle]$SourceRectangle,
        [object]$Settings
    )

    $targetWidth = [int]$Settings.width
    $targetHeight = [int]$Settings.height

    if ($targetWidth -gt 0 -and $targetHeight -gt 0) {
        return New-Object System.Drawing.Size $targetWidth, $targetHeight
    }

    if ($targetWidth -gt 0) {
        $height = [int][Math]::Round($SourceRectangle.Height * ($targetWidth / $SourceRectangle.Width))
        return New-Object System.Drawing.Size $targetWidth, $height
    }

    if ($targetHeight -gt 0) {
        $width = [int][Math]::Round($SourceRectangle.Width * ($targetHeight / $SourceRectangle.Height))
        return New-Object System.Drawing.Size $width, $targetHeight
    }

    return New-Object System.Drawing.Size $SourceRectangle.Width, $SourceRectangle.Height
}

function Get-CoverSourceRectangle {
    param(
        [System.Drawing.Image]$Image,
        [System.Drawing.Size]$TargetSize
    )

    $sourceWidth = $Image.Width
    $sourceHeight = $Image.Height
    $sourceRatio = $sourceWidth / $sourceHeight
    $targetRatio = $TargetSize.Width / $TargetSize.Height

    if ($sourceRatio -gt $targetRatio) {
        $cropWidth = [int][Math]::Round($sourceHeight * $targetRatio)
        $x = [int][Math]::Round(($sourceWidth - $cropWidth) / 2)
        return New-Object System.Drawing.Rectangle $x, 0, $cropWidth, $sourceHeight
    }

    $cropHeight = [int][Math]::Round($sourceWidth / $targetRatio)
    $y = [int][Math]::Round(($sourceHeight - $cropHeight) / 2)
    return New-Object System.Drawing.Rectangle 0, $y, $sourceWidth, $cropHeight
}

function Get-FitDestinationRectangle {
    param(
        [System.Drawing.Image]$Image,
        [System.Drawing.Size]$TargetSize
    )

    $scale = [Math]::Min(($TargetSize.Width / $Image.Width), ($TargetSize.Height / $Image.Height))
    $width = [int][Math]::Round($Image.Width * $scale)
    $height = [int][Math]::Round($Image.Height * $scale)
    $x = [int][Math]::Round(($TargetSize.Width - $width) / 2)
    $y = [int][Math]::Round(($TargetSize.Height - $height) / 2)

    return New-Object System.Drawing.Rectangle $x, $y, $width, $height
}

function Get-BackgroundColor {
    param([object]$Settings)

    $colorText = "#f2eadc"
    if ($Settings.PSObject.Properties.Name -contains "backgroundColor" -and -not [string]::IsNullOrWhiteSpace($Settings.backgroundColor)) {
        $colorText = [string]$Settings.backgroundColor
    }

    try {
        return [System.Drawing.ColorTranslator]::FromHtml($colorText)
    }
    catch {
        return [System.Drawing.Color]::FromArgb(242, 234, 220)
    }
}

function Get-ColorMatrix {
    param([object]$Settings)

    $brightness = [double]$Settings.brightness
    $contrast = [double]$Settings.contrast
    $saturation = [double]$Settings.saturation
    $warmth = [double]$Settings.warmth

    if ($contrast -le 0) { $contrast = 1.0 }
    if ($saturation -le 0) { $saturation = 1.0 }

    $lumR = 0.299
    $lumG = 0.587
    $lumB = 0.114
    $inverseSat = 1.0 - $saturation
    $translation = (0.5 * (1.0 - $contrast)) + $brightness

    $matrix = New-Object System.Drawing.Imaging.ColorMatrix

    $matrix.Matrix00 = [single](($lumR * $inverseSat + $saturation) * $contrast)
    $matrix.Matrix01 = [single](($lumR * $inverseSat) * $contrast)
    $matrix.Matrix02 = [single](($lumR * $inverseSat) * $contrast)
    $matrix.Matrix03 = 0
    $matrix.Matrix04 = 0

    $matrix.Matrix10 = [single](($lumG * $inverseSat) * $contrast)
    $matrix.Matrix11 = [single](($lumG * $inverseSat + $saturation) * $contrast)
    $matrix.Matrix12 = [single](($lumG * $inverseSat) * $contrast)
    $matrix.Matrix13 = 0
    $matrix.Matrix14 = 0

    $matrix.Matrix20 = [single](($lumB * $inverseSat) * $contrast)
    $matrix.Matrix21 = [single](($lumB * $inverseSat) * $contrast)
    $matrix.Matrix22 = [single](($lumB * $inverseSat + $saturation) * $contrast)
    $matrix.Matrix23 = 0
    $matrix.Matrix24 = 0

    $matrix.Matrix30 = 0
    $matrix.Matrix31 = 0
    $matrix.Matrix32 = 0
    $matrix.Matrix33 = 1
    $matrix.Matrix34 = 0

    $matrix.Matrix40 = [single]($translation + $warmth)
    $matrix.Matrix41 = [single]$translation
    $matrix.Matrix42 = [single]($translation - ($warmth * 0.7))
    $matrix.Matrix43 = 0
    $matrix.Matrix44 = 1

    return $matrix
}

function New-ResizedBitmap {
    param(
        [System.Drawing.Image]$Image,
        [System.Drawing.Rectangle]$SourceRectangle,
        [System.Drawing.Size]$TargetSize,
        [object]$Settings
    )

    $bitmap = New-Object System.Drawing.Bitmap $TargetSize.Width, $TargetSize.Height, ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $attributes = New-Object System.Drawing.Imaging.ImageAttributes

    try {
        $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

        $destination = New-Object System.Drawing.Rectangle 0, 0, $TargetSize.Width, $TargetSize.Height
        $matrix = Get-ColorMatrix -Settings $Settings
        $attributes.SetColorMatrix($matrix, [System.Drawing.Imaging.ColorMatrixFlag]::Default, [System.Drawing.Imaging.ColorAdjustType]::Bitmap)

        if ($Settings.crop -eq "fit" -and $TargetSize.Width -gt 0 -and $TargetSize.Height -gt 0) {
            $backgroundColor = Get-BackgroundColor -Settings $Settings
            $graphics.Clear($backgroundColor)

            if ($Settings.background -eq "blur") {
                $coverSource = Get-CoverSourceRectangle -Image $Image -TargetSize $TargetSize
                $smallWidth = [Math]::Max(24, [int][Math]::Round($TargetSize.Width / 18))
                $smallHeight = [Math]::Max(24, [int][Math]::Round($TargetSize.Height / 18))
                $small = New-Object System.Drawing.Bitmap $smallWidth, $smallHeight, ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
                $smallGraphics = [System.Drawing.Graphics]::FromImage($small)

                try {
                    $smallGraphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
                    $smallGraphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                    $smallGraphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
                    $smallGraphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

                    $smallDest = New-Object System.Drawing.Rectangle 0, 0, $smallWidth, $smallHeight
                    $smallGraphics.DrawImage(
                        $Image,
                        $smallDest,
                        $coverSource.X,
                        $coverSource.Y,
                        $coverSource.Width,
                        $coverSource.Height,
                        [System.Drawing.GraphicsUnit]::Pixel,
                        $attributes
                    )
                }
                finally {
                    $smallGraphics.Dispose()
                }

                $graphics.DrawImage($small, $destination)
                $small.Dispose()

                $overlayAlpha = 70
                if ($Settings.PSObject.Properties.Name -contains "backgroundOverlayAlpha") {
                    $overlayAlpha = [int]$Settings.backgroundOverlayAlpha
                }

                $overlayBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb($overlayAlpha, $backgroundColor.R, $backgroundColor.G, $backgroundColor.B))
                try {
                    $graphics.FillRectangle($overlayBrush, $destination)
                }
                finally {
                    $overlayBrush.Dispose()
                }
            }

            $fitDestination = Get-FitDestinationRectangle -Image $Image -TargetSize $TargetSize
            $graphics.DrawImage(
                $Image,
                $fitDestination,
                0,
                0,
                $Image.Width,
                $Image.Height,
                [System.Drawing.GraphicsUnit]::Pixel,
                $attributes
            )

            return $bitmap
        }

        $graphics.DrawImage(
            $Image,
            $destination,
            $SourceRectangle.X,
            $SourceRectangle.Y,
            $SourceRectangle.Width,
            $SourceRectangle.Height,
            [System.Drawing.GraphicsUnit]::Pixel,
            $attributes
        )
    }
    finally {
        $attributes.Dispose()
        $graphics.Dispose()
    }

    return $bitmap
}

function Save-Image {
    param(
        [System.Drawing.Bitmap]$Bitmap,
        [string]$Path,
        [object]$Settings
    )

    if ($Settings.format -eq "png") {
        $Bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
        return
    }

    $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() |
        Where-Object { $_.MimeType -eq "image/jpeg" } |
        Select-Object -First 1

    $quality = [long]$Settings.quality
    if ($quality -le 0) {
        $quality = 92
    }

    $encoder = [System.Drawing.Imaging.Encoder]::Quality
    $encoderParameters = New-Object System.Drawing.Imaging.EncoderParameters 1
    $encoderParameters.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter $encoder, $quality

    try {
        $Bitmap.Save($Path, $codec, $encoderParameters)
    }
    finally {
        $encoderParameters.Dispose()
    }
}

$files = Get-InputFiles -InputPath $InputPath
if (-not $files -or $files.Count -eq 0) {
    Write-Output "No supported images found in $InputPath"
    exit 0
}

$logPath = Join-Path $logDir ("run_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
$processed = 0

foreach ($file in $files) {
    $image = $null
    $bitmap = $null

    try {
        $image = [System.Drawing.Image]::FromFile($file.FullName)
        $sourceRectangle = Get-SourceRectangle -Image $image -Settings $settings
        $targetSize = Get-TargetSize -SourceRectangle $sourceRectangle -Settings $settings
        $outputPath = Get-OutputPath -File $file -Settings $settings -OutputDir $OutputDir -Overwrite:$Overwrite.IsPresent

        $bitmap = New-ResizedBitmap -Image $image -SourceRectangle $sourceRectangle -TargetSize $targetSize -Settings $settings
        Save-Image -Bitmap $bitmap -Path $outputPath -Settings $settings

        $message = "OK | $($file.Name) | $($image.Width)x$($image.Height) -> $($targetSize.Width)x$($targetSize.Height) | $outputPath"
        Add-Content -LiteralPath $logPath -Value $message -Encoding UTF8
        Write-Output $message
        $processed++
    }
    catch {
        $message = "ERROR | $($file.Name) | $($_.Exception.Message)"
        Add-Content -LiteralPath $logPath -Value $message -Encoding UTF8
        Write-Output $message
    }
    finally {
        if ($bitmap -ne $null) { $bitmap.Dispose() }
        if ($image -ne $null) { $image.Dispose() }
    }
}

Write-Output "Done. Processed: $processed. Log: $logPath"
