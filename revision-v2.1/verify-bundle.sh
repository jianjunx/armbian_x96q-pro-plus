#!/bin/bash
# Exercise the real installer on an isolated copy of the shipped v2 image.
set -euo pipefail
work=$(mktemp -d /tmp/h728-repair-test.XXXXXX)
root=$work/root
loop=
cleanup() {
    for part in boot ''; do
        if mountpoint -q "$root/$part"; then umount "$root/$part"; fi
    done
    [[ -z $loop ]] || losetup -d "$loop"
}
trap cleanup EXIT
mkdir "$root"
cp --sparse=always /armbian/output/images/Armbian_X96Q-Pro-Plus_H728_Bookworm_6.17-2_v2.img "$work/test.img"
loop=$(losetup --find --show --partscan "$work/test.img")
for p in 1 2; do
    part=${loop}p$p
    number=$(<"/sys/class/block/$(basename "$part")/dev")
    test -b "$part" || mknod "$part" b "${number%:*}" "${number#*:}"
done
mount "${loop}p2" "$root"
mount "${loop}p1" "$root/boot"
tar -xzf /armbian/output/repairs/h728-v2.1-repair.tar.gz -C "$work"
cp "$root/etc/default/cpufrequtils" "$work/original-cpufrequtils"
bash "$work/h728-v2.1-repair/install.sh" --root "$root"
cmp "$root/boot/Image" /armbian/cache/h728-audit/reference/boot/Image
cmp "$root/boot/dtb/allwinner/sun55i-h728-x96qpro+.dtb" '/armbian/cache/h728-audit/reference/boot/dtbs/allwinner/sun55i-h728-x96qpro+.dtb'
grep -qx GOVERNOR=schedutil "$root/etc/default/cpufrequtils"
grep -qx MIN_SPEED=408000 "$root/etc/default/cpufrequtils"
test -L "$root/etc/systemd/system/basic.target.wants/armbian-hardware-optimize.service"
test -x "$root/usr/local/sbin/h728-diagnostics"
backup=$(find "$root/var/backups" -maxdepth 1 -type d -name 'h728-v2.1.*' -print -quit)
cmp "$backup/etc/default/cpufrequtils" "$work/original-cpufrequtils"
for path in "$work/h728-v2.1-repair/firmware/"*; do
    cmp "$path" "$root/usr/lib/firmware/aic8800_sdio/$(basename "$path")"
done
# Installing twice must not duplicate the active governor setting.
bash "$work/h728-v2.1-repair/install.sh" --root "$root"
test "$(grep -c '^GOVERNOR=' "$root/etc/default/cpufrequtils")" -eq 1
echo 'PASS: original v2 image unchanged; repair installs on its isolated copy, preserves boot payload, backs up configuration and is repeatable.'
echo 'Hardware Wi-Fi association and DVFS stability: not yet tested.'
echo "Test copy retained at $work/test.img"
