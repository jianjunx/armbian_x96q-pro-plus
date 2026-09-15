#!/bin/bash
set -euo pipefail
src=/armbian/cache/h728-source-input
export H728_INPUT_DIR=$src
export H728_CACHE_DIR=/armbian/cache/h728-source-image-test1
export H728_IMAGE=$H728_CACHE_DIR/source-test1.img
# shellcheck source=common.sh
source "$src/common.sh"
version=7.2.0-h728-test1
test -f "$cache/finalized"
mount_image yes
test "$(stat -c%s "$image")" -eq 4294967296
sfdisk --json "$image" | jq -e '.partitiontable.partitions | .[0].start == 8192 and .[0].type == "c" and .[0].bootable and .[1].start == 1056768'
blob=/armbian/cache/blobs/u-boot-sunxi-with-spl-x96qproplus-b99f4a9.bin
cmp -n "$(stat -c%s "$blob")" -i 8192:0 "$image" "$blob"
payload=$root/usr/lib/linux-image-h728-source
cmp "$payload/Image" "$root/boot/Image"
cmp /tmp/h728-source-test1/obj/arch/arm64/boot/Image "$root/boot/Image"
cmp "$payload/config" /tmp/h728-source-test1/obj/.config
cmp "$root/boot/Image-reference" "$ref/boot/Image"
dtb=$root/boot/dtb/allwinner/sun55i-h728-test1.dtb
cmp "$payload/sun55i-h728-test1.dtb" "$dtb"
dtc -q -I dts -O dtb -o "$root/tmp/expected.dtb" "$src/sun55i-h728-test1.dts"
cmp "$root/tmp/expected.dtb" "$dtb"
for node in /soc/ethernet@4510000 /soc/usb@4d00000 /soc/phy@4f00000 /soc/mmc@4020000 /soc/mmc@4021000 /soc/mmc@4022000; do
    test "$(fdtget "$dtb" "$node" status)" = okay
done
test "$(fdtget "$dtb" /soc/mmc@4021000 max-frequency)" -eq 24000000
test "$(fdtget "$dtb" /soc/mmc@4021000 bus-width)" -eq 4
test "$(fdtget "$dtb" /soc/pinctrl@2000000/mmc1-pins drive-strength)" -eq 20
test "$(fdtget -t x "$dtb" /soc/mmc@4022000 vmmc-supply)" = "$(fdtget -t x "$dtb" /vcc3v3 phandle)"
test "$(fdtget "$dtb" /soc/mmc@4022000 max-frequency)" -eq 52000000
test "$(fdtget -l "$dtb" /cpus | grep -c '^cpu@')" -eq 8
for cpu in 0 100 200 300 400 500 600 700; do
    test "$(fdtget "$dtb" /cpus/cpu@$cpu compatible)" = arm,cortex-a55
    fdtget "$dtb" /cpus/cpu@$cpu operating-points-v2 >/dev/null
done
for module in dwmac_sun55i realtek sun8i_thermal aic8800_bsp aic8800_fdrv; do
    chroot "$root" modprobe --set-version "$version" --show-depends "$module"
    test "$(chroot "$root" modinfo -k "$version" -F vermagic "$module" | cut -d' ' -f1)" = "$version"
done
listing=$(chroot "$root" lsinitramfs "/boot/initrd.img-$version")
for driver in dwmac-sun55i realtek sun8i_thermal; do
    grep -q "$driver.*\.ko" <<< "$listing"
done
dd if="$root/boot/uInitrd" bs=64 skip=1 status=none | cmp - "$root/boot/initrd.img-$version"
uuid=$(blkid -s UUID -o value "${loop}p2")
bootuuid=$(blkid -s UUID -o value "${loop}p1")
grep -qx "rootdev=UUID=$uuid" "$root/boot/armbianEnv.txt"
grep -q "$uuid" "$root/etc/fstab"
grep -q "$bootuuid" "$root/etc/fstab"
awk -v id="$uuid" '$1=="APPEND" && index($0,"root=UUID=" id)==0 {exit 1}' "$root/boot/extlinux/extlinux.conf"
while read -r directive path _; do
    case "$directive" in LINUX|INITRD|FDT) test -s "$root/boot$path" ;; esac
done < "$root/boot/extlinux/extlinux.conf"
grep -qx VERSION_CODENAME=trixie "$root/etc/os-release"
test -z "$(chroot "$root" dpkg --audit)"
chroot "$root" apt-get check
chroot "$root" apt-mark showhold | grep -qx linux-image-h728-source
for file in "$root/etc/apt/sources.list" "$root/etc/apt/sources.list.d/"*.list "$root/etc/apt/sources.list.d/"*.sources; do
    test -f "$file" || continue
    if sed '/^[[:space:]]*#/d' "$file" | grep -qi bookworm; then exit 1; fi
done
tar -xzf /armbian/output/repairs/h728-v2.1-repair.tar.gz -C "$root/tmp"
for firmware in "$root/tmp/h728-v2.1-repair/firmware/"*; do
    cmp "$firmware" "$root/usr/lib/firmware/aic8800_sdio/$(basename "$firmware")"
done
cmp "$src/h728-install-emmc" "$root/usr/local/sbin/h728-install-emmc"
grep -qx EMMC_INSTALL=disabled "$root/etc/h728-image-release"
test ! -s "$root/etc/machine-id"
test ! -e "$root/usr/sbin/policy-rc.d"
for key in rsa ecdsa ed25519; do test ! -e "$root/etc/ssh/ssh_host_${key}_key"; done
test -f "$root/root/.not_logged_in_yet"
# shellcheck disable=SC2016
chroot "$root" perl -e 'open(my $f,"<","/etc/shadow") or die; while(<$f>){my @p=split /:/; if($p[0] eq "root"){crypt("1234",$p[1]) eq $p[1] or die "Unexpected root password"; exit 0}} die "No root account"'
chroot "$root" mkdir -p /run/sshd
chroot "$root" ssh-keygen -q -t ed25519 -N '' -f /tmp/ssh-test-key
chroot "$root" sshd -t -h /tmp/ssh-test-key
chroot "$root" systemd-analyze verify /etc/systemd/system/h728-ssh-hostkeys.service
echo 'PASS: filesystems, bootloader, source Image/config/modules/DTB, initramfs, UUIDs, firmware, Trixie, initial SSH identity, disabled eMMC installer.'
echo 'NOT HARDWARE VALIDATED. HDMI/DE35 source support is not provided by this test kernel; use Ethernet SSH/UART.'
