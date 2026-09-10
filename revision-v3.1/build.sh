#!/bin/bash
set -euo pipefail
src=/armbian/cache/h728-v3.1-input
# shellcheck source=settings.sh
source "$src/settings.sh"
# shellcheck source=base-common.sh
source "$H728_COMMON"
base=/armbian/output/images/Armbian_X96Q-Pro-Plus_H728_Trixie_7.2.0-7_v3.img
oldpkg=/armbian/output/debs/linux-image-h728-manjaro_7.2.0-7+h728.3_arm64.deb
test ! -e "$image" || { echo 'Working image exists; preserve it, do not overwrite.'; exit 1; }
test ! -e "$package" || { echo 'New kernel package already exists; refusing overwrite.'; exit 1; }
printf '%s  %s\n' \
    46b5720330065a731169f60bab260b0b46a23f8b1ec37e4497e690078ddebfec "$base" \
    f437b98bf59b8ad78f5aa58ee0294c9a1ccfe344229078cf8e9e2251df6f6a40 "$oldpkg" \
    d94be64757c9860c1d68ef88aa0acf552735b48076edb0fc12223bb76dbca629 /armbian/output/repairs/h728-v2.1-repair.tar.gz \
    0914b3859e86f91e8bdfc64d19b1f3ad3036c50521a0c00b2bce578982145b7c /armbian/cache/blobs/u-boot-sunxi-with-spl-x96qproplus-b99f4a9.bin | sha256sum -c -
work=$(mktemp -d /tmp/h728-v3.1-build.XXXXXX)
dpkg-deb -R "$oldpkg" "$work/kernel"
sed -i 's/^Version: .*/Version: 7.2.0-7+h728.4/' "$work/kernel/DEBIAN/control"
payload=$work/kernel/usr/lib/linux-image-h728-manjaro
cp "$ref/boot/dtbs/allwinner/sun55i-h728-x96qpro+.dtb" "$payload/sun55i-h728-x96qpro+.dtb"
bash "$src/patch-emmc-dtb.sh" "$payload/sun55i-h728-x96qpro+.dtb"
printf '%s  %s\n' be1028ce193f0948f0476c03851a6a6da82ce5b4cf40d83c1c472cc47b9b2567 "$payload/sun55i-h728-x96qpro+.dtb" | sha256sum -c -
cmp "$payload/Image" "$ref/boot/Image"
dpkg-deb --root-owner-group -Zxz --build "$work/kernel" "$package"
cp --sparse=never "$base" "$image"
mount_image no
oldroot=$(blkid -s UUID -o value "${loop}p2")
oldboot=$(blkid -s UUID -o value "${loop}p1")
# Filesystem IDs must be changed while unmounted.
cleanup
trap - EXIT
loop=$(losetup --find --show --partscan "$image")
trap 'losetup -d "$loop"' EXIT
for p in 1 2; do
    part=${loop}p$p
    number=$(cat "/sys/class/block/${part##*/}/dev")
    expected=$(printf '%x:%x' "${number%:*}" "${number#*:}")
    if [[ ! -b $part || $(stat -c '%t:%T' "$part") != "$expected" ]]; then
        rm -f "$part"
        mknod "$part" b "${number%:*}" "${number#*:}"
    fi
done
if e2fsck -pf "${loop}p2"; then
    :
else
    fsck_status=$?
    test "$fsck_status" -eq 1 || exit "$fsck_status"
fi
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
printf '#!/bin/sh\nexit 101\n' >"$root/usr/sbin/policy-rc.d"
chmod 755 "$root/usr/sbin/policy-rc.d"
cp "$package" "$root/tmp/h728-v3.1-kernel.deb"
chroot "$root" dpkg -i /tmp/h728-v3.1-kernel.deb
chroot "$root" apt-mark hold linux-image-h728-manjaro
chroot "$root" apt-get check
sed -i -E 's/loglevel=[0-9]+/loglevel=7/g; s/Trixie v3$/Trixie v3.1/; s/eMMC enabled \(52 MHz SDR\)/SD system - corrected eMMC supply/' "$root/boot/extlinux/extlinux.conf"
sed -i -E 's/^verbosity=.*/verbosity=7/; /^extraargs=/{s/ loglevel=[0-9]+//g; s/$/ loglevel=7/;}' "$root/boot/armbianEnv.txt"
sed -i 's/setenv verbosity 6/setenv verbosity 7/; s/H728 v3/H728 v3.1/g' "$root/boot/boot.cmd"
mkimage -A arm64 -T script -C none -n 'H728 Trixie v3.1 SD' -d "$root/boot/boot.cmd" "$root/boot/boot.scr"
# Convert the inherited full diagnostic into a stdout-only collector.
install -d "$root/usr/local/lib"
# shellcheck disable=SC2016
sed '/^report=/d; s/Armbian v3 hardware report/Armbian v3.1 hardware report/; s/} >"$report" 2>\&1/}/; /^mv -f /d; /^sync -f /d' \
    "$root/usr/local/sbin/h728-diagnostics" >"$root/usr/local/lib/h728-diagnostics-base"
chmod 755 "$root/usr/local/lib/h728-diagnostics-base"
install -m0755 "$src/h728-diagnostics" "$root/usr/local/sbin/h728-diagnostics"
install -m0755 "$src/h728-install-emmc" "$root/usr/local/sbin/h728-install-emmc"
install -m0644 "$src/h728-diagnostics.service" "$root/etc/systemd/system/h728-diagnostics.service"
if [[ -f $root/lib/systemd/system/exim4.service || -f $root/usr/lib/systemd/system/exim4.service || -f $root/etc/init.d/exim4 ]]; then
    chroot "$root" systemctl disable exim4.service
    chroot "$root" systemctl mask exim4.service
fi
install -m0644 "$src/H728-README.txt" "$root/boot/H728-README.txt"
printf 'VERSION=v3.1\nMODE=standalone-sd\nEMMC_INSTALL=disabled\n' >"$root/etc/h728-image-release"
chroot "$root" dpkg-query -W >"$cache/installed-packages.txt"
chroot "$root" dpkg --audit
# Preserve first-login provisioning and remove only identities in the new image.
truncate -s 0 "$root/etc/machine-id"
rm -f "$root/etc/ssh/ssh_host_rsa_key" "$root/etc/ssh/ssh_host_rsa_key.pub" \
    "$root/etc/ssh/ssh_host_ecdsa_key" "$root/etc/ssh/ssh_host_ecdsa_key.pub" \
    "$root/etc/ssh/ssh_host_ed25519_key" "$root/etc/ssh/ssh_host_ed25519_key.pub" \
    "$root/var/lib/systemd/random-seed" "$root/usr/sbin/policy-rc.d" "$root/tmp/h728-v3.1-kernel.deb"
sync
cleanup
trap - EXIT
touch "$cache/finalized"
echo 'v3.1 assembled. Must run verify.sh before delivery.'
