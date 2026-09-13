#!/bin/bash
# Run inside the configured pinned U-Boot tree. All build entry points use this.
set -euo pipefail
case "${1:-apply}" in
    apply)
        scripts/config --set-val MMC_SUNXI_SLOT_EXTRA 2
        scripts/config --set-str IDENT_STRING ' H728 eMMC v3'
        scripts/config --enable OF_LIBFDT_OVERLAY
        # Both SPL and U-Boot proper must avoid intermittent CMD18 failures.
        scripts/config --set-val SYS_MMC_MAX_BLK_COUNT 1
        ;;
    check)
        grep -qx 'CONFIG_MMC_SUNXI_SLOT_EXTRA=2' .config
        grep -qx 'CONFIG_SYS_MMC_MAX_BLK_COUNT=1' .config
        grep -qx 'CONFIG_OF_LIBFDT_OVERLAY=y' .config
        grep -qx 'CONFIG_IDENT_STRING=" H728 eMMC v3"' .config
        ;;
    *) echo 'Usage: configure-emmc-uboot.sh [apply|check]' >&2; exit 2 ;;
esac
