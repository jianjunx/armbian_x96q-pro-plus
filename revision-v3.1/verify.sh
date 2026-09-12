#!/bin/bash
set -euo pipefail
src=/armbian/cache/h728-v3.1-input
# shellcheck source=settings.sh
source "$src/settings.sh"
bash "$src/base-verify.sh"
# shellcheck source=base-common.sh
source "$H728_COMMON"
mount_image yes
uuid=$(blkid -s UUID -o value "${loop}p2")
bootuuid=$(blkid -s UUID -o value "${loop}p1")
test "$uuid" != 5e0d59f0-a18f-4d13-8d91-ea283a16f754
test "$uuid" != dd11ca3d-7015-4466-8fba-cb95a97b73ff
test "$bootuuid" != 7283-0001
awk -v id="$uuid" '$1=="APPEND" && index($0,"root=UUID=" id)==0 {exit 1}' "$root/boot/extlinux/extlinux.conf"
grep -qx verbosity=7 "$root/boot/armbianEnv.txt"
if grep -q 'loglevel=6' "$root/boot/extlinux/extlinux.conf"; then exit 1; fi
grep -q 'setenv verbosity 7' "$root/boot/boot.cmd"
dd if="$root/boot/boot.scr" bs=1 skip=72 status=none | cmp - "$root/boot/boot.cmd"
cmp "$root/usr/lib/linux-image-h728-manjaro/sun55i-h728-x96qpro+.dtb" "$root/boot/dtb/allwinner/sun55i-h728-x96qpro+.dtb"
cmp "$src/h728-diagnostics" "$root/usr/local/sbin/h728-diagnostics"
cmp "$src/h728-install-emmc" "$root/usr/local/sbin/h728-install-emmc"
# This entry point is the NEW refusal-only script, not the old destructive tool.
if chroot "$root" /usr/local/sbin/h728-install-emmc --install; then exit 1; fi
# shellcheck disable=SC2016
if grep -q '\$report' "$root/usr/local/lib/h728-diagnostics-base"; then exit 1; fi
chroot "$root" bash -n /usr/local/lib/h728-diagnostics-base
test -s "$root/etc/h728-image-release"
grep -qx VERSION=v3.1.1 "$root/etc/h728-image-release"
test "$(fdtget "$root/boot/dtb/allwinner/sun55i-h728-x96qpro+.dtb" /soc/mmc@4021000 max-frequency)" = 24000000
cp "$root/boot/dtb/allwinner/sun55i-h728-x96qpro+.dtb" "$root/tmp/wifi20.dtb"
fdtput -t i "$root/tmp/wifi20.dtb" /soc/mmc@4021000 max-frequency 20000000
cmp "$root/tmp/wifi20.dtb" "$root/boot/dtb/allwinner/sun55i-h728-x96qpro+-wifi20.dtb"
test "$(readlink "$root/etc/systemd/system/exim4.service")" = /dev/null
chroot "$root" systemd-analyze verify /etc/systemd/system/h728-diagnostics.service
chroot "$root" sh -c 'command -v timeout; command -v flock; command -v dtc'
test ! -e "$root/boot/h728-diagnostics.txt"
test ! -d "$root/boot/h728-logs"
for key in rsa ecdsa ed25519; do test ! -e "$root/etc/ssh/ssh_host_${key}_key"; done
for file in "$root/etc/apt/sources.list" "$root/etc/apt/sources.list.d/"*.list "$root/etc/apt/sources.list.d/"*.sources; do
    test -f "$file" || continue
    if sed '/^[[:space:]]*#/d' "$file" | grep -qi bookworm; then exit 1; fi
done
echo 'PASS v3.1: independent SD UUIDs, corrected packaged DTB, loglevel7, bounded diagnostics, eMMC installer blocked, Exim masked.'
echo 'This is offline verification only; v3.1 physical SD boot/peripherals/thermal testing remains required.'
