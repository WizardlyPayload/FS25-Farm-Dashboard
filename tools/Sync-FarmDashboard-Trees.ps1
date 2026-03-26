<#
.SYNOPSIS
  Keeps your two local trees in sync: MAIN CODEBASE (backup / daily work) and
  FS25-Farm-Dashboard (git clone for GitHub).

.DESCRIPTION
  Folder mapping:
    MAIN: FS25_FarmDashboard_App\FS25_FarmDashboard_App  <->  Git: FS25_Dashboard APP
    MAIN: FS25_FarmDashboard_Mod\FS25_FarmDashboard_Mod  <->  Git: FS25_Dashboard MOD
  Root files README.md, RELEASE_NOTES.md, .gitignore, and docs\ are mirrored both ways.

  Excludes: node_modules, release, dist, out, .git, build artifacts (see $ExcludeDirNames).

.PARAMETER Direction
  ToGit   — copy from MAIN into the git clone (edit in MAIN, then sync before commit).
  FromGit — copy from the git clone into MAIN (after pull, refresh your backup).

.PARAMETER DryRun
  List what would copy (robocopy /L) without changing files.

.EXAMPLE
  .\tools\Sync-FarmDashboard-Trees.ps1 -Direction ToGit
.EXAMPLE
  .\tools\Sync-FarmDashboard-Trees.ps1 -Direction FromGit
.EXAMPLE
  $env:FARM_DASHBOARD_MAIN_ROOT = 'D:\work\MAIN CODEBASE'
  $env:FARM_DASHBOARD_GIT_ROOT = 'D:\repos\FS25-Farm-Dashboard'
  .\tools\Sync-FarmDashboard-Trees.ps1 -Direction ToGit
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('ToGit', 'FromGit')]
    [string] $Direction = 'ToGit',

    [string] $MainRoot = '',

    [string] $GitRoot = '',

    [switch] $DryRun
)

$ErrorActionPreference = 'Stop'

# Defaults for this machine (override with -MainRoot / -GitRoot or env vars).
if (-not $MainRoot) { $MainRoot = $env:FARM_DASHBOARD_MAIN_ROOT }
if (-not $GitRoot) { $GitRoot = $env:FARM_DASHBOARD_GIT_ROOT }
if (-not $MainRoot) {
    $MainRoot = "C:\Users\Graham\Documents\JoshWalki's Farmdash server edit\MAIN CODEBASE"
}
if (-not $GitRoot) {
    $GitRoot = 'C:\Users\Graham\Documents\FS25-Farm-Dashboard'
}

function Resolve-ExistingDir {
    param([string] $Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Directory not found: $Path"
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

$MainRoot = Resolve-ExistingDir $MainRoot
$GitRoot = Resolve-ExistingDir $GitRoot

$MainApp = Join-Path $MainRoot 'FS25_FarmDashboard_App\FS25_FarmDashboard_App'
$MainMod = Join-Path $MainRoot 'FS25_FarmDashboard_Mod\FS25_FarmDashboard_Mod'
$GitApp = Join-Path $GitRoot 'FS25_Dashboard APP'
$GitMod = Join-Path $GitRoot 'FS25_Dashboard MOD'

foreach ($p in @($MainApp, $MainMod)) {
    if (-not (Test-Path -LiteralPath $p -PathType Container)) {
        throw "Expected folder missing: $p"
    }
}
foreach ($p in @($GitApp, $GitMod)) {
    if (-not (Test-Path -LiteralPath $p -PathType Container)) {
        throw "Expected folder missing: $p"
    }
}

$ExcludeDirNames = @(
    'node_modules', 'release', 'dist', 'out', '.git', '.vs', 'win-unpacked',
    '__pycache__'
)

function Build-RobocopyArgs {
    param(
        [string] $Source,
        [string] $Dest
    )
    # One /XD with multiple directory names (name-only excludes, any depth).
    $xd = @('/XD') + $ExcludeDirNames
    $base = @(
        $Source, $Dest, '/E', '/FFT', '/R:2', '/W:2', '/MT:8',
        '/XF', '.env', '.env.*'
    )
    if ($DryRun) {
        $base += '/L'
    }
    return ($base + $xd)
}

function Invoke-RobocopyPair {
    param(
        [string] $From,
        [string] $To,
        [string] $Label
    )
    Write-Host "=== $Label ===" -ForegroundColor Cyan
    Write-Host "  $From"
    Write-Host "  -> $To"
    $args = Build-RobocopyArgs -Source $From -Dest $To
    & robocopy @args
    $code = $LASTEXITCODE
    if ($code -ge 8) {
        throw "robocopy failed for $Label (exit $code)"
    }
}

function Copy-RootFiles {
    param(
        [string] $FromRoot,
        [string] $ToRoot
    )
    $files = @('README.md', 'RELEASE_NOTES.md', '.gitignore')
    foreach ($name in $files) {
        $src = Join-Path $FromRoot $name
        if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { continue }
        $dst = Join-Path $ToRoot $name
        if ($DryRun) {
            Write-Host "[dry-run] Copy-Item $src -> $dst"
        } else {
            Copy-Item -LiteralPath $src -Destination $dst -Force
        }
    }
    $docsFrom = Join-Path $FromRoot 'docs'
    $docsTo = Join-Path $ToRoot 'docs'
    if (Test-Path -LiteralPath $docsFrom -PathType Container) {
        if ($DryRun) {
            Write-Host "[dry-run] Mirror docs: $docsFrom -> $docsTo"
        } else {
            if (-not (Test-Path -LiteralPath $docsTo -PathType Container)) {
                New-Item -ItemType Directory -Path $docsTo -Force | Out-Null
            }
            robocopy $docsFrom $docsTo /E /FFT /R:2 /W:2 /MT:8 $(if ($DryRun) { '/L' })
            if ($LASTEXITCODE -ge 8) { throw "robocopy docs failed (exit $LASTEXITCODE)" }
        }
    }
}

Write-Host "MAIN:  $MainRoot" -ForegroundColor Yellow
Write-Host "GIT:   $GitRoot" -ForegroundColor Yellow
Write-Host "Direction: $Direction" -ForegroundColor Yellow
if ($DryRun) { Write-Host "(dry run — no files changed)" -ForegroundColor Magenta }

switch ($Direction) {
    'ToGit' {
        Invoke-RobocopyPair -From $MainApp -To $GitApp -Label 'App -> FS25_Dashboard APP'
        Invoke-RobocopyPair -From $MainMod -To $GitMod -Label 'Mod -> FS25_Dashboard MOD'
        Copy-RootFiles -FromRoot $MainRoot -ToRoot $GitRoot
    }
    'FromGit' {
        Invoke-RobocopyPair -From $GitApp -To $MainApp -Label 'FS25_Dashboard APP -> App'
        Invoke-RobocopyPair -From $GitMod -To $MainMod -Label 'FS25_Dashboard MOD -> Mod'
        Copy-RootFiles -FromRoot $GitRoot -ToRoot $MainRoot
    }
}

Write-Host "Done." -ForegroundColor Green
