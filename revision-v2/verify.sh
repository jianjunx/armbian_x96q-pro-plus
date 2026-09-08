#!/bin/bash
# Offline acceptance checks. These do not replace a physical board boot test.
set -euo pipefail
image=/armbian/output/images/Armbian_X96Q-Pro-Plus_H728_Bookworm_6.17-2_v2.img
version=6.17.0-rc1-2-MANJARO-ARM+
ref=/armbian/cache/h728-audit/reference
root=$(mktemp -d /tmp/h728-verify.XXXXXX)
loop=$(losetup --find --show --partscan --read-only "$image")
cleanup() {
    for sub in run tmp dev boot ''; do
        if mountpoint -q "$root/$sub"; then umount "$root/$sub"; fi
    done
    losetup -d "$loop"
    rmdir "$root"
}
trap cleanup EXIT
for p in 1 2; do
    part=${loop}p$p
    number=$(<"/sys/class/block/$(basename "$part")/dev")
    test -b "$part" || mknod "$part" b "${number%:*}" "${number#*:}"
done
sfdisk --json "$image" | jq -e '.partitiontable.partitions[0] | .start == 8192 and .size == 1048576 and .type == "c" and .bootable == true'
fsck.vfat -n "${loop}p1"
e2fsck -fn "${loop}p2"
mount -o ro,noload "${loop}p2" "$root"
mount -o ro "${loop}p1" "$root/boot"
# Keep the image read-only; chroot tools need device nodes and scratch space.
mount --bind /dev "$root/dev"
mount -t tmpfs -o size=256m tmpfs "$root/tmp"
mount -t tmpfs -o size=16m tmpfs "$root/run"
blob=/armbian/cache/blobs/u-boot-sunxi-with-spl-x96qproplus-b99f4a9.bin
cmp -n "$(stat -c%s "$blob")" -i 8192:0 "$image" "$blob"
cmp "$root/boot/Image" "$ref/boot/Image"
dtb=$root/boot/dtb/allwinner/sun55i-h728-x96qpro+.dtb
cmp "$dtb" "$ref/boot/dtbs/allwinner/sun55i-h728-x96qpro+.dtb"
test "$(fdtget "$dtb" /soc/ethernet@4510000 status)" = okay
test "$(fdtget "$dtb" /soc/ethernet@4510000/mdio/ethernet-phy@1 reg)" = 1
test "$(fdtget "$dtb" /soc/usb@4d00000 status)" = okay
test "$(fdtget "$dtb" /soc/usb@4d00000 dr_mode)" = host
test "$(fdtget "$dtb" /soc/phy@4f00000 status)" = okay
test "$(fdtget -l "$dtb" /cpus | grep -c '^cpu@')" = 8
for cpu in 0 100 200 300 400 500 600 700; do
    test "$(fdtget "$dtb" /cpus/cpu@$cpu compatible)" = arm,cortex-a55
    test "$(fdtget "$dtb" /cpus/cpu@$cpu enable-method)" = psci
    fdtget "$dtb" /cpus/cpu@$cpu clocks
    fdtget "$dtb" /cpus/cpu@$cpu operating-points-v2
done
test "$(fdtget -l "$dtb" /cpus/cpu-map | wc -l)" -eq 2
for module in dwmac_sun55i realtek sun8i_thermal; do
    chroot "$root" modprobe --set-version "$version" --show-depends "$module"
done
test "$(chroot "$root" modinfo -k "$version" -F vermagic dwmac_sun55i | cut -d' ' -f1)" = "$version"
module_path=kernel/drivers/net/ethernet/stmicro/stmmac/dwmac-sun55i.ko
gzip -dc "$ref/usr/lib/modules/$version/$module_path.gz" | cmp - "$root/lib/modules/$version/$module_path"
initrd_listing=$(chroot "$root" lsinitramfs "/boot/initrd.img-$version")
for driver in dwmac-sun55i realtek sun8i_thermal; do
    grep -q "$driver.*\.ko" <<<"$initrd_listing"
done
uuid=$(blkid -s UUID -o value "${loop}p2")
grep -q "root=UUID=$uuid" "$root/boot/extlinux/extlinux.conf"
grep -q "rootdev=UUID=$uuid" "$root/boot/armbianEnv.txt"
grep -q "$uuid" "$root/etc/fstab"
while read -r directive path rest; do
    case "$directive" in LINUX|INITRD|FDT) test -s "$root/boot$path" ;; esac
done <"$root/boot/extlinux/extlinux.conf"
chroot "$root" dpkg --audit
# dpkg-query, not the shell, expands the package metadata placeholder.
# shellcheck disable=SC2016
test "$(chroot "$root" dpkg-query -W -f='${Status}' linux-image-h728-manjaro)" = 'hold ok installed'
test -L "$root/etc/systemd/system/timers.target.wants/h728-diagnostics.timer"
test -L "$root/etc/systemd/system/multi-user.target.wants/ssh.service"
chroot "$root" systemd-analyze verify /etc/systemd/system/h728-diagnostics.service /etc/systemd/system/h728-diagnostics.timer
grep -q 'mirrors.tuna.tsinghua.edu.cn/debian' "$root/etc/apt/sources.list.d/debian.sources"
echo 'PASS: partitions, filesystems, bootloader bytes, matched kernel/DTB/modules/initrd, enabled GMAC1/USB3, eight PSCI CPUs, OPP bindings, SSH and diagnostic timer.'
echo 'Physical board: NOT TESTED. Ethernet link/DHCP, USB enumeration and CPU online/frequency require SD boot.'
