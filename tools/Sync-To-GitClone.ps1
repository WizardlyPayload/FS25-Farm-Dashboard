# Sync MAIN CODEBASE (this tree) -> local GitHub clone at FS25-Farm-Dashboard.
# Skips: node_modules, release (and anything under them).
# Usage (PowerShell):  .\tools\Sync-To-GitClone.ps1
# Or:  .\tools\Sync-To-GitClone.ps1 -GitRoot "D:\path\to\FS25-Farm-Dashboard"

param(
    [string]$GitRoot = (Join-Path $env:USERPROFILE "Documents\FS25-Farm-Dashboard")
)

$ErrorActionPreference = "Stop"
$srcRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if (-not (Test-Path -LiteralPath $srcRoot)) { throw "Bad source root: $srcRoot" }

Write-Host "Source: $srcRoot"
Write-Host "Dest:   $GitRoot"

$appSrc = Join-Path $srcRoot "FS25_FarmDashboard_App\FS25_FarmDashboard_App"
$appDst = Join-Path $GitRoot "FS25_Dashboard APP"
$modSrc = Join-Path $srcRoot "FS25_FarmDashboard_Mod\FS25_FarmDashboard_Mod"
$modDst = Join-Path $GitRoot "FS25_Dashboard MOD"

if (-not (Test-Path -LiteralPath $appSrc)) { throw "Missing: $appSrc" }
if (-not (Test-Path -LiteralPath $modSrc)) { throw "Missing: $modSrc" }

& robocopy $appSrc $appDst /E /XD node_modules release /R:2 /W:1 /NFL /NDL /NJH /NJS
if ($LASTEXITCODE -ge 8) { throw "robocopy app failed: $LASTEXITCODE" }

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

Write-Host "Done. Open $GitRoot in GitHub Desktop and commit."
