#!/bin/bash
# Reversible, single-variable Wi-Fi experiment; NOT a verified Wi-Fi fix.
set -euo pipefail
baseline=5e4c838516b43e7667a583859b671cf5eb00316674eb950d0eb5bb67b2502bc7
node=/soc/mmc@4021000
dtb=/boot/dtb/allwinner/sun55i-h728-x96qpro+.dtb
recovery=/boot/h728-wifi-clock12-v2-recovery
tmp=
cleanup() { [[ -z $tmp ]] || rm -f -- "$tmp"; }
trap cleanup EXIT
die() { echo "STOP: $*" >&2; exit 1; }
hash() { sha256sum "$1" | awk '{print $1}'; }
make_candidate() {
    [[ $(hash "$1") == "$baseline" ]] || die 'DTB is not the pinned v3.1 baseline.'
    cp -- "$1" "$2"
    fdtput -t i "$2" "$node" max-frequency 12000000
    [[ $(fdtget -t i "$2" "$node" max-frequency) == 12000000 ]] || die 'Clock patch failed.'
    # Restore the property temporarily: byte equality proves no other delta.
    fdtput -t i "$2" "$node" max-frequency 24000000
    cmp -s "$1" "$2" || die 'Unexpected DTB changes beyond the clock property.'
    fdtput -t i "$2" "$node" max-frequency 12000000
}

mode=${1:-help}
for command in sha256sum awk cp cmp fdtget fdtput mktemp mv sync; do
    command -v "$command" >/dev/null || die "Missing dependency: $command"
done
# Offline validation only; refuses to overwrite an existing output.
if [[ $mode == prepare ]]; then
    [[ $# == 3 && -f $2 && ! -e $3 && ! -L $3 ]] || die 'Usage: prepare INPUT NEW_OUTPUT'
    make_candidate "$2" "$3"
    sha256sum "$3"
    exit 0
fi
[[ $mode == arm || $mode == restore ]] || die 'Usage: bash h728-wifi-clock12-v2-test.sh arm|restore'
[[ $EUID == 0 ]] || die 'Run as root.'
[[ $(uname -r) == 7.2.0-7-MANJARO-ARM ]] || die 'Unexpected kernel.'
[[ $(tr -d '\0' </proc/device-tree/model) == 'X96Q Pro+' ]] || die 'Unexpected board.'
for mountpoint in / /boot; do
    source=$(findmnt -nro SOURCE --target "$mountpoint")
    source=$(readlink -f "$source")
    parent=$(lsblk -ndo PKNAME "$source")
    [[ -n $parent && -f /sys/class/block/$parent/device/type ]] || die 'Cannot resolve SD device.'
    [[ $(cat "/sys/class/block/$parent/device/type") == SD ]] || die "$mountpoint is not on SD; eMMC must remain untouched."
    if [[ $mountpoint == / ]]; then root_parent=$parent; fi
    [[ $parent == "$root_parent" ]] || die 'Root and boot are on different devices.'
done
[[ $(findmnt -nro FSTYPE --target /boot) == vfat ]] || die '/boot is not FAT.'
[[ -f $dtb && ! -L $dtb ]] || die 'Expected regular board DTB missing.'
grep -qx 'fdtfile=allwinner/sun55i-h728-x96qpro+.dtb' /boot/armbianEnv.txt || die 'Unexpected boot DTB selection.'
grep -Eq '^[[:space:]]*FDT /dtb/allwinner/sun55i-h728-x96qpro\+\.dtb[[:space:]]*$' /boot/extlinux/extlinux.conf || die 'Unexpected extlinux DTB selection.'

if [[ $mode == arm ]]; then
    [[ $(hash "$dtb") == "$baseline" ]] || die 'Active DTB differs from baseline; restore prior experiments first.'
    [[ ! -e $recovery ]] || die 'Recovery directory already exists; do not overwrite it.'
    mkdir "$recovery"
    cp -- "$dtb" "$recovery/original.dtb"
    [[ $(hash "$recovery/original.dtb") == "$baseline" ]] || die 'Backup verification failed.'
    make_candidate "$recovery/original.dtb" "$recovery/clock12.dtb"
    sync
    tmp=$(mktemp /boot/dtb/allwinner/.h728-wifi-clock12.XXXXXX)
    cp -- "$recovery/clock12.dtb" "$tmp"
    cmp -s "$tmp" "$recovery/clock12.dtb" || die 'Staging verification failed.'
    sync
    mv -f -- "$tmp" "$dtb"
    tmp=
    sync
    cmp -s "$dtb" "$recovery/clock12.dtb" || die 'Installed DTB verification failed.'
    echo 'WIFI_CLOCK12_ARMED. No reboot performed. This is an experiment, not a confirmed fix.'
else
    [[ -f $recovery/original.dtb ]] || die 'Recovery DTB missing.'
    [[ $(hash "$recovery/original.dtb") == "$baseline" ]] || die 'Recovery checksum mismatch.'
    tmp=$(mktemp /boot/dtb/allwinner/.h728-wifi-clock12.XXXXXX)
    make_candidate "$recovery/original.dtb" "$tmp"
    if [[ $(hash "$dtb") != "$baseline" ]]; then
        cmp -s "$tmp" "$dtb" || die 'DTB has unrelated changes; refusing to overwrite.'
    fi
    cp -- "$recovery/original.dtb" "$tmp"
    sync
    mv -f -- "$tmp" "$dtb"
    tmp=
    sync
    [[ $(hash "$dtb") == "$baseline" ]] || die 'Restore verification failed.'
    echo 'WIFI_BASELINE_RESTORED. Recovery files retained. No reboot performed.'
fi
echo "Computer recovery: copy $recovery/original.dtb to FAT dtb/allwinner/sun55i-h728-x96qpro+.dtb"
