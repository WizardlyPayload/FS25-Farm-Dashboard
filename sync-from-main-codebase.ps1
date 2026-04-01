# One-way sync: MAIN CODEBASE -> this Git clone (excludes node_modules and release folders).
# Run from PowerShell:  .\sync-from-main-codebase.ps1
# Optional: -MainRoot "path" -GitRoot "path"

param(
    [string]$MainRoot = "",
    [string]$GitRoot = ""
)

$ErrorActionPreference = "Stop"
if (-not $GitRoot) { $GitRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }

$candidates = @(
    (Join-Path $env:USERPROFILE "Documents\JoshWalki Farmdash server edit\MAIN CODEBASE"),
    (Join-Path $env:USERPROFILE "Documents\JoshWalki's Farmdash server edit\MAIN CODEBASE"),
    (Join-Path $env:USERPROFILE "Documents\JoshWalki’s Farmdash server edit\MAIN CODEBASE")
)
if ($MainRoot) {
    $srcRoot = $MainRoot
} else {
    $srcRoot = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $srcRoot) {
        Write-Error "Could not find MAIN CODEBASE. Pass -MainRoot 'full path to MAIN CODEBASE'."
    }
}

Write-Host "Source: $srcRoot"
Write-Host "Dest:   $GitRoot"

$appSrc = Join-Path $srcRoot "FS25_FarmDashboard_App\FS25_FarmDashboard_App"
$appDst = Join-Path $GitRoot "FS25_Dashboard APP"
$modSrc = Join-Path $srcRoot "FS25_FarmDashboard_Mod\FS25_FarmDashboard_Mod"
$modDst = Join-Path $GitRoot "FS25_Dashboard MOD"

if (-not (Test-Path -LiteralPath $appSrc)) { throw "Missing: $appSrc" }
if (-not (Test-Path -LiteralPath $modSrc)) { throw "Missing: $modSrc" }

function Invoke-RobocopyApp {
    param($S, $D)
    & robocopy $S $D /E /XD node_modules release /R:2 /W:1 /NFL /NDL /NJH /NJS
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed: $LASTEXITCODE" }
}

Invoke-RobocopyApp $appSrc $appDst
& robocopy $modSrc $modDst /E /R:2 /W:1 /NFL /NDL /NJH /NJS
if ($LASTEXITCODE -ge 8) { throw "robocopy mod failed: $LASTEXITCODE" }

$docsSrc = Join-Path $srcRoot "docs"
$docsDst = Join-Path $GitRoot "docs"
if (Test-Path -LiteralPath $docsSrc) {
    & robocopy $docsSrc $docsDst /E /R:2 /W:1 /NFL /NDL /NJH /NJS
    if ($LASTEXITCODE -ge 8) { throw "robocopy docs failed: $LASTEXITCODE" }
}

$toolsSrc = Join-Path $srcRoot "tools"
$toolsDst = Join-Path $GitRoot "tools"
if (Test-Path -LiteralPath $toolsSrc) {
    & robocopy $toolsSrc $toolsDst /E /R:2 /W:1 /NFL /NDL /NJH /NJS
    if ($LASTEXITCODE -ge 8) { throw "robocopy tools failed: $LASTEXITCODE" }
}

foreach ($f in @("README.md", "RELEASE_NOTES.md", ".gitignore")) {
    $p = Join-Path $srcRoot $f
    if (Test-Path -LiteralPath $p) {
        Copy-Item -LiteralPath $p -Destination (Join-Path $GitRoot $f) -Force
    }
}

$dead = Join-Path $modDst "src\collectors\VehicleDataCollectorSimple.lua"
if (Test-Path -LiteralPath $dead) {
    Remove-Item -LiteralPath $dead -Force
    Write-Host "Removed stale VehicleDataCollectorSimple.lua"
}

Write-Host "OK - open this folder in GitHub Desktop and commit."
