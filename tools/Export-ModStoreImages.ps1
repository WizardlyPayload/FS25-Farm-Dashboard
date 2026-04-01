#Requires -Version 5.1
<#
.SYNOPSIS
  Copy shop-style thumbnails from LOCAL FS25 mod folders into one folder as PNG for Farm Dashboard.

.DESCRIPTION
  - Only reads files under your PC's Farming Simulator 2025 "mods" directory (no HTTP, no Mod Hub).
  - Prefers shop/store images: store_<name>.png and store_<name>.dds (not small icon_<name>.dds unless -IncludeIconDds).
  - PNG: Giants-style store_<rest>.png and paths under \store\ (see Test-StoreLikeTexture). Optional \textures\icon\ via -IncludeIconPng.
  - DDS: store_<rest>.dds (primary). Requires ImageMagick (magick) or DirectXTex texconv - see -TexconvPath. icon_*.dds only with -IncludeIconDds.
  - Scans ALL .zip files under ModsRoot at any depth. Unpacked mods: top-level folders, recursive files.
  - Output filenames use ModFolder__<title>.png when store XML maps store_*.dds / store_*.png (and optionally icon_*) to <name><en> (or modDesc <title>); otherwise ModFolder__<original texture name>.png.
  - If the destination PNG already exists in OutputDir, that texture is skipped (no copy/convert). Use -Force to overwrite.

.PARAMETER IncludeIconDds
  When set, also includes icon_*.dds and DDS under \textures\icon\ (default: store_*.dds only).

.PARAMETER IncludeIconPng
  When set, also includes PNGs under \textures\icon\ and mod icon.png / modicon.png (default: store-oriented paths only).

.PARAMETER OnlyStorePrefixedPng
  If set, only copies PNGs whose filename matches store_*.png (no DDS).

.PARAMETER OnlyIconPrefixedDds
  If set, only processes icon_*.dds (converted to PNG). Skips PNG discovery.

.PARAMETER IncludeDds
  When true (default), include store_*.dds and convert to PNG. Set to false to copy PNG rules only. Use -IncludeIconDds to add icon_*.dds.

.PARAMETER TexconvPath
  Full path to texconv.exe if not on PATH (DirectXTex). Used when magick is not available.

.PARAMETER MagickPath
  Full path to magick.exe if PATH is stale (common in Cursor/VS Code: restart terminal, or use this).

.PARAMETER ModsRoot
  Default: Documents\My Games\FarmingSimulator2025\mods

.PARAMETER OutputDir
  Where to write PNGs (default: repo web\assests\img\items_mod_extract).

.PARAMETER DryRun
  List actions without copying or converting.

.PARAMETER Force
  Overwrite existing PNGs in OutputDir. Default: skip copy/convert when the destination file already exists.

.PARAMETER MaxFileSizeMB
  Skip very large files (likely full textures, not shop icons).

.EXAMPLE
  .\tools\Export-ModStoreImages.ps1 -DryRun
  .\tools\Export-ModStoreImages.ps1 -OnlyIconPrefixedDds -DryRun
  .\tools\Export-ModStoreImages.ps1 -TexconvPath "C:\Tools\texconv.exe"
#>

[CmdletBinding()]
param(
    [string] $ModsRoot = $(Join-Path $env:USERPROFILE "Documents\My Games\FarmingSimulator2025\mods"),
    [string] $OutputDir = "",
    [switch] $DryRun,
    [int] $MaxFileSizeMB = 8,
    [switch] $OnlyStorePrefixedPng,
    [switch] $OnlyIconPrefixedDds,
    [switch] $IncludeIconDds,
    [switch] $IncludeIconPng,
    [bool] $IncludeDds = $true,
    [string] $TexconvPath = "",
    [string] $MagickPath = "",
    [string] $SummaryJsonPath = "",
    [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Default output: MAIN CODEBASE layout, or public GitHub clone (`FS25_Dashboard APP`).
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $_main = Join-Path $PSScriptRoot "..\FS25_FarmDashboard_App\FS25_FarmDashboard_App\web\assests\img\items_mod_extract"
    $_git  = Join-Path $PSScriptRoot "..\FS25_Dashboard APP\web\assests\img\items_mod_extract"
    if (Test-Path -LiteralPath (Split-Path -Parent $_main)) {
        $OutputDir = $_main
    }
    elseif (Test-Path -LiteralPath (Split-Path -Parent $_git)) {
        $OutputDir = $_git
    }
    else {
        $OutputDir = $_main
    }
}

# UTF-8 stdout so Electron/Node can split lines reliably (PS 5.1 defaults vary).
try {
    $utf8Out = New-Object System.Text.UTF8Encoding $false
    [Console]::OutputEncoding = $utf8Out
    $OutputEncoding = $utf8Out
} catch { }

$script:TextureActionCount = 0
$script:PngCopied = 0
$script:DdsConverted = 0
$script:OutputsSkippedAlreadyExist = 0
$script:DdsSkippedNoConverter = 0
$script:DdsConvertFailed = 0
$script:DdsConverter = $null   # 'magick' | 'texconv' | $null
$script:TexconvExe = $null
$script:MagickExe = $null       # full path to magick.exe when using ImageMagick
$script:ForceExport = [bool]$Force

function Update-SessionPathFromRegistry {
    # Terminals started from an IDE often keep an old PATH (before ImageMagick installer ran).
    $machine = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $user = [System.Environment]::GetEnvironmentVariable("Path", "User")
    if (-not [string]::IsNullOrWhiteSpace($machine) -or -not [string]::IsNullOrWhiteSpace($user)) {
        $env:Path = "$machine;$user;$env:Path"
    }
}

function Resolve-MagickExe {
    param([string] $ExplicitPath)
    if ($ExplicitPath -and (Test-Path -LiteralPath $ExplicitPath)) {
        return (Resolve-Path -LiteralPath $ExplicitPath).Path
    }
    Update-SessionPathFromRegistry

    foreach ($name in @("magick.exe", "magick")) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd -and $cmd.Source -and (Test-Path -LiteralPath $cmd.Source)) {
            return $cmd.Source
        }
    }

    $whereCmd = Get-Command where.exe -ErrorAction SilentlyContinue
    if ($whereCmd) {
        try {
            $lines = & where.exe magick 2>$null
            foreach ($line in $lines) {
                if ($line -and (Test-Path -LiteralPath $line.Trim())) {
                    return $line.Trim()
                }
            }
        }
        catch { }
    }

    $pf64 = [Environment]::GetEnvironmentVariable("ProgramFiles")
    $pf32 = [Environment]::GetEnvironmentVariable("ProgramFiles(x86)")
    foreach ($root in @($pf64, $pf32)) {
        if ([string]::IsNullOrWhiteSpace($root)) { continue }
        # PS 5.1: avoid -LiteralPath + -Filter together (invalid parameter set).
        $dirs = @(Get-ChildItem -Path $root -Directory -Filter "ImageMagick*" -ErrorAction SilentlyContinue)
        foreach ($d in $dirs) {
            $candidate = Join-Path $d.FullName "magick.exe"
            if (Test-Path -LiteralPath $candidate) {
                return $candidate
            }
        }
    }

    return $null
}

function Sanitize-FileNamePart([string] $s) {
    if ([string]::IsNullOrWhiteSpace($s)) { return "mod" }
    $s = $s -replace '[<>:"/\\|?*]', '_'
    $s = $s.Trim()
    if ($s.Length -gt 80) { $s = $s.Substring(0, 80) }
    return $s
}

function Write-FdExportJson([hashtable] $Payload) {
    $json = $Payload | ConvertTo-Json -Compress -Depth 8
    if ([string]::IsNullOrWhiteSpace($json)) { $json = '{}' }
    Write-Output ("FD_JSON " + $json)
}

function Initialize-DdsConverter {
    $script:MagickExe = $null
    if (-not $IncludeDds) {
        $script:DdsConverter = $null
        return
    }
    $resolved = Resolve-MagickExe -ExplicitPath $MagickPath
    if ($resolved) {
        $script:MagickExe = $resolved
        $script:DdsConverter = 'magick'
        return
    }
    if ($TexconvPath -and (Test-Path -LiteralPath $TexconvPath)) {
        $script:DdsConverter = 'texconv'
        $script:TexconvExe = $TexconvPath
        return
    }
    if (Get-Command texconv -ErrorAction SilentlyContinue) {
        $script:DdsConverter = 'texconv'
        $script:TexconvExe = (Get-Command texconv).Source
        return
    }
    $script:DdsConverter = $null
}

function Test-StoreLikeTexture {
    param(
        [string] $FullPath,
        [string] $FileName,
        [long] $Length
    )
    $maxBytes = $MaxFileSizeMB * 1MB
    if ($Length -gt $maxBytes) { return $null }
    $fn = $FileName.ToLowerInvariant()
    $fp = $FullPath.ToLowerInvariant()

    if ($OnlyIconPrefixedDds) {
        if ($IncludeDds -and ($fn -match '^icon_.+\.dds$')) {
            return 'dds'
        }
        return $null
    }

    if ($fn -match '\.dds$') {
        if (-not $IncludeDds) { return $null }
        if ($OnlyStorePrefixedPng) { return $null }
        if ($fn -match '^store_.+\.dds$') {
            return 'dds'
        }
        if ($fp -match '\\textures\\store\\' -and $fn -match '\.dds$') {
            return 'dds'
        }
        if ($IncludeIconDds -and ($fn -match '^icon_.+\.dds$')) {
            return 'dds'
        }
        if ($IncludeIconDds -and ($fp -match '\\textures\\icon' -and $fn -match '(icon|preview|store|shop|thumbnail)')) {
            return 'dds'
        }
        return $null
    }

    if ($fn -notmatch '\.png$') { return $null }

    if ($fn -match '^store_.+\.png$') {
        return 'png'
    }
    if ($OnlyStorePrefixedPng) {
        return $null
    }

    if ($fp -match '\\store\\') { return 'png' }
    if ($IncludeIconPng -and ($fp -match '\\textures\\icon')) { return 'png' }
    if ($fn -match 'store|preview|shop|thumbnail|modhub|overview') { return 'png' }
    if ($fn -eq 'store.png') { return 'png' }
    if ($IncludeIconPng -and ($fn -eq 'icon.png' -or $fn -eq 'modicon.png')) { return 'png' }
    return $null
}

function Get-DestLeafForTexture {
    param([string] $OriginalName, [string] $Kind)
    if ($Kind -eq 'dds') {
        return [System.IO.Path]::ChangeExtension($OriginalName, ".png")
    }
    return $OriginalName
}

<#
  Parse FS mod XML to map texture base names (e.g. store_flexDraper, icon_flexDraper) to English store titles (<name><en>...</en>).
  Reduces wrong thumbnails when one pack contains many vehicles (fuzzy match was picking another icon).
#>
function Merge-TextureDisplayNamesFromXmlContent {
    param([string] $Content, [hashtable] $Map)
    if ([string]::IsNullOrWhiteSpace($Content)) { return }

    $parts = $Content -split '(?=<(?:storeItem|vehicle|implement|tractor|trailer|combine|cutter|fillType|fillUnit|placeable|sprayer|baler|tipper|woodHarvester)\b)'
    foreach ($part in $parts) {
        if ($part.Length -lt 25) { continue }
        $en = $null
        if ($part -match '<name>\s*<en>([^<]+)</en>') {
            $en = $Matches[1].Trim()
        }
        elseif ($part -match '<name[^>]*>\s*<en>([^<]+)</en>') {
            $en = $Matches[1].Trim()
        }
        elseif ($part -match '<name[^>]*>\s*<de>([^<]+)</de>') {
            $en = $Matches[1].Trim()
        }
        if (-not $en) { continue }

        foreach ($m in [regex]::Matches($part, '([A-Za-z0-9_\-\.\$\\\/]+(?:icon|store|preview|shop|thumbnail)[A-Za-z0-9_\-\.\$\\\/]*\.(?:dds|png))')) {
            $raw = $m.Groups[1].Value -replace '\$', ''
            $fn = [System.IO.Path]::GetFileName($raw)
            $bk = [System.IO.Path]::GetFileNameWithoutExtension($fn).ToLowerInvariant()
            if ($bk.Length -gt 0 -and -not $Map.ContainsKey($bk)) {
                $Map[$bk] = $en
            }
        }
        foreach ($m in [regex]::Matches($part, '\b(store_[A-Za-z0-9_\-]+\.(?:dds|png)|icon_[A-Za-z0-9_\-]+\.dds)\b')) {
            $bk = [System.IO.Path]::GetFileNameWithoutExtension($m.Value).ToLowerInvariant()
            if ($bk.Length -gt 0 -and -not $Map.ContainsKey($bk)) {
                $Map[$bk] = $en
            }
        }
    }

    if ($Content -match '<name>\s*<en>([^<]+)</en>') {
        $one = $Matches[1].Trim()
        foreach ($m in [regex]::Matches($Content, '\b(store_[A-Za-z0-9_\-]+\.(?:dds|png)|icon_[A-Za-z0-9_\-]+\.dds)\b')) {
            $bk = [System.IO.Path]::GetFileNameWithoutExtension($m.Value).ToLowerInvariant()
            if ($bk.Length -gt 0 -and -not $Map.ContainsKey($bk)) {
                $Map[$bk] = $one
            }
        }
    }

    if ($Content -match '<title>\s*<en>([^<]+)</en>') {
        $titleEn = $Matches[1].Trim()
        foreach ($m in [regex]::Matches($Content, '\b(store_[A-Za-z0-9_\-]+\.(?:dds|png)|icon_[A-Za-z0-9_\-]+\.dds)\b')) {
            $bk = [System.IO.Path]::GetFileNameWithoutExtension($m.Value).ToLowerInvariant()
            if ($bk.Length -gt 0 -and -not $Map.ContainsKey($bk)) {
                $Map[$bk] = $titleEn
            }
        }
    }
}

function Build-TextureDisplayNameMapFromModFolder {
    param([string] $ModPath)
    $map = @{}
    if (-not (Test-Path -LiteralPath $ModPath)) { return $map }
    $xmlFiles = @(Get-ChildItem -LiteralPath $ModPath -Recurse -File -Filter *.xml -ErrorAction SilentlyContinue |
            Where-Object { $_.Length -lt 450000 -and $_.Length -gt 0 } | Select-Object -First 350)
    foreach ($xf in $xmlFiles) {
        try {
            $content = [System.IO.File]::ReadAllText($xf.FullName)
        }
        catch {
            continue
        }
        Merge-TextureDisplayNamesFromXmlContent -Content $content -Map $map
    }
    return $map
}

function Build-TextureDisplayNameMapFromZipArchive {
    param([System.IO.Compression.ZipArchive] $Zip)
    $map = @{}
    $xmlEntries = @($Zip.Entries | Where-Object {
            $_.FullName -match '\.xml$' -and -not $_.FullName.EndsWith('/') -and $_.Length -gt 0 -and $_.Length -lt 450000
        })
    foreach ($ent in $xmlEntries) {
        $content = $null
        $sr = $null
        try {
            $sr = New-Object System.IO.StreamReader($ent.Open())
            $content = $sr.ReadToEnd()
        }
        catch {
            $content = $null
        }
        finally {
            if ($null -ne $sr) { $sr.Dispose() }
        }
        if ($null -ne $content) {
            Merge-TextureDisplayNamesFromXmlContent -Content $content -Map $map
        }
    }
    return $map
}

function Resolve-LeafPngForExport {
    param(
        [hashtable] $DisplayNameMap,
        [string] $TextureFileName,
        [string] $LeafPngFromTexture
    )
    $texBase = [System.IO.Path]::GetFileNameWithoutExtension($TextureFileName).ToLowerInvariant()
    if ($DisplayNameMap -and $DisplayNameMap.ContainsKey($texBase)) {
        $display = $DisplayNameMap[$texBase]
        if (-not [string]::IsNullOrWhiteSpace($display)) {
            return (Sanitize-FileNamePart ($display + ".png"))
        }
    }
    return (Sanitize-FileNamePart $LeafPngFromTexture)
}

function Format-Win32CommandLineArg {
    param([string] $Text)
    if ($null -eq $Text) { return '""' }
    if ($Text -notmatch '[\s"]') { return $Text }
    return '"' + ($Text -replace '"', '\"') + '"'
}

function Invoke-Win32Process {
    param(
        [string] $FilePath,
        [string[]] $ArgumentList
    )
    $argLine = ($ArgumentList | ForEach-Object { Format-Win32CommandLineArg $_ }) -join ' '
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo.FileName = $FilePath
    $p.StartInfo.Arguments = $argLine
    $p.StartInfo.UseShellExecute = $false
    $p.StartInfo.CreateNoWindow = $true
    # Do not redirect streams: synchronous ReadToEnd() can deadlock if the child fills stderr.
    [void]$p.Start()
    $p.WaitForExit()
    return @{
        ExitCode = $p.ExitCode
        StdOut   = ""
        StdErr   = ""
    }
}

function Ensure-DirectoryExists {
    param([string] $DirectoryPath)
    if ([string]::IsNullOrEmpty($DirectoryPath)) { return }
    if (-not (Test-Path -LiteralPath $DirectoryPath)) {
        [void][System.IO.Directory]::CreateDirectory($DirectoryPath)
    }
}

function Convert-DdsFileToPng {
    param([string] $SourcePath, [string] $DestPngPath)

    # Avoid Split-Path/New-Item here: some PS 5.1 hosts throw "Parameter set cannot be resolved"
    # on Split-Path -LiteralPath -Parent with certain paths.
    $parent = [System.IO.Path]::GetDirectoryName($DestPngPath)
    if ([string]::IsNullOrEmpty($parent)) {
        throw "Invalid output path (no directory): $DestPngPath"
    }
    Ensure-DirectoryExists -DirectoryPath $parent

    if ($script:DdsConverter -eq 'magick') {
        $exe = $script:MagickExe
        if (-not $exe) { throw "magick.exe path not set" }
        $r = Invoke-Win32Process -FilePath $exe -ArgumentList @($SourcePath, $DestPngPath)
        $code = $r.ExitCode
        if (-not (Test-Path -LiteralPath $DestPngPath)) {
            throw "magick did not create output (exit $code). If DDS is BC7/unsupported, try -TexconvPath to texconv.exe."
        }
        if ($null -ne $code -and $code -ne 0) {
            throw "magick exited with code $code"
        }
        return
    }

    if ($script:DdsConverter -eq 'texconv') {
        $tempOut = Join-Path $env:TEMP ("fd_texconv_" + [Guid]::NewGuid().ToString("N"))
        [void][System.IO.Directory]::CreateDirectory($tempOut)
        try {
            $tex = $script:TexconvExe
            $r = Invoke-Win32Process -FilePath $tex -ArgumentList @("-nologo", "-y", "-ft", "png", "-o", $tempOut, $SourcePath)
            if ($r.ExitCode -ne 0) {
                throw "texconv exited with code $($r.ExitCode)"
            }
            $base = [System.IO.Path]::GetFileNameWithoutExtension($SourcePath)
            $candidate = Join-Path $tempOut ($base + ".png")
            if (-not (Test-Path -LiteralPath $candidate)) {
                $first = Get-ChildItem -Path $tempOut -Filter *.png -File -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($first) { $candidate = $first.FullName }
            }
            if (-not (Test-Path -LiteralPath $candidate)) {
                throw "texconv did not produce a PNG for $SourcePath"
            }
            Copy-Item -LiteralPath $candidate -Destination $DestPngPath -Force
        }
        finally {
            Remove-Item -LiteralPath $tempOut -Recurse -Force -ErrorAction SilentlyContinue
        }
        return
    }

    throw "No DDS converter (install ImageMagick or pass -TexconvPath to texconv.exe)"
}

function Copy-FromModDirectory {
    param([string] $ModPath, [string] $ModKey, [string] $DestRoot, [switch] $Dry)

    $files = Get-ChildItem -LiteralPath $ModPath -Recurse -File -ErrorAction SilentlyContinue |
        ForEach-Object {
            $k = Test-StoreLikeTexture -FullPath $_.FullName -FileName $_.Name -Length $_.Length
            if ($k) { [pscustomobject]@{ File = $_; Kind = $k } }
        }

    $displayMap = Build-TextureDisplayNameMapFromModFolder -ModPath $ModPath

    foreach ($row in $files) {
        $f = $row.File
        $kind = $row.Kind
        $leafPng = Get-DestLeafForTexture -OriginalName $f.Name -Kind $kind
        $base = Sanitize-FileNamePart $ModKey
        $leaf = Resolve-LeafPngForExport -DisplayNameMap $displayMap -TextureFileName $f.Name -LeafPngFromTexture $leafPng
        $destName = "${base}__${leaf}"
        $dest = Join-Path $DestRoot $destName

        if ($kind -eq 'dds' -and -not $Dry -and -not $script:DdsConverter) {
            $script:DdsSkippedNoConverter++
            Write-Warning "Skip DDS (no converter): $($f.FullName)"
            continue
        }

        if (-not $script:ForceExport -and -not $Dry -and (Test-Path -LiteralPath $dest)) {
            $script:OutputsSkippedAlreadyExist++
            Write-Output "[Skip] $destName (already exists)"
            continue
        }

        if ($Dry) {
            if (-not $script:ForceExport -and (Test-Path -LiteralPath $dest)) {
                Write-Output "[DryRun] SKIP (exists) $destName"
                continue
            }
            $script:TextureActionCount++
            if ($kind -eq 'dds') {
                Write-Output "[DryRun] DDS->PNG $($f.FullName) -> $dest"
            }
            else {
                Write-Output "[DryRun] COPY $($f.FullName) -> $dest"
            }
            continue
        }

        $script:TextureActionCount++

        if ($kind -eq 'png') {
            Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
            $script:PngCopied++
            Write-Output "[OK] $destName"
        }
        else {
            try {
                Convert-DdsFileToPng -SourcePath $f.FullName -DestPngPath $dest
                $script:DdsConverted++
                Write-Output "[OK] $destName (from DDS)"
            }
            catch {
                $script:DdsConvertFailed++
                Write-Warning "DDS convert failed: $($f.FullName) - $($_.Exception.Message)"
            }
        }
    }
}

function Expand-TexturesFromZip {
    param([string] $ZipPath, [string] $ModKey, [string] $DestRoot, [switch] $Dry)

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    }
    catch {
        Write-Warning "Skip zip (open failed): $ZipPath"
        return
    }
    try {
        $displayMap = Build-TextureDisplayNameMapFromZipArchive -Zip $zip

        foreach ($e in $zip.Entries) {
            if ($e.FullName.EndsWith('/')) { continue }
            if ($e.Length -gt ($MaxFileSizeMB * 1MB)) { continue }
            # Parentheses required: commas inside GetFileName(...) would be parsed as multiple arguments.
            $zipEntryPath = $e.FullName -replace '/', [System.IO.Path]::DirectorySeparatorChar
            $name = [System.IO.Path]::GetFileName($zipEntryPath)
            $fakePath = ($e.FullName -replace '/', '\')
            $kind = Test-StoreLikeTexture -FullPath $fakePath -FileName $name -Length $e.Length
            if (-not $kind) { continue }

            $leafPng = Get-DestLeafForTexture -OriginalName $name -Kind $kind
            $base = Sanitize-FileNamePart $ModKey
            $leaf = Resolve-LeafPngForExport -DisplayNameMap $displayMap -TextureFileName $name -LeafPngFromTexture $leafPng
            $destName = "${base}__${leaf}"
            $dest = Join-Path $DestRoot $destName

            if ($kind -eq 'dds' -and -not $Dry -and -not $script:DdsConverter) {
                $script:DdsSkippedNoConverter++
                Write-Warning "Skip DDS in zip (no converter): $($e.FullName) in $ZipPath"
                continue
            }

            if (-not $script:ForceExport -and -not $Dry -and (Test-Path -LiteralPath $dest)) {
                $script:OutputsSkippedAlreadyExist++
                Write-Output "[Skip] $destName (already exists)"
                continue
            }

            if ($Dry) {
                if (-not $script:ForceExport -and (Test-Path -LiteralPath $dest)) {
                    Write-Output "[DryRun] SKIP (exists) $destName"
                    continue
                }
                $script:TextureActionCount++
                if ($kind -eq 'dds') {
                    Write-Output "[DryRun] ZIP DDS->PNG $($e.FullName) -> $dest"
                }
                else {
                    Write-Output "[DryRun] ZIP $($e.FullName) -> $dest"
                }
                continue
            }

            $script:TextureActionCount++

            $dir = [System.IO.Path]::GetDirectoryName($dest)
            if (-not [string]::IsNullOrEmpty($dir)) {
                Ensure-DirectoryExists -DirectoryPath $dir
            }

            if ($kind -eq 'png') {
                try {
                    $in = $e.Open()
                    $out = [System.IO.File]::Create($dest)
                    try {
                        $in.CopyTo($out)
                    }
                    finally {
                        $out.Dispose()
                        $in.Dispose()
                    }
                    $script:PngCopied++
                    Write-Output "[OK] $destName (from zip)"
                }
                catch {
                    Write-Warning "Extract failed: $($e.FullName)"
                }
                continue
            }

            $tmpDds = Join-Path $env:TEMP ("fd_zip_" + [Guid]::NewGuid().ToString("N") + ".dds")
            try {
                $in = $e.Open()
                $outF = [System.IO.File]::Create($tmpDds)
                try {
                    $in.CopyTo($outF)
                }
                finally {
                    $outF.Dispose()
                    $in.Dispose()
                }
                try {
                    Convert-DdsFileToPng -SourcePath $tmpDds -DestPngPath $dest
                    $script:DdsConverted++
                    Write-Output "[OK] $destName (DDS from zip)"
                }
                catch {
                    $script:DdsConvertFailed++
                    Write-Warning "DDS convert failed: $($e.FullName) - $($_.Exception.Message)"
                }
            }
            finally {
                Remove-Item -LiteralPath $tmpDds -Force -ErrorAction SilentlyContinue
            }
        }
    }
    finally {
        $zip.Dispose()
    }
}

function Write-SummaryJson {
    param(
        [bool] $Ok,
        [string] $ErrorMessage,
        [string] $ModsRootNormVal,
        [string] $OutputDirVal,
        [int] $TopFoldersCount,
        [int] $ZipCount
    )
    if (-not $SummaryJsonPath) { return }
    $parent = [System.IO.Path]::GetDirectoryName($SummaryJsonPath)
    if (-not [string]::IsNullOrEmpty($parent) -and -not (Test-Path -LiteralPath $parent)) {
        [void][System.IO.Directory]::CreateDirectory($parent)
    }
    $obj = [ordered]@{
        ok                        = $Ok
        textureMatches            = $script:TextureActionCount
        pngCopied                 = $script:PngCopied
        ddsConverted              = $script:DdsConverted
        outputsSkippedExisting    = $script:OutputsSkippedAlreadyExist
        ddsSkippedNoConverter     = $script:DdsSkippedNoConverter
        ddsConvertFailed          = $script:DdsConvertFailed
        topLevelModFolders        = $TopFoldersCount
        zipArchivesScanned        = $ZipCount
        modsRoot                  = $ModsRootNormVal
        outputDir                 = $OutputDirVal
        ddsConverter              = $script:DdsConverter
        dryRun                    = [bool]$DryRun
        forceExport               = [bool]$script:ForceExport
    }
    if ($ErrorMessage) { $obj.error = $ErrorMessage }
    # PS 5.1 Set-Content -Encoding utf8 writes a BOM; Node JSON.parse fails on BOM — write UTF-8 without BOM.
    $jsonText = $obj | ConvertTo-Json -Depth 4
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($SummaryJsonPath, $jsonText, $utf8NoBom)
}

# --- main ---
if (-not (Test-Path -LiteralPath $ModsRoot)) {
    $msg = "Mods folder not found: $ModsRoot"
    Write-Host "ERROR: $msg" -ForegroundColor Red
    Write-SummaryJson -Ok $false -ErrorMessage $msg -ModsRootNormVal $ModsRoot -OutputDirVal $OutputDir -TopFoldersCount 0 -ZipCount 0
    exit 1
}

$ModsRootNorm = ((Resolve-Path -LiteralPath $ModsRoot).Path).TrimEnd('\')

Initialize-DdsConverter

if (-not $DryRun) {
    if (-not (Test-Path -LiteralPath $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    }
}

Write-Host "ModsRoot : $ModsRootNorm"
Write-Host "OutputDir: $OutputDir"
Write-Host "DryRun   : $DryRun"
Write-Host "Include DDS (store_*.dds; -IncludeIconDds for icon_*.dds): $IncludeDds"
Write-Host "Include icon DDS        : $IncludeIconDds"
Write-Host "Include icon PNG paths    : $IncludeIconPng"
Write-Host "Only store_*.png        : $OnlyStorePrefixedPng"
Write-Host "Only icon_*.dds         : $OnlyIconPrefixedDds"
Write-Host "Force overwrite         : $script:ForceExport"
if ($IncludeDds) {
    if ($script:DdsConverter) {
        $detail = if ($script:DdsConverter -eq 'texconv') { " ($($script:TexconvExe))" }
                  elseif ($script:DdsConverter -eq 'magick' -and $script:MagickExe) { " ($($script:MagickExe))" }
                  else { "" }
        Write-Host "DDS converter          : $($script:DdsConverter)$detail"
    }
    else {
        Write-Host "DDS converter          : (none - see -MagickPath, or restart terminal after installing ImageMagick)"
    }
}
Write-Host ""

# 1) Discover unpacked mods + zip archives (single scan each; drives progress UI in Electron)
$top = @(Get-ChildItem -LiteralPath $ModsRootNorm -ErrorAction Stop)
$topFolders = @($top | Where-Object { $_.PSIsContainer })
$allZips = @(Get-ChildItem -LiteralPath $ModsRootNorm -Filter *.zip -Recurse -File -ErrorAction SilentlyContinue)
$fdTotalSteps = $topFolders.Count + $allZips.Count
Write-FdExportJson @{
    type       = 'init'
    totalSteps = $fdTotalSteps
    folderCount = $topFolders.Count
    zipCount   = $allZips.Count
}

$fdStep = 0
foreach ($folder in $topFolders) {
    $fdStep++
    Write-FdExportJson @{
        type    = 'step'
        current = $fdStep
        total   = $fdTotalSteps
        phase   = 'folder'
        label   = $folder.Name
    }
    Copy-FromModDirectory -ModPath $folder.FullName -ModKey $folder.Name -DestRoot $OutputDir -Dry:$DryRun
}

# 2) All zips at any depth
$zi = 0
foreach ($zip in $allZips) {
    $zi++
    $fdStep++
    Write-FdExportJson @{
        type    = 'step'
        current = $fdStep
        total   = $fdTotalSteps
        phase   = 'zip'
        label   = $zip.Name
    }
    if (($allZips.Count -gt 50) -and (($zi % 100) -eq 0 -or $zi -eq $allZips.Count)) {
        Write-Progress -Activity "Scanning mod zip files" -Status "$zi / $($allZips.Count) - $($zip.Name)" -PercentComplete ([math]::Min(100, [int](100 * $zi / [math]::Max(1, $allZips.Count))))
    }
    $rel = $zip.FullName.Substring($ModsRootNorm.Length).TrimStart('\')
    $keyFromPath = $rel -replace '\.zip$', ''
    $keyFromPath = $keyFromPath -replace '\\', '__'
    $modKey = Sanitize-FileNamePart $keyFromPath
    Expand-TexturesFromZip -ZipPath $zip.FullName -ModKey $modKey -DestRoot $OutputDir -Dry:$DryRun
}
if ($allZips.Count -gt 50) {
    Write-Progress -Activity "Scanning mod zip files" -Completed
}

Write-Host ""
Write-Output "Summary: $($script:TextureActionCount) texture match(es); PNG copied: $($script:PngCopied); DDS converted: $($script:DdsConverted); already exported (skipped): $($script:OutputsSkippedAlreadyExist); DDS skipped (no converter): $($script:DdsSkippedNoConverter); top-level folders: $($topFolders.Count); zip archives: $($allZips.Count)."
if ($script:TextureActionCount -eq 0 -and $script:OutputsSkippedAlreadyExist -eq 0) {
    Write-Host ""
    Write-Output "No matching files. Check ModsRoot, -OnlyIconPrefixedDds / -OnlyStorePrefixedPng, and that mods contain store_*.png / store_*.dds (or use -IncludeIconDds / -IncludeIconPng for icon textures)."
    if ($IncludeDds -and -not $script:DdsConverter) {
        Write-Output "For DDS: install ImageMagick, then restart this terminal (PATH refresh), or run: -MagickPath `"C:\Program Files\ImageMagick-7.x.x-Q16-HDRI\magick.exe`""
    }
}
Write-Host ""
Write-Output "Done. Review output PNGs; merge into assests/img/items or extend vehicles.js patterns as needed."
if ($DryRun) {
    Write-Output "Re-run without -DryRun to copy/convert files."
}

$outResolved = $OutputDir
if (Test-Path -LiteralPath $OutputDir) {
    try { $outResolved = ((Resolve-Path -LiteralPath $OutputDir).Path) } catch { }
}
Write-SummaryJson -Ok $true -ErrorMessage $null -ModsRootNormVal $ModsRootNorm -OutputDirVal $outResolved -TopFoldersCount $topFolders.Count -ZipCount $allZips.Count
