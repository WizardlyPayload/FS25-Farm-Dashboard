#Requires -Version 5.1
# Farm Dashboard optional setup: ensure ImageMagick (magick) is available for DDS→PNG in mod image export.
# Always exits 0 so the main application install is never blocked.

$ErrorActionPreference = 'Stop'
$log = Join-Path $env:TEMP 'FarmDashImageMagickInstall.log'

function Write-Log([string] $m) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'o'), $m
    Add-Content -LiteralPath $log -Value $line -Encoding utf8 -ErrorAction SilentlyContinue
}

function Update-SessionPathFromRegistry {
    $machine = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [System.Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not [string]::IsNullOrWhiteSpace($machine) -or -not [string]::IsNullOrWhiteSpace($user)) {
        $env:Path = "$machine;$user;$env:Path"
    }
}

function Test-MagickOnPath {
    Update-SessionPathFromRegistry
    foreach ($name in @('magick.exe', 'magick')) {
        $c = Get-Command $name -ErrorAction SilentlyContinue
        if ($c -and $c.Source -and (Test-Path -LiteralPath $c.Source)) {
            Write-Log "Found existing: $($c.Source)"
            return $true
        }
    }
    $pf64 = [Environment]::GetEnvironmentVariable('ProgramFiles')
    $pf32 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    foreach ($root in @($pf64, $pf32)) {
        if ([string]::IsNullOrWhiteSpace($root)) { continue }
        $dirs = @(Get-ChildItem -Path $root -Directory -Filter 'ImageMagick*' -ErrorAction SilentlyContinue)
        foreach ($d in $dirs) {
            $exe = Join-Path $d.FullName 'magick.exe'
            if (Test-Path -LiteralPath $exe) {
                Write-Log "Found ImageMagick: $exe"
                return $true
            }
        }
    }
    return $false
}

try {
    Write-Log '--- Farm Dashboard ImageMagick helper start ---'
    if (Test-MagickOnPath) {
        Write-Log 'Already available; done.'
        exit 0
    }

    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($winget -and $winget.Source) {
        $args = @(
            'install', '--id', 'ImageMagick.ImageMagick', '-e',
            '--accept-package-agreements', '--accept-source-agreements', '--silent'
        )
        Write-Log 'Trying winget (user context, no UAC prompt) ...'
        try {
            $p = Start-Process -FilePath $winget.Source -ArgumentList $args -Wait -PassThru -NoNewWindow
            Write-Log "winget exit: $($p.ExitCode)"
        } catch {
            Write-Log "winget start error: $($_.Exception.Message)"
        }
        Update-SessionPathFromRegistry
        if (Test-MagickOnPath) {
            Write-Log 'winget succeeded.'
            exit 0
        }

        Write-Log 'Trying winget elevated (UAC may prompt) ...'
        try {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $winget.Source
            $psi.Arguments = ($args -join ' ')
            $psi.UseShellExecute = $true
            $psi.Verb = 'runas'
            $elev = [System.Diagnostics.Process]::Start($psi)
            $elev.WaitForExit()
            Write-Log "winget elevated exit: $($elev.ExitCode)"
        } catch {
            Write-Log "winget elevated: $($_.Exception.Message)"
        }
        Update-SessionPathFromRegistry
        if (Test-MagickOnPath) { exit 0 }
    } else {
        Write-Log 'winget not on PATH.'
    }

    $choco = Get-Command choco.exe -ErrorAction SilentlyContinue
    if ($choco) {
        Write-Log 'Trying Chocolatey (may prompt UAC) ...'
        try {
            $c = Start-Process -FilePath $choco.Source -ArgumentList @('install', 'imagemagick', '-y') -Wait -PassThru -Verb RunAs -ErrorAction SilentlyContinue
            if ($c) { Write-Log "choco exit: $($c.ExitCode)" }
        } catch {
            Write-Log "choco: $($_.Exception.Message)"
        }
        Update-SessionPathFromRegistry
        if (Test-MagickOnPath) { exit 0 }
    }

    Write-Log 'Automatic install did not complete. You can install ImageMagick from https://imagemagick.org or place texconv.exe under resources/texconv.'
}
catch {
    Write-Log "Error: $($_.Exception.Message)"
}

exit 0
