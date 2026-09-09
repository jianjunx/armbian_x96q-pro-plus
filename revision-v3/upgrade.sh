#!/bin/bash
# shellcheck source=common.sh
source /armbian/cache/h728-v3-input/common.sh
test -f "$cache/prepared"
mount_image no
if [[ ! -f $cache/bookworm-updated ]]; then
    # The source v2 is a never-booted release image, not the user's live SD card.
    sed -i 's/ bookworm-backports//g' "$root/etc/apt/sources.list.d/debian.sources"
    apt_in update
    apt_in -y upgrade --without-new-pkgs
    touch "$cache/bookworm-updated"
fi
install -m0644 "$src/debian.sources" "$root/etc/apt/sources.list.d/debian.sources"
apt_in update
# The original BSP requires the Armbian-specific numeric base-files version.
# Repackage that metadata to allow the real Debian 13 base-files package.
if [[ ! -f $cache/bsp-trixie-adapted ]]; then
    stage=$(mktemp -d /tmp/h728-v3-bsp.XXXXXX)
    dpkg-deb -R /armbian/output/debs/armbian-bsp-cli-x96q-pro-plus-current_26.11.0-trunk_arm64__1-PCf08b-Va99a-H01ba-Bca11-R1b1e.deb "$stage"
    sed -i 's/^Version: .*/Version: 26.11.0-trunk+h728.3/; s/base-files (>= 26.11.0-trunk)/base-files (>= 13)/' "$stage/DEBIAN/control"
    bsp=/armbian/output/debs/armbian-bsp-cli-x96q-pro-plus-current_26.11.0-trunk+h728.3_arm64.deb
    dpkg-deb --root-owner-group --build "$stage" "$bsp"
    cp "$bsp" "$root/tmp/h728-bsp-v3.deb"
    chroot "$root" apt-mark unhold armbian-bsp-cli-x96q-pro-plus-current
    chroot "$root" dpkg -i /tmp/h728-bsp-v3.deb
    chroot "$root" apt-mark hold armbian-bsp-cli-x96q-pro-plus-current
    touch "$cache/bsp-trixie-adapted"
fi
# The Armbian-branded base-files has a numerically higher version than Debian's.
# Deliberately select the target Debian suite so real OS metadata is upgraded.
apt_in -y --allow-downgrades install base-files/trixie
apt_in -y upgrade --without-new-pkgs
apt_in -s dist-upgrade >"$cache/trixie-upgrade-plan.txt"
cat "$cache/trixie-upgrade-plan.txt"
if grep -E '^Remv (linux-image-h728-manjaro|linux-u-boot-x96q-pro-plus-current|armbian-bsp-cli-x96q-pro-plus-current|openssh-server|systemd-sysv|netplan.io) ' "$cache/trixie-upgrade-plan.txt"; then
    echo 'Unexpected removal of a boot/network package; inspect the saved plan.'; exit 1
fi
apt_in -y dist-upgrade
apt_in -y install iw rfkill wpasupplicant wireless-regdb
chroot "$root" apt-mark unhold linux-image-h728-manjaro
chroot "$root" dpkg -i /tmp/h728-kernel-v3.deb
chroot "$root" apt-mark hold linux-image-h728-manjaro linux-u-boot-x96q-pro-plus-current armbian-bsp-cli-x96q-pro-plus-current
chroot "$root" dpkg --audit
apt_in check
touch "$cache/upgraded"
echo 'Trixie package upgrade and 7.2 kernel installation completed.'
