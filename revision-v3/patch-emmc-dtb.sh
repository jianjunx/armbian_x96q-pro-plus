#!/bin/bash
# Patch only the eMMC node of the matched 7.2 DTB, retaining its other devices.
# Set H728_DTB_ROLLBACK=1 to skip the patch and keep the stock reference DTB
# verbatim. This produces a binary-test image that disables the eMMC node
# without touching GMAC1, USB, CPU or any other device, isolating whether the
# v3 regression lives in this delta or in the upstream 7.2 reference DTB.
set -euo pipefail
dtb=$1

if [[ "${H728_DTB_ROLLBACK:-0}" == "1" ]]; then
    echo "patch-emmc-dtb: H728_DTB_ROLLBACK=1 set; leaving $dtb unchanged (stock reference)."
    exit 0
fi

node=/soc/mmc@4022000
for pair in 'vmmc-supply reg_cldo3' 'vqmmc-supply reg_cldo1'; do
    read -r property symbol <<<"$pair"
    path=$(fdtget "$dtb" /__symbols__ "$symbol")
    phandle=$(fdtget -t x "$dtb" "$path" phandle)
    fdtput -t x "$dtb" "$node" "$property" "$phandle"
done
fdtput -t s "$dtb" "$node" status okay
fdtput -t i "$dtb" "$node" bus-width 8
# Begin with high-speed SDR rather than untested HS200 timing on this kernel.
fdtput -t i "$dtb" "$node" max-frequency 52000000
fdtput -t i "$dtb" "$node" post-power-on-delay-ms 500
fdtput "$dtb" "$node" non-removable
fdtput "$dtb" "$node" cap-mmc-hw-reset
for property in mmc-ddr-1_8v mmc-hs200-1_8v mmc-hs400-1_8v; do
    if fdtget "$dtb" "$node" "$property" >/dev/null 2>&1; then fdtput -d "$dtb" "$node" "$property"; fi
done
