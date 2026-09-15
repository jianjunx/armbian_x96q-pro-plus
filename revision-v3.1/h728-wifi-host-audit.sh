#!/bin/bash
# Read-only diagnostics: no DTB, register, debug flags or device-state writes.
set -eu
[[ $EUID == 0 ]] || { echo 'Run as root.' >&2; exit 1; }
for cmd in timeout grep cat findmnt modinfo uname; do
    command -v "$cmd" >/dev/null || { echo "Missing: $cmd" >&2; exit 1; }
done
section() { printf '\n=== %s ===\n' "$1"; }
read_file() {
    if [[ -r $1 ]]; then timeout 5 cat "$1" || echo "UNAVAILABLE: $1";
    else echo "MISSING: $1"; fi
}
section 'Kernel and boot media (no UUIDs)'
uname -r
findmnt -nro SOURCE,FSTYPE / /boot || true
section 'MMC1 actual operating mode'
read_file /sys/kernel/debug/mmc1/ios
section 'Relevant dynamic-debug callsites; flags are NOT changed'
control=/sys/kernel/debug/dynamic_debug/control
[[ -r $control ]] || control=/proc/dynamic_debug/control
if [[ -r $control ]]; then
    timeout 5 grep -E 'sunxi_mmc_dump_errinfo|sunxi_mmc_clk_set_phase|sunxi_mmc_clk_set_rate|sunxi_pinctrl_set_io_bias_cfg' "$control" || true
else
    echo 'Dynamic debug control unavailable (debugfs is not mounted by this tool).'
fi
section 'Wi-Fi pin mux and pin configuration (PG0-PG5 only)'
shopt -s nullglob
for file in /sys/kernel/debug/pinctrl/*2000000*/pinmux-pins /sys/kernel/debug/pinctrl/*2000000*/pinconf-pins; do
    echo "--- $file"
    timeout 5 grep -E 'PG[0-5]([^0-9]|$)' "$file" || true
done
section 'MMC and peripheral clock summary'
if [[ -r /sys/kernel/debug/clk/clk_summary ]]; then
    timeout 5 grep -E 'clock|mmc|pll-periph|pll_periph|hosc' /sys/kernel/debug/clk/clk_summary || true
fi
section 'AIC module identity (no module reload)'
for module in aic8800_bsp aic8800_fdrv; do
    timeout 5 modinfo "$module" | grep -E '^(filename|version|srcversion|vermagic|depends):' || true
done
section 'Recent host errors; no SSIDs, IP addresses or MAC addresses requested'
timeout 5 dmesg | grep -E 'sunxi-mmc|smc [0-9]+ err|sdio_err|set power on fail' | tail -100 || true
section 'D-state tasks'
ps -eo pid,stat,comm,wchan:40 | awk 'NR==1 || $2 ~ /^D/'
echo 'AUDIT_COMPLETE. No configuration or hardware state changed.'
