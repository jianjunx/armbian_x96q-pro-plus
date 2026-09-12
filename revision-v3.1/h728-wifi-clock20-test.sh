#!/bin/bash
# Reversible 12 MHz -> 20 MHz SDIO Wi-Fi experiment.
set -euo pipefail
baseline_hash=be1028ce193f0948f0476c03851a6a6da82ce5b4cf40d83c1c472cc47b9b2567
node=/soc/mmc@4021000
dtb=/boot/dtb/allwinner/sun55i-h728-x96qpro+.dtb
clock12_recovery=/boot/h728-wifi-clock12-v1-recovery
recovery=/boot/h728-wifi-clock20-v1-recovery
tmp=
expected12=
cleanup() {
    [[ -z $tmp ]] || rm -f -- "$tmp"
    [[ -z $expected12 ]] || rm -f -- "$expected12"
}
trap cleanup EXIT
die() { echo "STOP: $*" >&2; exit 1; }
hash() { sha256sum "$1" | awk '{print $1}'; }
make_dtb() {
    local source=$1 output=$2 frequency=$3
    cp -- "$source" "$output"
    fdtput -t i "$output" "$node" max-frequency "$frequency"
    [[ $(fdtget -t i "$output" "$node" max-frequency) == "$frequency" ]] || die 'DTB clock update failed.'
}
install_dtb() {
    local source=$1
    tmp=$(mktemp /boot/dtb/allwinner/.h728-wifi-clock20.XXXXXX)
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
[[ $mode == arm || $mode == restore ]] || die 'Usage: bash h728-wifi-clock20-test.sh arm|restore'
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
[[ -f $clock12_recovery/original.dtb ]] || die 'The verified 12 MHz experiment recovery is missing.'
[[ $(hash "$clock12_recovery/original.dtb") == "$baseline_hash" ]] || die 'Pinned baseline recovery checksum mismatch.'

expected12=$(mktemp /boot/dtb/allwinner/.h728-wifi-clock20.XXXXXX)
make_dtb "$clock12_recovery/original.dtb" "$expected12" 12000000

if [[ $mode == arm ]]; then
    cmp -s "$dtb" "$expected12" || die 'Active DTB is not the verified 12 MHz candidate.'
    [[ ! -e $recovery ]] || die '20 MHz recovery directory already exists; refusing to overwrite it.'
    mkdir "$recovery"
    cp -- "$dtb" "$recovery/clock12.dtb"
    cmp -s "$recovery/clock12.dtb" "$expected12" || die '12 MHz backup verification failed.'
    make_dtb "$clock12_recovery/original.dtb" "$recovery/clock20.dtb" 20000000
    install_dtb "$recovery/clock20.dtb"
    echo 'WIFI_CLOCK20_ARMED. No reboot performed. This remains an experiment.'
else
    [[ -f $recovery/clock12.dtb && -f $recovery/clock20.dtb ]] || die '20 MHz recovery files missing.'
    cmp -s "$recovery/clock12.dtb" "$expected12" || die '12 MHz recovery verification failed.'
    if ! cmp -s "$dtb" "$recovery/clock20.dtb" && ! cmp -s "$dtb" "$expected12"; then
        die 'Active DTB has unrelated changes; refusing to overwrite it.'
    fi
    install_dtb "$recovery/clock12.dtb"
    echo 'WIFI_CLOCK12_RESTORED. Recovery files retained. No reboot performed.'
fi
echo "Computer recovery: copy $recovery/clock12.dtb to FAT dtb/allwinner/sun55i-h728-x96qpro+.dtb"
