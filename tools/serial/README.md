# UART tools: safety status

The old `h728_flash_emmc_uboot.py` and `h728_emmc_one_pass.py` are disabled.
Both exit with status 2 **before opening a serial port**, including when passed
their old arguments or H728_QUICK=1. Successful one-off hardware use did not
make their unchecked device selection and write extent safe for reuse.

Use PuTTY logging or `h728_serial_capture.py` for capture, and
`h728_serial_shell.py` for read-only Linux diagnostics. The latter asks for the
password interactively; it does not store it. A password was present in older
Git commits: change that password on the device (and anywhere it was reused).
Deleting it from the current tree does not revoke it or erase Git history.

Do not run the historical flashing commands in archived logs/post-mortems.
A replacement writer must verify board identity, eMMC CID and user hardware
partition, actual first-partition boundary, image hash/header, verified backup,
typed target/CID consent, reselected target, and exact write/read-back counts.
Failure after a write must report possible modification, never “nothing written”.
Keep v3.1's installer disabled until this separately reviewed workflow exists.

The current successful eMMC boot log still has Wi-Fi firmware upload errors.
The SD v3.1.1 clock fix has not thereby been proved installed on eMMC. Collect
`cat /sys/kernel/debug/mmc1/ios`, `iw dev`, and the current DTB hash over wired
SSH before any on-device change. Preserve the working eMMC and recovery SD.

For that check, copy `h728-emmc-wifi-check.sh` to the box and run it with bash
over wired SSH. It only reads; it neither mounts debugfs nor changes the DTB.
