#!/bin/bash
set -euo pipefail
src=/armbian/cache/h728-source-input
work=/tmp/h728-source-test1
version=7.2.0-h728-test1
package=/armbian/output/debs/linux-image-h728-source_7.2.0-1+h728test1_arm64.deb
test ! -e "$package" || { echo 'Package exists; refusing overwrite'; exit 1; }
test "$(make -s -C "$work/linux-7.2" ARCH=arm64 O="$work/obj" kernelrelease)" = "$version"
pkg=$(mktemp -d /tmp/h728-source-package.XXXXXX)
make -C "$work/linux-7.2" ARCH=arm64 O="$work/obj" INSTALL_MOD_PATH="$pkg" INSTALL_MOD_STRIP=1 modules_install
find "$pkg/lib/modules/$version" -type l -name build -delete
find "$pkg/lib/modules/$version" -name '*.ko.gz' -exec gunzip '{}' +
depmod -b "$pkg" "$version"
payload=$pkg/usr/lib/linux-image-h728-source
install -d "$payload" "$pkg/DEBIAN"
install -m0644 "$work/obj/arch/arm64/boot/Image" "$payload/Image"
install -m0644 "$work/obj/.config" "$payload/config"
install -m0644 "$work/obj/System.map" "$payload/System.map"
dtc -q -I dts -O dtb -o "$payload/sun55i-h728-test1.dtb" "$src/sun55i-h728-test1.dts"
install -m0755 "$src/kernel-postinst" "$pkg/DEBIAN/postinst"
printf '%s\n' 'Package: linux-image-h728-source' 'Version: 7.2.0-1+h728test1' 'Architecture: arm64' 'Maintainer: H728 experimental image project' 'Depends: initramfs-tools, kmod' 'Description: Source-built Linux 7.2 H728 SD-only test kernel' > "$pkg/DEBIAN/control"
dpkg-deb --root-owner-group -Zxz --build "$pkg" "$package"
install -d /armbian/output/h728-source-test1
cp "$work/obj/.config" /armbian/output/h728-source-test1/config
cp "$work/obj/System.map" /armbian/output/h728-source-test1/System.map
cp "$work/obj/Module.symvers" /armbian/output/h728-source-test1/Module.symvers
sha256sum "$package"
