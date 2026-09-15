#!/bin/bash
set -euo pipefail
src=/armbian/cache/h728-source-input
export H728_INPUT_DIR=$src
export H728_CACHE_DIR=/armbian/cache/h728-source-image-test1
export H728_IMAGE=$H728_CACHE_DIR/source-test1.img
# shellcheck source=common.sh
source "$src/common.sh"
version=7.2.0-h728-test1
base=/armbian/cache/h728-v3.1.3/v3.1.3-working.img
package=/armbian/output/debs/linux-image-h728-source_7.2.0-1+h728test1_arm64.deb
printf '%s  %s\n' 07625d11b198bf9b42c88d185a2566993c4e990d5ef692d95277e71fd4a53e17 "$base" | sha256sum -c -
test -s "$package"
test ! -e "$image" || { echo 'Working image exists; refusing overwrite'; exit 1; }
cp --sparse=never "$base" "$image"
mount_image no
oldroot=$(blkid -s UUID -o value "${loop}p2")
oldboot=$(blkid -s UUID -o value "${loop}p1")
cleanup
trap - EXIT
loop=$(losetup --find --show --partscan "$image")
trap 'losetup -d "$loop"' EXIT
# Device nodes have been created by mount_image; same partition numbers.
for p in 1 2; do
    part=${loop}p$p
    number=$(<"/sys/class/block/${part##*/}/dev")
    if [[ ! -b $part || $(stat -c '%t:%T' "$part") != "$(printf '%x:%x' "${number%:*}" "${number#*:}")" ]]; then
        rm -f "$part"
        mknod "$part" b "${number%:*}" "${number#*:}"
    fi
done
e2fsck -pf "${loop}p2" || test "$?" -eq 1
tune2fs -U random "${loop}p2"
fatid=$(od -An -N4 -tx4 /dev/urandom | tr -d ' ')
fatlabel -i "${loop}p1" "$fatid"
losetup -d "$loop"
trap - EXIT
mount_image no
uuid=$(blkid -s UUID -o value "${loop}p2")
bootuuid=$(blkid -s UUID -o value "${loop}p1")
test "$uuid" != "$oldroot"
test "$bootuuid" != "$oldboot"
sed -i "s/$oldroot/$uuid/g; s/$oldboot/$bootuuid/g" "$root/etc/fstab" "$root/boot/armbianEnv.txt" "$root/boot/extlinux/extlinux.conf"
cp "$root/boot/Image" "$root/boot/Image-reference"
cp "$root/boot/dtb/allwinner/sun55i-h728-x96qpro+.dtb" "$root/boot/dtb/allwinner/sun55i-h728-reference.dtb"
printf '#!/bin/sh\nexit 101\n' > "$root/usr/sbin/policy-rc.d"
chmod 755 "$root/usr/sbin/policy-rc.d"
cp "$package" "$root/tmp/source-kernel.deb"
chroot "$root" dpkg -i /tmp/source-kernel.deb
chroot "$root" apt-mark hold linux-image-h728-source linux-image-h728-manjaro
chroot "$root" apt-get check
sed -i 's@^fdtfile=.*@fdtfile=allwinner/sun55i-h728-test1.dtb@' "$root/boot/armbianEnv.txt"
printf '%s\n' 'DEFAULT source-test1' 'TIMEOUT 50' 'MENU TITLE H728 source kernel test1 - SD only' '' \
    'LABEL source-test1' '    MENU LABEL Linux 7.2 source - pinctrl test' '    LINUX /Image' \
    "    INITRD /initrd.img-$version" '    FDT /dtb/allwinner/sun55i-h728-test1.dtb' \
    "    APPEND root=UUID=$uuid rootwait rw rootfstype=ext4 console=ttyS0,115200 earlycon=uart8250,mmio32,0x02500000 loglevel=7 panic=10" '' \
    'LABEL reference' '    MENU LABEL Original reference kernel recovery (Wi-Fi not guaranteed)' \
    '    LINUX /Image-reference' '    INITRD /initrd.img-7.2.0-7-MANJARO-ARM' \
    '    FDT /dtb/allwinner/sun55i-h728-reference.dtb' \
    "    APPEND root=UUID=$uuid rootwait rw rootfstype=ext4 console=ttyS0,115200 earlycon=uart8250,mmio32,0x02500000 loglevel=7 panic=10" > "$root/boot/extlinux/extlinux.conf"
mkimage -A arm64 -O linux -T ramdisk -C none -n "$version" -d "$root/boot/initrd.img-$version" "$root/boot/uInitrd"
install -m0755 "$src/h728-install-emmc" "$root/usr/local/sbin/h728-install-emmc"
install -m0644 "$src/TEST-IMAGE.md" "$root/boot/H728-README.txt"
install -m0644 "$src/TEST-IMAGE.md" "$root/boot/EMMC-INSTALL.md"
printf 'VERSION=v3.2.0-test1\nMODE=standalone-sd\nEMMC_INSTALL=disabled\nKERNEL=%s\nWIFI_SDIO_MAX_HZ=24000000\nWIFI_BUS_WIDTH=4\nWIFI_DRIVE_MA=20\n' "$version" > "$root/etc/h728-image-release"
truncate -s 0 "$root/etc/machine-id"
for key in rsa ecdsa ed25519; do
    rm -f "$root/etc/ssh/ssh_host_${key}_key" "$root/etc/ssh/ssh_host_${key}_key.pub"
done
rm -f "$root/var/lib/systemd/random-seed" "$root/usr/sbin/policy-rc.d" "$root/tmp/source-kernel.deb"
chroot "$root" dpkg --audit
sync
cleanup
trap - EXIT
touch "$cache/finalized"
echo 'Assembled. Read-only verification required before delivery.'
