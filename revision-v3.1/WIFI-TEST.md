# v3.1 Wi-Fi bring-up, 2026-09-10

Latest experiment: 40 MHz was actually achieved (debugfs ios), but firmware
transfer again failed with SDIO data errors / -110 and no wlan0. The user
requested direct 40 -> 24 MHz testing, with 20 MHz recovery if it fails.
`h728-wifi-clock24-test.sh arm` requires the pinned 40 MHz candidate and wired
carrier; it installs 24 MHz directly without an intermediate 20 MHz boot.
`restore` returns to the verified 20 MHz DTB, not the failed 40 MHz setting.
It preserves previous40.dtb for evidence and clock20.dtb for recovery under
FAT h728-wifi-clock24-v1-recovery. Computer recovery copies clock20.dtb to
dtb/allwinner/sun55i-h728-x96qpro+.dtb. Cold boot after either action.
24 MHz subsequently passed three user-confirmed cold boots and TCP transfer
for 300 seconds per direction: download 64.3 Mbit/s, upload 66.0 Mbit/s with
zero upload retransmissions. Observed actual clock was 22222222 Hz. A later
boot log contained no SDIO transfer errors; it was a different boot from the
initial test log and cannot establish the earlier boot's complete log state.
v3.1.1 now adopts this clock ceiling, retaining a 20 MHz fallback DTB. The new
image itself still requires hardware retesting. Signal strength/AP association
varied between tests, so throughput differences are not controlled clock-only
measurements.

Update: user tested the 12 MHz candidate. Live MMC ios confirms 12 MHz / 4-bit;
patch and fmac firmware uploads completed far enough to create wlan0 (DOWN).
The supplied filtered boot log no longer shows the prior transfer timeout.
5 GHz association, DHCP and a 94-packet gateway test completed with zero loss;
three subsequent power-disconnected cold boots also succeeded. This supports
clock-sensitive initialization, not a proven electrical root cause. Sustained
transfer is still pending.

2026-09-12 update: 20 MHz also passed three user-reported cold boots, 5 GHz
association and DHCP. Interface-bound TCP iperf3 completed 300 seconds per
direction: download 58.5 Mbit/s (2.04 GiB), upload 60.0 Mbit/s (2.10 GiB,
four retransmissions). Download retransmission count was not reported.
Filtered logs showed no SDIO transfer timeout, but two station debug-entry
registration/unregistration errors remain unexplained. This is the current
tested baseline for this unit, not proof of universal board compatibility.

The user requested a next experiment above 25 MHz, skipping 24 MHz.
`h728-wifi-clock40-test.sh arm` accepts only the byte-verified 20 MHz candidate
and requires Ethernet carrier. It changes only mmc1 max-frequency to 40 MHz.
The reference already enables SD high-speed; no UHS/DDR, regulator, reset,
bus-width or pin-drive changes are introduced. The later 40 MHz test failed
as recorded above.
Read `actual clock` after boot, then test association, three cold boots and
300 seconds of interface-bound TCP in each direction before adoption.

Upload the script to /root, connect Ethernet, run `bash
/root/h728-wifi-clock40-test.sh arm`. After WIFI_CLOCK40_ARMED, power off,
disconnect power for 30 seconds and cold boot. On failure, via wired SSH run
`bash /root/h728-wifi-clock40-test.sh restore`, then cold boot again. Restore
returns to 20 MHz. Computer recovery: copy FAT
`h728-wifi-clock40-v1-recovery/clock20.dtb` over
`dtb/allwinner/sun55i-h728-x96qpro+.dtb`. Recovery files are retained.
This experiment is not included in default image assembly.

Initial 25 MHz hardware feedback confirmed SD boot and Ethernet, but no Wi-Fi.
The AIC8800 SDIO functions enumerate; firmware files are read. Upload of the
D80 U02 patch fails with MMC data errors and -110 (timeout). One boot stalled
in sdio_release_irq during cleanup; another completed cleanup with
`rwnx_mod_init, set power on fail`. No wireless interface appears.
Do not unload/reload the failed driver repeatedly or infer a password problem.
Raw diagnostics contain private network/login metadata and are not committed.

The matched reference DTB already specifies 25 MHz, 4-bit SDIO, a 200 ms
post-power-on delay, and vcc3v3 main supply. Live debugfs confirms 25 MHz.
Missing vqmmc metadata / a reported 3.3 V signal setting does not establish
the physical I/O voltage. Do not change regulator voltages speculatively.
The original author reported working AIC Wi-Fi with their firmware package:
https://forum.manjaro.org/t/allwinner-h728-a523-a527-t527-initial-support-thread/173654
This does not establish compatibility on every board/kernel revision.

## First controlled experiment: 12 MHz

`h728-wifi-sdio-test.sh` modifies only mmc1 max-frequency, from 25 to 12 MHz.
It retains Image/modules/firmware, bus width, reset, regulator properties,
Ethernet, SD and eMMC nodes. A round-trip property edit must reproduce the
baseline DTB byte-for-byte. This tests clock-related transfer sensitivity;
it is NOT a proven fix or evidence that the clock is the root cause.
Not included in default image assembly pending hardware results.

Copy the script to `/root/` on the box using existing wired SSH. Back up the
working SD before testing. With both root and boot on the same SD, run:

```sh
bash /root/h728-wifi-sdio-test.sh arm
```

Only proceed after `WIFI_CLOCK12_ARMED`. Run `sync; poweroff`, wait for shutdown,
disconnect power for 30 seconds, and reconnect with SD and Ethernet attached.
No automatic reboot, driver reload, eMMC mount or eMMC write is performed.

Collect after boot:

```sh
cat /sys/kernel/debug/mmc1/ios
ip -br link
command -v iw >/dev/null && iw dev
dmesg | grep -Ei 'aic|4021000|mmc1|sdio|blocked for more' | tail -100
```

An interface alone is not success: next verify scan, association and sustained
transfer. If unchanged, restore before the next isolated experiment:

```sh
bash /root/h728-wifi-sdio-test.sh restore
```

Then cold-boot again. If SSH fails, power off, insert SD into a computer, copy
FAT `h728-wifi-clock12-v1-recovery/original.dtb` over
`dtb/allwinner/sun55i-h728-x96qpro+.dtb`. No boot configuration restoration needed.
Keep the recovery directory; repeated arm refuses to overwrite that backup.

Offline checks: ShellCheck, bash syntax, candidate 12 MHz readback, byte-identical
round trip, refusal of a mismatched input / existing output. These are not
hardware validation. No physical device is accessible from the build host.

## 2026-09-13: v3 on eMMC, and why `reboot` is the wrong instrument

The v3 image (not v3.1) ships the reference 25 MHz SDIO clock, so Wi-Fi was
dead on the box after installing to eMMC. `mmc1: new high speed SDIO card at
address 390b` enumerates fine and every firmware file is read, but
`aicwf_sdio_tx_msg` returns -110 while uploading `fmacfw_8800d80_u02.bin`,
`aicbsp_dummy_sdmmc` probe of function 1 and 2 fails with -110, and
`rwnx_mod_init, set power on fail!` leaves no wlan0.

Clock sweep on that unit, all by `reboot`:

| SDIO clock | wlan0 |
|---|---|
| 25 MHz (reference) | NO, NO |
| 24 MHz | YES once, then NO, NO |
| 20 MHz | NO, NO |
| 12.5 MHz | YES |

**Do not read that table as a clock result.** Every success recorded earlier in
this file required `sync; poweroff` and **30 seconds with power disconnected**.
`reboot` never removes vcc3v3 from the AIC chip, so the chip is not hard
reset between attempts and can stay in the state that failed. Warm reboots
therefore cannot measure cold-boot reliability in either direction: they can
fail a good clock and, as the single 12.5 MHz pass shows, occasionally pass
despite a bad state. Only a power-disconnected cold boot counts.

What was actually changed on the box, pending cold-boot confirmation:
`/boot/dtb/allwinner/sun55i-h728-x96qpro+.dtb` -> `/soc/mmc@4021000
max-frequency = 24000000`, the value v3.1.1 already adopted and that passed
three cold boots plus 300 s TCP per direction. The pre-change DTB (25 MHz) is
kept at `/root/dtb-backup-20260913.dtb`.

To make cold boots auditable without watching the console,
`/root/h728-wifi-bootcheck.sh` is installed and enabled as
`h728-wifi-bootcheck.service`. Each boot appends to `/root/wifi-boot-log.txt`:
the DTB clock, whether wlan0 exists and its MAC, `set power on fail` count,
`sdio_err` count, and the live `mmc1` clock. Cold boot three times, then read
that file.

Note this unit's eMMC boot uses the v4 bootloader blob, so the boot path
differs from the SD-boot tests above; that is a second variable, not
controlled for here.
