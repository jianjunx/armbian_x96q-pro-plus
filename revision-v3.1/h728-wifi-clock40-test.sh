#!/bin/bash
# Reversible 20 MHz -> 40 MHz SDIO Wi-Fi experiment.
set -euo pipefail
baseline_hash=be1028ce193f0948f0476c03851a6a6da82ce5b4cf40d83c1c472cc47b9b2567
node=/soc/mmc@4021000
dtb=/boot/dtb/allwinner/sun55i-h728-x96qpro+.dtb
clock12_recovery=/boot/h728-wifi-clock12-v1-recovery
recovery=/boot/h728-wifi-clock40-v1-recovery
tmp=
expected20=
cleanup() {
    [[ -z $tmp ]] || rm -f -- "$tmp"
    [[ -z $expected20 ]] || rm -f -- "$expected20"
}
trap cleanup EXIT
die() { echo "STOP: $*" >&2; exit 1; }
hash() { sha256sum "$1" | awk '{print $1}'; }
make_dtb() {
    local source=$1 output=$2 frequency=$3 original_frequency
    original_frequency=$(fdtget -t i "$source" "$node" max-frequency)
    cp -- "$source" "$output"
    fdtput -t i "$output" "$node" max-frequency "$frequency"
    [[ $(fdtget -t i "$output" "$node" max-frequency) == "$frequency" ]] || die 'DTB clock update failed.'
    fdtput -t i "$output" "$node" max-frequency "$original_frequency"
    cmp -s "$source" "$output" || die 'Unexpected changes beyond Wi-Fi clock.'
    fdtput -t i "$output" "$node" max-frequency "$frequency"
}
install_dtb() {
    local source=$1
    [[ -z $tmp ]] || rm -f -- "$tmp"
    tmp=$(mktemp /boot/dtb/allwinner/.h728-wifi-clock40.XXXXXX)
    cp -- "$source" "$tmp"
    cmp -s "$tmp" "$source" || die 'Staging verification failed.'
    sync
    mv -f -- "$tmp" "$dtb"
    tmp=
    sync
    cmp -s "$dtb" "$source" || die 'Installed DTB verification failed.'
}

mode=${1:-help}
for command in sha256sum awk cp cmp fdtget fdtput mktemp mv sync findmnt readlink lsblk; do
    command -v "$command" >/dev/null || die "Missing dependency: $command"
done
[[ $mode == arm || $mode == restore ]] || die 'Usage: bash h728-wifi-clock40-test.sh arm|restore'
[[ $EUID == 0 ]] || die 'Run as root.'
[[ $(uname -r) == 7.2.0-7-MANJARO-ARM ]] || die 'Unexpected kernel.'
[[ $(tr -d '\0' </proc/device-tree/model) == 'X96Q Pro+' ]] || die 'Unexpected board.'
for mountpoint in / /boot; do
    source=$(readlink -f "$(findmnt -nro SOURCE --target "$mountpoint")")
    parent=$(lsblk -ndo PKNAME "$source")
    [[ -n $parent && -f /sys/class/block/$parent/device/type ]] || die 'Cannot resolve SD device.'
    [[ $(cat "/sys/class/block/$parent/device/type") == SD ]] || die "$mountpoint is not on SD; eMMC must remain untouched."
    if [[ $mountpoint == / ]]; then root_parent=$parent; fi
    [[ $parent == "$root_parent" ]] || die 'Root and boot are on different devices.'
done
[[ $(findmnt -nro FSTYPE --target /boot) == vfat ]] || die '/boot is not FAT.'
[[ -f $dtb && ! -L $dtb ]] || die 'Expected regular board DTB missing.'
[[ -f $clock12_recovery/original.dtb ]] || die 'The original pinned DTB recovery is missing.'
[[ $(hash "$clock12_recovery/original.dtb") == "$baseline_hash" ]] || die 'Pinned baseline recovery checksum mismatch.'

expected20=$(mktemp /boot/dtb/allwinner/.h728-wifi-clock40.XXXXXX)
make_dtb "$clock12_recovery/original.dtb" "$expected20" 20000000

if [[ $mode == arm ]]; then
    [[ $(cat /sys/class/net/end0/carrier 2>/dev/null) == 1 ]] || die 'Connect Ethernet before arming; Wi-Fi may fail at 40 MHz.'
    cmp -s "$dtb" "$expected20" || die 'Active DTB is not the verified 20 MHz candidate.'
    [[ ! -e $recovery ]] || die '40 MHz recovery directory already exists; refusing to overwrite it.'
    mkdir "$recovery"
    cp -- "$dtb" "$recovery/clock20.dtb"
    cmp -s "$recovery/clock20.dtb" "$expected20" || die '20 MHz backup verification failed.'
    make_dtb "$clock12_recovery/original.dtb" "$recovery/clock40.dtb" 40000000
    install_dtb "$recovery/clock40.dtb"
    echo 'WIFI_CLOCK40_ARMED. No reboot performed. This remains an experiment.'
else
    [[ -f $recovery/clock20.dtb && -f $recovery/clock40.dtb ]] || die '40 MHz recovery files missing.'
    cmp -s "$recovery/clock20.dtb" "$expected20" || die '20 MHz recovery verification failed.'
    tmp=$(mktemp /boot/dtb/allwinner/.h728-wifi-clock40.XXXXXX)
    make_dtb "$clock12_recovery/original.dtb" "$tmp" 40000000
    if ! cmp -s "$dtb" "$tmp" && ! cmp -s "$dtb" "$expected20"; then
        die 'Active DTB has unrelated changes; refusing to overwrite it.'
    fi
    install_dtb "$recovery/clock20.dtb"
    echo 'WIFI_CLOCK20_RESTORED. Recovery files retained. No reboot performed.'
fi
echo "Computer recovery: copy $recovery/clock20.dtb to FAT dtb/allwinner/sun55i-h728-x96qpro+.dtb"
