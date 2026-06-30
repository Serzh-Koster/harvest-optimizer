$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$labDir = Split-Path -Parent $scriptDir
$galleryPath = Join-Path $labDir "gallery.html"

$imageExtensions = @(".jpg", ".jpeg", ".png", ".bmp", ".gif", ".webp")

function Html-Escape {
    param([string]$Text)

    return [System.Net.WebUtility]::HtmlEncode($Text)
}

function Url-Segment {
    param([string]$Text)

    return [Uri]::EscapeDataString($Text).Replace("%2F", "/")
}

function Get-ImageFiles {
    param([string]$Folder)

    if (-not (Test-Path -LiteralPath $Folder)) {
        return @()
    }

    return Get-ChildItem -LiteralPath $Folder -File |
        Where-Object { $imageExtensions -contains $_.Extension.ToLowerInvariant() } |
        Sort-Object LastWriteTime -Descending
}

function Get-ImageSizeText {
    param([System.IO.FileInfo]$File)

    Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
    $image = $null

    try {
        $image = [System.Drawing.Image]::FromFile($File.FullName)
        return "{0}x{1}" -f $image.Width, $image.Height
    }
    catch {
        return "size unknown"
    }
    finally {
        if ($image -ne $null) {
            $image.Dispose()
        }
    }
}

function New-CardHtml {
    param(
        [System.IO.FileInfo]$File,
        [string]$FolderName
    )

    $safeName = Html-Escape $File.Name
    $href = "{0}/{1}" -f $FolderName, (Url-Segment $File.Name)
    $size = Html-Escape (Get-ImageSizeText -File $File)
    $date = Html-Escape ($File.LastWriteTime.ToString("yyyy-MM-dd HH:mm"))
    $kb = [Math]::Round($File.Length / 1KB)

    return @"
<article class="card">
  <a href="$href" target="_blank">
    <img src="$href" alt="$safeName" loading="lazy">
  </a>
  <div class="meta">
    <div class="name">$safeName</div>
    <div class="details">$size · $kb KB · $date</div>
  </div>
</article>
"@
}

$inbox = Get-ImageFiles -Folder (Join-Path $labDir "inbox")
$output = Get-ImageFiles -Folder (Join-Path $labDir "output")
$generatedAt = Html-Escape (Get-Date -Format "yyyy-MM-dd HH:mm:ss")

$inboxCards = ($inbox | ForEach-Object { New-CardHtml -File $_ -FolderName "inbox" }) -join "`n"
$outputCards = ($output | ForEach-Object { New-CardHtml -File $_ -FolderName "output" }) -join "`n"

if ([string]::IsNullOrWhiteSpace($inboxCards)) {
    $inboxCards = "<p class=""empty"">No images in inbox.</p>"
}

if ([string]::IsNullOrWhiteSpace($outputCards)) {
    $outputCards = "<p class=""empty"">No images in output.</p>"
}

$html = @"
<!doctype html>
<html lang="uk">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Photo Lab Gallery</title>
  <style>
    :root {
      color-scheme: light;
      font-family: Arial, sans-serif;
      background: #f5f1ea;
      color: #201c17;
    }

    body {
      margin: 0;
      padding: 28px;
    }

    header {
      display: flex;
      align-items: end;
      justify-content: space-between;
      gap: 20px;
      margin-bottom: 28px;
      border-bottom: 1px solid #d7cbbd;
      padding-bottom: 16px;
    }

    h1, h2, p {
      margin: 0;
    }

    h1 {
      font-size: 28px;
      font-weight: 700;
    }

    .stamp {
      color: #6c6257;
      font-size: 13px;
      white-space: nowrap;
    }

    section {
      margin: 28px 0 36px;
    }

    h2 {
      font-size: 18px;
      margin-bottom: 14px;
    }

    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(260px, 1fr));
      gap: 16px;
    }

    .card {
      background: #fffdf9;
      border: 1px solid #ded3c5;
      border-radius: 8px;
      overflow: hidden;
      box-shadow: 0 8px 22px rgba(43, 35, 26, 0.08);
    }

    .card img {
      display: block;
      width: 100%;
      height: 320px;
      object-fit: contain;
      background: #ebe4d9;
    }

    .meta {
      padding: 10px 12px 12px;
    }

    .name {
      font-size: 13px;
      line-height: 1.35;
      overflow-wrap: anywhere;
    }

    .details {
      margin-top: 6px;
      color: #6c6257;
      font-size: 12px;
    }

    .empty {
      color: #6c6257;
    }
  </style>
</head>
<body>
  <header>
    <div>
      <h1>Photo Lab Gallery</h1>
    </div>
    <p class="stamp">Updated $generatedAt</p>
  </header>

  <section>
    <h2>Inbox originals</h2>
    <div class="grid">
$inboxCards
    </div>
  </section>

  <section>
    <h2>Output variants</h2>
    <div class="grid">
$outputCards
    </div>
  </section>
</body>
</html>
"@

Set-Content -LiteralPath $galleryPath -Value $html -Encoding UTF8
Write-Output "Gallery: $galleryPath"
