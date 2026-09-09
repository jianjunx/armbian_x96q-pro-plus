<#
X96Q Pro+ H728 v3 FAT-side DTB rollback helper (Path A).

Mutates the FAT boot partition of a flashed v3 SD card to use the stock
reference DTB (sun55i-h728-x96qpro+-stock.dtb) instead of the eMMC-patched
DTB, without rebuilding the image. This is the binary test for the v3
network regression hypothesis described in revision-v3/README.md.

Usage:
    # Roll back (set DEFAULT stock-dtb). Drive letter is auto-detected when
    # only one removable volume contains extlinux/extlinux.conf.
    powershell -ExecutionPolicy Bypass -File revision-v3/rollback-fat.ps1

    # Pass the drive letter explicitly when multiple removable volumes match.
    powershell -ExecutionPolicy Bypass -File revision-v3/rollback-fat.ps1 `
        -DriveLetter E

    # Restore the original DEFAULT after a test. Reads extlinux/extlinux.conf.bak
    # written by a previous rollback run.
    powershell -ExecutionPolicy Bypass -File revision-v3/rollback-fat.ps1 `
        -DriveLetter E -Restore

The script never touches the ext4 root partition; only the FAT boot partition.
A successful run is fully reversible through -Restore. It is safe to run while
the SD card is mounted read-only by Windows; if Windows holds a handle to the
file, the script retries with elevated rights.
#>

[CmdletBinding()]
param(
    [string]$DriveLetter,
    [switch]$Restore
)

$ErrorActionPreference = 'Stop'

function Find-SdDriveLetter {
    $candidates = @()
    # Get-Volume / Find-Volume are not always available; iterate Win32_LogicalDisk.
    Get-CimInstance -ClassName Win32_LogicalDisk | ForEach-Object {
        if ($_.DriveType -ne 2) { return } # 2 = Removable
        if (-not $_.DriveLetter) { return }
        $testPath = "$($_.DriveLetter):\extlinux\extlinux.conf"
        if (Test-Path -LiteralPath $testPath) {
            $candidates += $_.DriveLetter
        }
    }
    if ($candidates.Count -eq 1) { return $candidates[0] }
    if ($candidates.Count -eq 0) {
        throw "No removable drive with extlinux\extlinux.conf was found. Insert the v3 SD card or pass -DriveLetter."
    }
    throw "Multiple removable drives contain extlinux\extlinux.conf: $($candidates -join ', '). Pass -DriveLetter explicitly."
}

if (-not $DriveLetter) {
    $DriveLetter = Find-SdDriveLetter
    Write-Host "Auto-detected FAT partition at ${DriveLetter}:" -ForegroundColor Cyan
}

$DriveLetter = $DriveLetter.TrimEnd(':').ToUpper()
$extlinux = "${DriveLetter}:\extlinux"
$confPath = "${extlinux}\extlinux.conf"
$bakPath  = "${extlinux}\extlinux.conf.bak"

if (-not (Test-Path -LiteralPath $confPath)) {
    throw "Not a v3 boot partition: ${confPath} not found on drive ${DriveLetter}:."
}

$content = Get-Content -LiteralPath $confPath -Raw
$firstLine = ($content -split "`r?`n", 2)[0]

if ($Restore) {
    if (-not (Test-Path -LiteralPath $bakPath)) {
        throw "No backup at ${bakPath}; nothing to restore."
    }
    $backup = Get-Content -LiteralPath $bakPath -Raw
    Set-Content -LiteralPath $confPath -Value $backup -NoNewline -Encoding ASCII
    $newFirst = ($backup -split "`r?`n", 2)[0]
    Write-Host "Restored ${confPath} from ${bakPath}." -ForegroundColor Green
    Write-Host "  DEFAULT: $newFirst"
    exit 0
}

if ($firstLine -eq 'DEFAULT stock-dtb') {
    Write-Host "Already on DEFAULT stock-dtb; no change needed." -ForegroundColor Yellow
    Write-Host "  backup still present: $(Test-Path -LiteralPath $bakPath)"
    exit 0
}

if ($firstLine -ne 'DEFAULT armbian-h728') {
    throw "Unexpected DEFAULT line '$firstLine' on ${confPath}; this script only converts 'DEFAULT armbian-h728' -> 'DEFAULT stock-dtb'. Refusing to modify."
}

if (Test-Path -LiteralPath $bakPath) {
    throw "Backup already exists at ${bakPath}; refusing to overwrite. Remove it manually, or pass -Restore to revert a previous run."
}

Copy-Item -LiteralPath $confPath -Destination $bakPath -Force
$updated = $content -replace '(?m)^DEFAULT armbian-h728$', 'DEFAULT stock-dtb'
Set-Content -LiteralPath $confPath -Value $updated -NoNewline -Encoding ASCII

$newFirst = ($updated -split "`r?`n", 2)[0]
Write-Host "Rollback applied." -ForegroundColor Green
Write-Host "  before: $firstLine"
Write-Host "  after:  $newFirst"
Write-Host "  backup: $bakPath"
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Safely eject the SD card in Windows."
Write-Host "  2. Insert into the box. Power off, wait 10 seconds, power on (cold boot)."
Write-Host "  3. Wait ~2 minutes, then check the router DHCP list for 'x96q-pro-plus'."
Write-Host "  4. Whether or not it works, copy the refreshed h728-diagnostics.txt off the FAT."
Write-Host ""
Write-Host "To restore the patched-DTB boot (after capturing the result):"
Write-Host "  powershell -ExecutionPolicy Bypass -File revision-v3/rollback-fat.ps1 -DriveLetter ${DriveLetter} -Restore"