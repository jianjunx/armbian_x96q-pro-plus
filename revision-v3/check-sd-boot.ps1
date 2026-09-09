<#
.SYNOPSIS
    Health-check an Armbian H728 SD card on Windows (read-only).

.DESCRIPTION
    Scans every disk volume for the Armbian/H728 boot markers and reports
    whether the card's FAT boot partition is intact, which extlinux entry is
    the default, and which root UUID it points at.

    Nothing is modified.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\check-sd-boot.ps1
#>
[CmdletBinding()]
param(
    [string]$DriveLetter
)

$ErrorActionPreference = 'Continue'

$markers = @(
    'extlinux\extlinux.conf',
    'armbianEnv.txt',
    'dtb\allwinner\sun55i-h728-x96qpro+.dtb',
    'dtb\allwinner\sun55i-h728-x96qpro+-stock.dtb'
)
$kernels = @('Image', 'initrd.img-7.2.0-7-MANJARO-ARM')

function Test-BootVolume {
    param([string]$Root)

    if (-not (Test-Path (Join-Path $Root 'extlinux\extlinux.conf'))) { return $false }
    if (-not (Test-Path (Join-Path $Root 'armbianEnv.txt'))) { return $false }
    return $true
}

function Get-CandidateVolumes {
    if ($DriveLetter) {
        return @($DriveLetter.TrimEnd('\') + '\')
    }
    $vols = @()
    Get-CimInstance Win32_LogicalDisk -ErrorAction SilentlyContinue |
        Where-Object { $_.DriveType -eq 2 -or $_.DriveType -eq 3 } |
        ForEach-Object { $vols += ($_.DeviceID + '\') }
    return $vols
}

Write-Host '============================================================'
Write-Host ' H728 SD card boot health check (read-only)'
Write-Host '============================================================'
Write-Host ''

$candidates = Get-CandidateVolumes
$found = $false

foreach ($root in $candidates) {
    if (-not (Test-BootVolume $root)) { continue }
    $found = $true

    Write-Host "### Armbian boot partition found: $root" -ForegroundColor Green
    Write-Host ''

    Write-Host '-- boot markers --'
    foreach ($m in $markers) {
        $p = Join-Path $root $m
        if (Test-Path $p) {
            $i = Get-Item $p
            Write-Host ("  OK   {0,-52} {1,10} bytes  {2}" -f $m, $i.Length, $i.LastWriteTime)
        }
        else {
            Write-Host ("  MISS {0,-52}" -f $m) -ForegroundColor Yellow
        }
    }

    Write-Host ''
    Write-Host '-- kernel / initrd --'
    foreach ($k in $kernels) {
        $p = Join-Path $root $k
        if (Test-Path $p) {
            $i = Get-Item $p
            Write-Host ("  OK   {0,-52} {1,10} bytes  {2}" -f $k, $i.Length, $i.LastWriteTime)
        }
        else {
            Write-Host ("  MISS {0,-52}" -f $k) -ForegroundColor Yellow
        }
    }

    Write-Host ''
    Write-Host '-- extlinux.conf --'
    $conf = Join-Path $root 'extlinux\extlinux.conf'
    if (Test-Path $conf) {
        Get-Content $conf | ForEach-Object {
            $line = $_
            if ($line -match '^\s*(DEFAULT|LABEL|MENU LABEL|FDT|LINUX|INITRD)\s*') {
                Write-Host "  $line"
            }
            elseif ($line -match 'APPEND') {
                $u = ([regex]'root=UUID=[0-9a-fA-F-]+').Match($line).Value
                Write-Host "  APPEND ... $u"
            }
        }
    }

    Write-Host ''
    Write-Host '-- armbianEnv.txt --'
    $env = Join-Path $root 'armbianEnv.txt'
    if (Test-Path $env) {
        Get-Content $env | Where-Object { $_ -match 'rootdev|fdtfile|verbosity|bootlogo' } |
            ForEach-Object { Write-Host "  $_" }
    }

    Write-Host ''
    Write-Host '-- boot script --'
    foreach ($s in @('boot.scr', 'boot.cmd')) {
        $p = Join-Path $root $s
        if (Test-Path $p) { Write-Host ("  OK   {0} ({1} bytes)" -f $s, (Get-Item $p).Length) }
    }

    Write-Host ''
}

if (-not $found) {
    Write-Host 'No Armbian boot partition detected on any volume.' -ForegroundColor Red
    Write-Host ''
    Write-Host 'If the card does not even appear as a drive, Windows may see it as'
    Write-Host 'unformatted. Check Disk Management (diskmgmt.msc) - a healthy card'
    Write-Host 'should show a ~512 MB FAT partition plus a large ext4 one.'
    Write-Host ''
    Write-Host 'Volumes scanned:' -ForegroundColor DarkGray
    foreach ($v in $candidates) { Write-Host "  $v" -ForegroundColor DarkGray }
}

Write-Host ''
Write-Host 'Autodetect tip: re-run with -DriveLetter E (no colon needed) if the'
Write-Host 'card was not picked up automatically.'
Write-Host ''
