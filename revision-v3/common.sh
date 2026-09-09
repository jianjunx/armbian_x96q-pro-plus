#!/bin/bash
# Shared variables are consumed by scripts sourcing this file.
# shellcheck disable=SC2034
set -euo pipefail
src=/armbian/cache/h728-v3-input
cache=/armbian/cache/h728-v3
image=$cache/v3-working.img
version=7.2.0-7-MANJARO-ARM
ref=/armbian/cache/h728-audit/reference-7.2
package=/armbian/output/debs/linux-image-h728-manjaro_7.2.0-7+h728.3_arm64.deb
mkdir -p "$cache"
mount_image() {
    local readonly=${1:-no}
    local -a loopopts=()
    [[ $readonly != yes ]] || loopopts+=(--read-only)
    root=$(mktemp -d /tmp/h728-v3-root.XXXXXX)
    loop=$(losetup --find --show --partscan "${loopopts[@]}" "$image")
    trap cleanup EXIT
    for p in 1 2; do
        local part=${loop}p$p
        local number
        number=$(<"/sys/class/block/$(basename "$part")/dev")
        local expected
        expected=$(printf '%x:%x' "${number%:*}" "${number#*:}")
        if [[ ! -b $part || $(stat -c '%t:%T' "$part") != "$expected" ]]; then
            rm -f "$part"
            mknod "$part" b "${number%:*}" "${number#*:}"
        fi
    done
    if [[ $readonly == yes ]]; then
        fsck.vfat -n "${loop}p1"
        e2fsck -fn "${loop}p2"
        mount -o ro,noload "${loop}p2" "$root"
        mount -o ro "${loop}p1" "$root/boot"
        mount -t tmpfs -o size=256m tmpfs "$root/tmp"
    else
        mount "${loop}p2" "$root"
        mount "${loop}p1" "$root/boot"
    fi
    mount --bind /dev "$root/dev"
    mount -t proc proc "$root/proc"
    mount -t sysfs sysfs "$root/sys"
    mount -t tmpfs -o size=64m tmpfs "$root/run"
}
cleanup() {
    for sub in run sys proc dev/pts dev tmp boot ''; do
        if mountpoint -q "$root/$sub"; then umount "$root/$sub"; fi
    done
    losetup -d "$loop"
    rmdir "$root"
}
apt_in() {
    chroot "$root" env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l \
        apt-get -o Acquire::Retries=3 -o Acquire::http::Timeout=45 \
        -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold "$@"
}
