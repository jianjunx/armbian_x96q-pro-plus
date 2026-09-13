#!/bin/bash
# Run manually on the box over wired SSH. No mount, reload or reboot.
set -u
echo '=== Running system ==='
uname -r
findmnt -no SOURCE,UUID /
findmnt -no SOURCE,UUID /boot
echo '=== Running SDIO clock ==='
if [[ -r /sys/kernel/debug/mmc1/ios ]]; then
    cat /sys/kernel/debug/mmc1/ios
else
    echo 'debugfs MMC information unavailable; nothing mounted automatically.'
fi
echo '=== Packaged boot DTB (may differ from running DT) ==='
dtb=/boot/dtb/allwinner/sun55i-h728-x96qpro+.dtb
if [[ -f $dtb ]]; then
    sha256sum "$dtb"
    if command -v fdtget >/dev/null; then
        fdtget "$dtb" /soc/mmc@4021000 max-frequency
    fi
fi
echo '=== Running DT Wi-Fi max-frequency (big endian bytes) ==='
prop=/proc/device-tree/soc/mmc@4021000/max-frequency
if [[ -r $prop ]]; then od -An -tx1 "$prop"; fi
echo 'Expected 24 MHz DT bytes: 01 6e 36 00; bus clock may be 22222222.'
echo '=== Wireless initialization errors ==='
dmesg | grep -Ei 'aic|4021000|mmc1|sdio' | tail -80
echo '=== Wireless interface ==='
if command -v iw >/dev/null; then iw dev; fi
echo 'No settings changed. Redact MAC/SSID/UUID fields before public sharing.'
