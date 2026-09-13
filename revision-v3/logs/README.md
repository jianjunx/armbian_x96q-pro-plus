# Serial logs — H728 eMMC boot, 2026-09-13

Evidence behind [`../eMMC-BOOT-POSTMORTEM.md`](../eMMC-BOOT-POSTMORTEM.md).
All three were captured over a USB-TTL adapter on COM3 at 115200 8N1, with the
SD card **removed** unless the file says otherwise.

| File | What it is | Why it matters |
|---|---|---|
| `2026-09-13-emmc-coldboot-VERIFIED.txt` | Final cold boot with the shipping blob (`Sep 13 2026 - 07:09:12`), SPL → U-Boot proper → extlinux → kernel → `login:` | The proof that standalone eMMC boot works |
| `2026-09-13-spl-instrumented-coldboot.txt` | Cold boot of the instrumented debug blob (`Sep 13 2026 - 06:48:37`); per-block `H728DBG` output collapsed into a histogram, transcript kept verbatim | The evidence that pinned down faults 1 and 2 |
| `2026-09-13-uboot-cli-diagnosis.txt` | U-Boot CLI session while SD-booted: `mmc info`, partition table, multi-block read sweep, `printenv` | Shows U-Boot proper reads the eMMC fine and that `boot_targets` lacks `mmc1` |

## What to look for

**In the instrumented log** — this is the run that ended the guessing:

```
## Instrumented line histogram
  38848 HNDBG cmd=N blks=N bs=N bc=N
  38759 HNDBG pio words=N tmo=N
     20 HNDBG bread fail start=N cur=N
     19 HNDBG bread recovered
     18 HNDBG ios bw=N clk=N

## boot outcome counters
bread fail                   20
bread recovered              19
single fail                   0
ios bw=1 clk=26000000        3
mmc block read error         0
```

Read it as: the timing fix **had** taken effect (`ios bw=1 clk=26000000`), multi-block
reads failed 20 times, the block-by-block fallback rescued 19 of them, and a
single-block read never failed once. That is what justified `b_max = 1`.

**In the CLI diagnosis** — `mmc info` reports `Mode: MMC High Speed (26MHz)` and the
read sweep succeeds at 1/2/8/16/64/128/512/1490 blocks, i.e. U-Boot proper is fine
with the eMMC while the SPL is not. `printenv` gives
`boot_targets=fel mmc0 usb0 pxe dhcp` — no `mmc1` — which is fault 3.

## Reproducing

**Safety update:** the flashing and one-pass commands below are historical
and now refuse to run before opening a port. Use capture/read-only diagnostics
only; see `../../tools/serial/README.md`. A successful eMMC boot in the final
log does not imply Wi-Fi success: it also records AIC firmware upload failure.

The scripts in [`../../tools/serial`](../../tools/serial) produced these logs
(pyserial; run with the managed venv python):

```bash
# capture a cold boot: power the board during the window
python tools/serial/h728_serial_capture.py COM3 300

# log in on the console and run diagnostics
python tools/serial/h728_serial_shell.py COM3

# one hang: diagnose while SD-booted, flash, then capture the cold boot
H728_QUICK=1 python tools/serial/h728_emmc_one_pass.py COM3 u-boot-sunxi-with-spl-emmc.bin 420

# flash only (interrupts autoboot, writes at sector 16, reads back with cmp.b)
python tools/serial/h728_flash_emmc_uboot.py COM3
```

A full instrumented run is 2.6 MB of mostly repeated per-block lines; keeping the
histogram plus the verbatim transcript is what makes it reviewable.
