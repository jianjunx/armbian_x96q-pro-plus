# v3.1 Wi-Fi bring-up, 2026-09-10

## Latest evidence and next experiment (2026-09-13)

40 MHz / 4-bit / 20 mA hardware test failed initialization with CMD53 RD DCE
and no wlan0. Stop clock/drive sweeps. Binary audit now establishes that the
reference pinctrl code lacks the upstream A523 inverted-withstand encoding
fix. This is not yet a proven Wi-Fi root cause. Details and reproducibility
caveats: [WIFI-KERNEL-AUDIT.md](WIFI-KERNEL-AUDIT.md).

20 mA follow-up: user confirmed three cold boots at 24 MHz / 4-bit / 20 mA.
300-second TCP tests completed: receive 23.8 Mbit/s, send 31.9 Mbit/s with 32
TCP retransmissions. Supplied error filter was empty. Link was 5 GHz, signal
-68 dBm, power saving off; Windows server used Ethernet. Do not attribute
throughput change solely to drive strength or claim fleet/long-term stability.

Next user-requested experiment: `h728-wifi-clock40-drive20-v1-test.sh` accepts
only the 4898a7ab... 24 MHz / 4-bit / 20 mA DTB and changes max-frequency to
40 MHz. Keeps drive strength, firmware, kernel, bootargs and all other nodes.
Requires SD root/boot and wired carrier. Never use the earlier 40 mA clock40
script for this state. arm creates FAT h728-wifi-clock40-drive20-v1-recovery;
restore returns to 24 MHz / 4-bit / 20 mA, not 40 mA or 1-bit. Computer recovery
copies original.dtb from that directory to dtb/allwinner/sun55i-h728-x96qpro+.dtb.
Candidate SHA-256:
869ac9994d209f25bc5978aea573ae95d08e546840b5c7dbe6e4572382a99094.
ShellCheck, syntax, 40M/4-bit/20mA readback, inverse-edit byte equality and
wrong-input/existing-output rejection passed offline. Hardware result pending;
not incorporated into image assembly or a Release. After cold boot check actual
clock, interface and CRC logs before throughput; compare at the same location.

Targeted error capture now confirms 24 MHz requested / 22222222 Hz actual,
4-bit, debug callsite enabled, and `smc 1 err, cmd 53, WR DCE` at fmac firmware
upload. DCE denotes the host DATA_CRC_ERROR flag, WR the write direction.
Upstream sunxi-mmc maps host error flags to -ETIMEDOUT, so -110 alone was not
proof of a pure timeout. Root cause (signal integrity, timing, I/O threshold,
controller behavior) is not established. Early CMD8/CMD55 response timeouts
during device-type probing must not be conflated with this CMD53 failure.

`h728-wifi-drive20-v1-test.sh` prepares the next single-property experiment:
keep 24 MHz / 4-bit and change PG0-PG5 mmc1-pins drive-strength 40 -> 20 mA.
No supply voltage, reset, kernel, firmware, bootargs or eMMC change. This tests
drive sensitivity; 40 mA is not proven incorrect. It accepts only baseline
5e4c838516b43e7667a583859b671cf5eb00316674eb950d0eb5bb67b2502bc7,
requires SD root/boot and wired carrier, and backs up the DTB before arming.
Candidate hash: 4898a7abe86e08c533ace788604a90ce58401dd2fc63ae42a31a5e8249c7e357.
ShellCheck, syntax, readback, inverse-property byte equality and rejection of
wrong input/existing output passed offline. No hardware success claimed.
Run arm, cold boot, inspect PG0-PG5 pinconf, MMC1 ios and WR DCE logs first;
do not start another throughput run unless initialization succeeds. Restore
returns to 24 MHz / 4-bit / 40 mA (the failing diagnostic baseline), not the
1-bit working control. Computer recovery copies original.dtb from FAT
h728-wifi-drive20-v1-recovery to dtb/allwinner/sun55i-h728-x96qpro+.dtb.

Follow-up: 12 MHz / 1-bit passed three user-reported cold boots and 300 s TCP
each direction (9.56 Mbit/s receive, 10.6 Mbit/s send, zero send retransmits).
The supplied post-test error filter was empty. User explicitly rejects this
throughput as a final solution. Keep it only as a diagnostic control; do not
ship/adopt it or continue a 1-bit speed sweep. High-throughput 4-bit operation
is unresolved. This does not prove broken DAT1-DAT3 wiring.

Read-only source/binary audit found CONFIG_MMC_SUNXI=y and
CONFIG_DYNAMIC_DEBUG=y in the matched config, plus sunxi_mmc_dump_errinfo
and its `smc %d err, cmd ...` format in the reference Image. The host driver
is built in: swapping an AIC module cannot replace its timing/error handling.
The newer warpme AIC patch still calls sdio_writesb and sdio_release_irq;
these callsites alone do not establish a fix in that version. Generic upstream
sunxi-mmc skips old clk_set_phase delay tables in new-timing mode, so merely
adding old-style sample/output phase properties is not justified. Matching
binary implementation and actual error status still need verification.

`h728-wifi-host-audit.sh` reads the current dynamic-debug callsites, MMC1 ios,
PG0-PG5 pin state, clock summary, module identities and host-error lines. It
does not mount debugfs, enable logging, reload modules, access /dev/mem,
change DTB or touch eMMC. Run while preserving the current control state;
no throughput test is requested. Review diagnostics before sharing publicly.
The next targeted failure-capture must be based on the callsites actually
available, not a speculative register write or broad MMC IRQ logging which
would also flood SD/eMMC I/O and alter timing.

This update supersedes earlier clock-stability claims below. Fresh SD and
standalone eMMC both failed AIC firmware upload. The user confirmed full
power removal; these failures must not be dismissed as warm-reboot artifacts.
12 MHz / 4-bit succeeded once on SD, then failed on a subsequent cold boot.
The blocked worker stack is in sdio_release_irq -> mmc_wait_for_req_done during
error cleanup, after a firmware upload data error. Fixing cleanup alone would
not establish successful firmware transfer. Supplied firmware hashes match the
pinned bundle; this proves integrity, not compatibility. No raw logs retained.

The upstream board patch already matches our PM1 active-low reset, 200 ms
post-power-on delay and 40 mA pin drive. Its 15 MHz cap is not proof that
another clock sweep will fix this unit. Matching Manjaro 7.2 source retrieval
still timed out. A523 pinctrl/clock fixes remain candidates to audit, not
confirmed missing patches. Do not substitute an unrelated kernel module or
modify regulator voltages/registers on that assumption.

Next isolated experiment: `h728-wifi-width1-v1-test.sh` changes ONLY mmc1
bus-width from 4 to 1, keeping 12 MHz, all supplies/reset settings and the
matched kernel/modules/firmware. This tests sensitivity to bus width, not a
proven electrical diagnosis or a shipping performance setting. Generic Linux
SDIO core negotiates wide mode only when the host advertises 4-bit capability;
verify actual width after boot because this binary/vendor driver may differ.

Input SHA-256 (12 MHz / 4-bit):
`7731eeb13cd90ba405da0b20bb89a979d6b3cf7c478de28d50524055b18b4614`.
Candidate SHA-256 (12 MHz / 1-bit):
`64cc67a31254e9aaa921deb0d66499e55e122043c1beb81e030ea27d08deff81`.
ShellCheck, bash syntax, readback, byte-identical inverse patch and rejection
of wrong input/existing output passed offline. Hardware result is pending.

Copy the script to /root on the box. With root and /boot on the same SD and
Ethernet connected, run `bash /root/h728-wifi-width1-v1-test.sh arm`.
It refuses other DTBs and eMMC roots, backs up before replacement, and never
reboots or reloads a driver. After WIFI_WIDTH1_ARMED, shut down cleanly,
disconnect power for 30 seconds, then cold boot with SD and Ethernet attached.
Collect mmc1 ios, ip -br link, D-state tasks and filtered AIC/MMC dmesg. Expected
ios is 12000000 Hz and `bus width: 0 (1 bits)`; if still 4-bit the experiment
has not taken effect. A wlan0 alone is not success: require scanning,
association, repeated cold boots and transfer without errors before adoption.

Rollback via wired SSH: `bash /root/h728-wifi-width1-v1-test.sh restore`, then
cold boot. This restores the preceding 12 MHz / 4-bit diagnostic baseline,
NOT a known-stable Wi-Fi state. Computer recovery: copy FAT
`h728-wifi-width1-v1-recovery/original.dtb` to
`dtb/allwinner/sun55i-h728-x96qpro+.dtb`. Keep recovery files. Do not force
module removal or unbind the MMC host when a worker is stuck in D state.
This experiment is not included in image assembly or a Release.

Sources:
- https://forum.manjaro.org/t/allwinner-h728-a523-a527-t527-initial-support-thread/173654
- https://github.com/warpme/minimyth2/blob/8d68d845fb304c9296b28ab26ba5faa4e7c72a11/script/kernel/linux-7.2/files/2900-arm64-dts-allwinner-h728-x96q-pro-plus-improvements.patch
- https://github.com/warpme/minimyth2/blob/8d68d845fb304c9296b28ab26ba5faa4e7c72a11/script/kernel/linux-7.2/files/2706-pinctrl-sunxi-A523-fix-voltage-withstand-encoding.patch
- https://github.com/torvalds/linux/blob/master/drivers/mmc/core/sdio.c

## Historical clock experiments

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
