#!/bin/bash
# shellcheck source=common.sh
source /armbian/cache/h728-v3-input/common.sh
test -f "$cache/upgraded"
test -s "$cache/u-boot-sunxi-with-spl-emmc.bin"
mount_image no
install -m0644 "$src/armbian.sources" "$root/etc/apt/sources.list.d/armbian.sources"
install -D -m0644 "$src/base-files.pref" "$root/etc/apt/preferences.d/h728-base-files"
# The old armbian-config third-party source stays disabled; Debian and Armbian
# repositories are now explicitly Trixie, with no Bookworm suite enabled.
apt_in update
apt_in check
install -m0644 "$src/os-release" "$root/etc/os-release"
install -m0755 /armbian/cache/h728-v2-input/h728-diagnostics "$root/usr/local/sbin/h728-diagnostics"
sed -i 's/Armbian v2 hardware report/Armbian v3 hardware report/' "$root/usr/local/sbin/h728-diagnostics"
install -m0755 "$src/h728-install-emmc" "$root/usr/local/sbin/h728-install-emmc"
install -d "$root/usr/lib/h728/uboot"
install -m0644 "$cache/u-boot-sunxi-with-spl-emmc.bin" "$cache/emmc-uboot.sha256" "$cache/emmc-uboot.config" "$root/usr/lib/h728/uboot/"
install -m0644 "$src/h728-ssh-hostkeys.service" "$root/etc/systemd/system/"
install -D -m0644 "$src/ssh-hostkeys.conf" "$root/etc/systemd/system/ssh.service.d/h728-hostkeys.conf"
chroot "$root" systemctl enable ssh.service systemd-networkd.service h728-diagnostics.timer armbian-hardware-optimize.service
uuid=$(blkid -s UUID -o value "${loop}p2")
sed "s/@ROOT_UUID@/$uuid/g; s/@KERNEL_VERSION@/$version/g" "$src/extlinux.conf.in" >"$root/boot/extlinux/extlinux.conf"
sed "s/@ROOT_UUID@/$uuid/g; s/^verbosity=7/verbosity=6/" /armbian/cache/h728-v2-input/armbianEnv.txt.in >"$root/boot/armbianEnv.txt"
# U-Boot expands fdtfile at boot time, not this build shell.
# shellcheck disable=SC2016
sed 's/H728 v2/H728 v3/g; s/verbosity 7/verbosity 6/; s|dtb/allwinner/sun55i-h728-x96qpro+.dtb|dtb/${fdtfile}|' /armbian/cache/h728-v2-input/boot.cmd >"$root/boot/boot.cmd"
mkimage -A arm64 -T script -C none -n 'H728 Trixie v3' -d "$root/boot/boot.cmd" "$root/boot/boot.scr"
install -m0644 "$ref/boot/dtbs/allwinner/sun55i-h728-x96qpro+.dtb" "$root/boot/dtb/allwinner/sun55i-h728-x96qpro+-stock.dtb"
install -m0644 "$src/H728-README.txt" "$root/boot/H728-README.txt"
# Rebuild once using final Trixie initramfs tooling and the installed new modules.
chroot "$root" update-initramfs -u -k "$version"
chroot "$root" netplan generate
chroot "$root" dpkg-query -W >"$cache/installed-packages.txt"
chroot "$root" apt-mark showhold >"$cache/held-packages.txt"
apt_in clean
# Remove only build-time files and baked-in host identities from the NEW image.
rm -f "$root/tmp/h728-kernel-v3.deb" "$root/tmp/h728-bsp-v3.deb" "$root/tmp/h728-kernel.deb"
rm -f "$root/usr/sbin/policy-rc.d" "$root/etc/resolv.conf"
cp -a "$cache/resolv.conf.original" "$root/etc/resolv.conf"
rm -f "$root/etc/ssh/ssh_host_rsa_key" "$root/etc/ssh/ssh_host_rsa_key.pub" \
    "$root/etc/ssh/ssh_host_ecdsa_key" "$root/etc/ssh/ssh_host_ecdsa_key.pub" \
    "$root/etc/ssh/ssh_host_ed25519_key" "$root/etc/ssh/ssh_host_ed25519_key.pub"
truncate -s 0 "$root/etc/machine-id"
rm -f "$root/var/lib/dbus/machine-id"
ln -s /etc/machine-id "$root/var/lib/dbus/machine-id"
rm -f "$root/var/lib/systemd/random-seed"
# Remove the obsolete rc kernel boot payload; the separate v2 image is retained.
old=6.17.0-rc1-2-MANJARO-ARM+
rm -f "$root/boot/vmlinuz-$old" "$root/boot/initrd.img-$old" "$root/boot/config-$old" "$root/boot/uInitrd-$old"
sync
touch "$cache/finalized"
echo 'Finalized Trixie v3 image, first-boot identities, diagnostics and eMMC installer.'
