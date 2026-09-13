#!/bin/bash
# Validate staged or installed payload without accessing any physical device.
set -euo pipefail
cd "${1:?payload directory required}"
sha256sum -c bundle.sha256
sha256sum -c emmc-uboot.sha256
grep -qx CONFIG_SYS_MMC_MAX_BLK_COUNT=1 emmc-uboot.config
grep -qx CONFIG_MMC_SUNXI_SLOT_EXTRA=2 emmc-uboot.config
if grep -qx CONFIG_SPL_LOG=y emmc-uboot.config; then
    echo 'Refusing instrumented debug payload' >&2
    exit 1
fi
test "$(fdtget emmc-uboot.dtb /soc/mmc@4022000 status)" = okay
test "$(fdtget emmc-uboot.dtb /soc/mmc@4022000 bus-width)" = 1
test "$(fdtget emmc-uboot.dtb /soc/mmc@4022000 max-frequency)" = 26000000
blob=u-boot-sunxi-with-spl-emmc.bin
test "$(dd if="$blob" bs=1 skip=4 count=8 status=none)" = eGON.BT0
size=$(stat -c%s "$blob")
test "$size" -gt 262144
# Conservative packaging limit, NOT permission to flash any disk layout.
test "$size" -le $((1048576 - 8192))
