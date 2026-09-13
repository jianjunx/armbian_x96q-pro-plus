#!/bin/bash
set -euo pipefail
config_script=$(cd -- "$(dirname -- "$0")" && pwd)/configure-emmc-uboot.sh
work=$(mktemp -d /tmp/h728-emmc-uboot.XXXXXX)
tar -xf /tmp/h728-uboot-source.tar.gz -C "$work"
tar -xf /tmp/h728-atf-source.tar.gz -C "$work"
uboot=$work/u-boot-b99f4a9e0778f4f402619d70976537d4833d7eab
atf=$work/arm-trusted-firmware-b5de74a685fb73b784e45bbbd18dd9a0c528d8b2
make -C "$atf" -j4 CROSS_COMPILE=aarch64-linux-gnu- PLAT=sun55i_a523 bl31
cp "$atf/build/sun55i_a523/release/bl31.bin" "$uboot/bl31.bin"
make -C "$uboot" CROSS_COMPILE=aarch64-linux-gnu- x96q_pro_plus_defconfig
cd "$uboot"
patch -p1 < /armbian/cache/h728-v3-input/uboot-emmc.patch
bash "$config_script" apply
make CROSS_COMPILE=aarch64-linux-gnu- olddefconfig
bash "$config_script" check
make -j4 CROSS_COMPILE=aarch64-linux-gnu- EXTRAVERSION=-h728-emmc-v3
test "$(grep '^CONFIG_MMC_SUNXI_SLOT_EXTRA=' .config)" = CONFIG_MMC_SUNXI_SLOT_EXTRA=2
out=/armbian/cache/h728-v3
install -m0644 u-boot-sunxi-with-spl.bin "$out/u-boot-sunxi-with-spl-emmc.bin"
install -m0644 .config "$out/emmc-uboot.config"
cd "$out"
sha256sum u-boot-sunxi-with-spl-emmc.bin >emmc-uboot.sha256
