#!/bin/bash
# One controlled experiment: SD boot payload, existing eMMC root filesystem.
set -euo pipefail
sd_uuid=5e0d59f0-a18f-4d13-8d91-ea283a16f754
emmc_uuid=dd11ca3d-7015-4466-8fba-cb95a97b73ff
label=h728-sd-emmc-root-test
fail() { echo "STOP: $*" >&2; exit 1; }
render_extlinux() {
    awk -v root="$emmc_uuid" -v label="$label" '
        /^DEFAULT / {print "DEFAULT " label; next}
        {print}
        END {
            print "\nLABEL " label
            print "    MENU LABEL Diagnostic - SD kernel with eMMC root"
            print "    LINUX /Image"
            print "    INITRD /initrd.img-7.2.0-7-MANJARO-ARM"
            print "    FDT /dtb/allwinner/sun55i-h728-x96qpro+.dtb"
            print "    APPEND root=UUID=" root " rootwait rw rootfstype=ext4 console=ttyS0,115200 earlycon=uart8250,mmio32,0x02500000 loglevel=7 panic=10"
        }
    ' "$1"
}
render_env() {
    awk -v root="$emmc_uuid" '
        /^rootdev=/ {print "rootdev=UUID=" root; next}
        /^fdtfile=/ {print "fdtfile=allwinner/sun55i-h728-x96qpro+.dtb"; next}
        /^verbosity=/ {print "verbosity=7"; next}
        /^extraargs=/ {gsub(/ loglevel=[0-9]+/, ""); print $0 " loglevel=7"; next}
        {print}
    ' "$1"
}
main() {
    [[ $# == 1 && $1 =~ ^(arm|restore)$ ]] || fail 'Usage: bash h728-sd-emmc-root-test.sh arm|restore'
    local mode=$1 rootpart bootpart disk backup ext env work path target
    [[ $EUID == 0 ]] || fail 'Run as root.'
    [[ $(tr -d '\0' </proc/device-tree/model) == 'X96Q Pro+' ]] || fail 'Wrong board.'
    [[ $(uname -r) == 7.2.0-7-MANJARO-ARM ]] || fail 'Wrong kernel.'
    rootpart=$(readlink -f "$(findmnt -nro SOURCE /)")
    bootpart=$(readlink -f "$(findmnt -nr -M /boot -o SOURCE)")
    disk=$(lsblk -ndo PKNAME "$rootpart")
    [[ $disk =~ ^mmcblk[0-9]+$ ]] || fail 'Unexpected root device.'
    [[ $(cat "/sys/class/block/$disk/device/type") == SD ]] || fail 'Must run from SD, not the eMMC system.'
    [[ $(blkid -s UUID -o value "$rootpart") == "$sd_uuid" ]] || fail 'Unexpected SD root UUID.'
    [[ $(lsblk -ndo PKNAME "$bootpart") == "$disk" && $(findmnt -nr -M /boot -o FSTYPE) == vfat ]] || fail '/boot is not the SD FAT partition.'
    backup=/boot/h728-sd-emmc-root-test-v1-recovery
    ext=/boot/extlinux/extlinux.conf
    env=/boot/armbianEnv.txt
    if [[ $mode == restore ]]; then
        (cd "$backup" && sha256sum -c SHA256SUMS)
        cp "$backup/armbianEnv.txt" "$env"
        cp "$backup/extlinux.conf" "$ext"
        sync -f /boot
        echo 'SD_SETTINGS_RESTORED. No reboot performed.'
        return
    fi
    [[ ! -e $backup && ! -L $backup ]] || fail 'Recovery directory exists; refusing to overwrite.'
    [[ $(grep -c '^DEFAULT ' "$ext") == 1 ]] || fail 'Unexpected extlinux defaults.'
    ! grep -q "^LABEL $label$" "$ext" || fail 'Test entry already exists.'
    grep -qx 'DEFAULT armbian-h728' "$ext" || fail 'Start from the proven eMMC-enabled SD configuration.'
    for path in rootdev fdtfile verbosity extraargs; do
        [[ $(grep -c "^$path=" "$env") == 1 ]] || fail "Unexpected armbianEnv field: $path"
    done
    grep -qx "rootdev=UUID=$sd_uuid" "$env" || fail 'Unexpected boot root setting.'
    grep -q 'loglevel=7' /proc/cmdline || fail 'Current successful baseline must use loglevel 7.'
    for path in /boot/Image /boot/initrd.img-7.2.0-7-MANJARO-ARM /boot/boot.scr; do
        [[ -f $path && -s $path ]] || fail "Missing boot file: $path"
    done
    printf '%s  %s\n' be1028ce193f0948f0476c03851a6a6da82ce5b4cf40d83c1c472cc47b9b2567 \
        '/boot/dtb/allwinner/sun55i-h728-x96qpro+.dtb' | sha256sum -c -
    local -a targets=()
    for path in /sys/block/mmcblk[0-9]*; do
        [[ ${path##*/} =~ ^mmcblk[0-9]+$ && -f $path/device/type ]] || continue
        [[ $(cat "$path/device/type") != MMC ]] || targets+=("/dev/${path##*/}")
    done
    [[ ${#targets[@]} == 1 ]] || fail 'Expected one eMMC.'
    target=${targets[0]}
    [[ $(blkid -s UUID -o value "${target}p2") == "$emmc_uuid" && $(blkid -s TYPE -o value "${target}p2") == ext4 ]] || fail 'Unexpected eMMC root.'
    if lsblk -nrpo MOUNTPOINTS "$target" | grep -q '[^[:space:]]'; then fail 'Unmount eMMC partitions before the test.'; fi
    work=$(mktemp -d /tmp/h728-root-test.XXXXXX)
    render_extlinux "$ext" >"$work/extlinux.conf"
    render_env "$env" >"$work/armbianEnv.txt"
    mkdir "$backup"
    cp "$env" "$backup/armbianEnv.txt"
    cp "$ext" "$backup/extlinux.conf"
    (cd "$backup" && sha256sum armbianEnv.txt extlinux.conf >SHA256SUMS)
    sync -f "$backup"
    # Stage complete files on the same FAT filesystem before renaming them.
    # Updating the two files is NOT a cross-file atomic transaction.
    [[ ! -e $env.h728-root-test-new && ! -e $ext.h728-root-test-new ]] || fail 'Staging files already exist.'
    cp "$work/armbianEnv.txt" "$env.h728-root-test-new"
    cp "$work/extlinux.conf" "$ext.h728-root-test-new"
    sync -f /boot
    mv "$env.h728-root-test-new" "$env"
    mv "$ext.h728-root-test-new" "$ext"
    cmp "$env" "$work/armbianEnv.txt"
    cmp "$ext" "$work/extlinux.conf"
    sync -f /boot
    echo 'SD_EMMC_ROOT_TEST_ARMED. No reboot performed.'
    echo "Keep SD inserted. Next Linux root UUID: $emmc_uuid"
    echo "Computer recovery: $backup/armbianEnv.txt -> FAT root; extlinux.conf -> FAT extlinux directory."
}
# Allow only the pure render functions to be sourced for offline fixture tests.
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
