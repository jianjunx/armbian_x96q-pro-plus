#!/bin/bash
# Run in the privileged h728-image-build container; /armbian is the build tree.
set -euo pipefail
src=/armbian/cache/h728-v2-input
ref=/armbian/cache/h728-audit/reference
version=6.17.0-rc1-2-MANJARO-ARM+
out=/armbian/output/images
old=$out/Armbian-unofficial_26.11.0-trunk_X96q-pro-plus_bookworm_current_6.18.48_minimal.img
new=$out/Armbian_X96Q-Pro-Plus_H728_Bookworm_6.17-2_v2.img
pkg=/armbian/output/debs/linux-image-h728-manjaro_6.17.0~rc1-2+h728.2_arm64.deb
test ! -e "$new" || { echo "Output already exists: $new"; exit 1; }
test "$(sha256sum "$old" | cut -d' ' -f1)" = 412f4c9b18ca389aeb314cf5259511b6a4798d4086d06361d9ae88c476b6883a
test "$(sha256sum /tmp/h728-reference.pkg.tar.zst | cut -d' ' -f1)" = 88d4f914cc395a8fad040da12055de5178134c1c88f27a79bc3afb9897e64a69
work=$(mktemp -d /tmp/h728-v2.XXXXXX)
root=$work/root
loop=
cleanup() {
    for mount in dev/pts dev proc sys boot ''; do
        if mountpoint -q "$root/$mount"; then umount "$root/$mount"; fi
    done
    [ -z "$loop" ] || losetup -d "$loop"
}
trap cleanup EXIT

# The Debian package installs matching modules, configuration, Image and DTB.
stage=$work/package
payload=$stage/usr/lib/linux-image-h728-manjaro
mkdir -p "$stage/DEBIAN" "$payload" "$stage/lib/modules" "$root"
install -m0644 "$src/kernel-control" "$stage/DEBIAN/control"
install -m0755 "$src/kernel-postinst" "$stage/DEBIAN/postinst"
cp -a "$ref/usr/lib/modules/$version" "$stage/lib/modules/"
cp -a "$ref/usr/lib/modules/extramodules-6.17-sunxi" "$stage/lib/modules/"
# Debian's kmod is built without zlib and cannot load Manjaro's .ko.gz.
# Decompress the modules (no changes to their ELF content) before depmod.
find "$stage/lib/modules/$version" -type f -name '*.ko.gz' -exec gzip -d {} +
install -m0644 "$ref/boot/Image" "$payload/Image"
install -m0644 /armbian/cache/h728-audit/reference.config "$payload/config"
install -m0644 "$ref/boot/dtbs/allwinner/sun55i-h728-x96qpro+.dtb" "$payload/"
dpkg-deb --root-owner-group -Zxz --build "$stage" "$pkg"

# OrbStack's macOS bind mount does not support Linux hole punching.
cp --sparse=never "$old" "$new"
# Standard FAT32 LBA partition type and active flag for U-Boot's distro scan.
sfdisk --part-type "$new" 1 c
sfdisk --activate "$new" 1
loop=$(losetup --find --show --partscan "$new")
for p in 1 2; do
    part=${loop}p$p
    number=$(<"/sys/class/block/$(basename "$part")/dev")
    test -b "$part" || mknod "$part" b "${number%:*}" "${number#*:}"
done
mount "${loop}p2" "$root"
mount "${loop}p1" "$root/boot"
mount --bind /dev "$root/dev"
mount -t proc proc "$root/proc"
mount -t sysfs sysfs "$root/sys"

chroot "$root" dpkg --remove linux-image-current-sunxi64 linux-dtb-current-sunxi64
install -m0644 "$src/h728-modules.conf" "$root/etc/modules-load.d/h728.conf"
# Include the ethernet/thermal modules before userspace discovery as well.
install -m0644 "$src/h728-modules.conf" "$root/etc/initramfs-tools/modules"
cp "$pkg" "$root/tmp/h728-kernel.deb"
chroot "$root" dpkg -i /tmp/h728-kernel.deb
chroot "$root" apt-mark hold linux-image-h728-manjaro linux-u-boot-x96q-pro-plus-current armbian-bsp-cli-x96q-pro-plus-current
install -m0755 "$src/h728-diagnostics" "$root/usr/local/sbin/h728-diagnostics"
install -m0644 "$src/h728-diagnostics.service" "$src/h728-diagnostics.timer" "$root/etc/systemd/system/"
chroot "$root" systemctl enable h728-diagnostics.timer ssh.service systemd-networkd.service

uuid=$(blkid -s UUID -o value "${loop}p2")
install -m0644 "$src/boot.cmd" "$root/boot/boot.cmd"
mkimage -A arm64 -T script -C none -n 'H728 Armbian v2' -d "$root/boot/boot.cmd" "$root/boot/boot.scr"
mkdir -p "$root/boot/extlinux"
sed "s/@ROOT_UUID@/$uuid/g; s/@KERNEL_VERSION@/$version/g" "$src/extlinux.conf.in" >"$root/boot/extlinux/extlinux.conf"
sed "s/@ROOT_UUID@/$uuid/g" "$src/armbianEnv.txt.in" >"$root/boot/armbianEnv.txt"
install -m0644 "$src/README.txt" "$root/boot/H728-README.txt"
# Verify replacement payloads are byte-identical to the hardware reference.
cmp "$ref/boot/Image" "$root/boot/Image"
cmp "$ref/boot/dtbs/allwinner/sun55i-h728-x96qpro+.dtb" "$root/boot/dtb/allwinner/sun55i-h728-x96qpro+.dtb"
chroot "$root" modprobe --set-version "$version" --show-depends dwmac_sun55i
chroot "$root" modprobe --set-version "$version" --show-depends realtek
chroot "$root" modprobe --set-version "$version" --show-depends sun8i_thermal
chroot "$root" dpkg --audit
chroot "$root" lsinitramfs "/boot/initrd.img-$version" | grep -E 'dwmac-sun55i|realtek.ko|sun8i_thermal' >"$work/initrd-drivers.txt"
cat "$work/initrd-drivers.txt"
sync
cleanup
trap - EXIT
cd "$out"
sha256sum "$(basename "$new")" >"$new.sha256"
echo "Built $new"
