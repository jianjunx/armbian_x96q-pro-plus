#!/bin/bash
# shellcheck source=common.sh
source /armbian/cache/h728-v3-input/common.sh
old=/armbian/output/images/Armbian_X96Q-Pro-Plus_H728_Bookworm_6.17-2_v2.img
test ! -e "$image" || { echo 'Working image exists; use subsequent stages or preserve it before rebuilding.'; exit 1; }
test "$(sha256sum "$old" | cut -d' ' -f1)" = f3718e92a5ee1bfbc2f227bd3144f2c6f0234e6a761b5facd7ddd8b63c91ec29
test "$(sha256sum /tmp/h728-kernel-7.2.pkg.tar.xz | cut -d' ' -f1)" = b45281c8ab874587f85e0d6926273a79f88f8ab637c46b3a67616f1f60d5aa1d
work=$(mktemp -d /tmp/h728-v3-package.XXXXXX)
payload=$work/package/usr/lib/linux-image-h728-manjaro
mkdir -p "$payload" "$work/package/DEBIAN" "$work/package/lib/modules"
cp -a "$ref/usr/lib/modules/$version" "$ref/usr/lib/modules/extramodules-7.2-sunxi" "$work/package/lib/modules/"
find "$work/package/lib/modules/$version" -type f -name '*.ko.gz' -exec gzip -d {} +
install -m0644 "$src/kernel-control" "$work/package/DEBIAN/control"
install -m0755 "$src/kernel-postinst" "$work/package/DEBIAN/postinst"
install -m0644 "$ref/boot/Image" "$payload/Image"
install -m0644 /armbian/cache/h728-audit/reference-7.2.config "$payload/config"
install -m0644 "$ref/boot/dtbs/allwinner/sun55i-h728-x96qpro+.dtb" "$payload/"
bash "$src/patch-emmc-dtb.sh" "$payload/sun55i-h728-x96qpro+.dtb"
dpkg-deb --root-owner-group -Zxz --build "$work/package" "$package"
cp --sparse=never "$old" "$image"
truncate -s 4G "$image"
printf 'start=1056768, size=7331840, type=83\n' | sfdisk --no-reread -N 2 "$image"
loop=$(losetup --find --show --partscan "$image")
trap 'losetup -d "$loop"' EXIT
for p in 1 2; do
    part=${loop}p$p
    number=$(<"/sys/class/block/$(basename "$part")/dev")
    test -b "$part" || mknod "$part" b "${number%:*}" "${number#*:}"
done
e2fsck -fy "${loop}p2"
resize2fs "${loop}p2"
tune2fs -U random "${loop}p2"
fatlabel -i "${loop}p1" 72830001
losetup -d "$loop"
trap - EXIT
mount_image no
tar -xzf /armbian/output/repairs/h728-v2.1-repair.tar.gz -C "$work"
bash "$work/h728-v2.1-repair/install.sh" --root "$root"
install -m0755 "$src/policy-rc.d" "$root/usr/sbin/policy-rc.d"
# Local chroot DNS only; the image's original resolver arrangement is restored later.
cp -a "$root/etc/resolv.conf" "$cache/resolv.conf.original"
rm "$root/etc/resolv.conf"
cp -L /etc/resolv.conf "$root/etc/resolv.conf"
mkdir -p "$root/etc/apt/sources.list.d/build-disabled"
mv "$root/etc/apt/sources.list.d/armbian.sources" "$root/etc/apt/sources.list.d/build-disabled/"
if [[ -f $root/etc/apt/sources.list.d/armbian-config.sources ]]; then
    mv "$root/etc/apt/sources.list.d/armbian-config.sources" "$root/etc/apt/sources.list.d/build-disabled/"
fi
uuid=$(blkid -s UUID -o value "${loop}p2")
sed -i "s/0956215a-b771-4b93-8a68-d968be52fcfe/$uuid/g; s/186B-EA51/7283-0001/g" "$root/etc/fstab"
cp "$package" "$root/tmp/h728-kernel-v3.deb"
touch "$cache/prepared"
echo 'Prepared independent v3 working image and kernel package.'
