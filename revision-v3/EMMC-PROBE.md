# eMMC diagnostic probe v1

This is a diagnostic installation, not an image rebuild or boot repair. The
user authorized diagnostic files on the already-installed eMMC on 2026-09-10.
No partition tables, raw bootloader regions, boot0/1, EXT_CSD, DTB, initramfs,
kernel, fstab or boot arguments are changed. The existing SD remains recovery.

The script is deliberately pinned to the three UUIDs observed on this box.
It discovers exactly one MMC-type device (excluding boot0/1), requires the
known SD root, rejects mounted/swap/holder targets, and requests a typed
device/CID token. It validates the offline target read-only first, then mounts
the eMMC ext4 root read-write for installation. That RW mount may replay the
filesystem journal. It does not mount the FAT boot partition for installation.
Existing probe files are never overwritten; failures may leave a partial
installation, so report the error rather than deleting files to bypass guards.

## Install from the currently working SD system

Upload `h728-emmc-probe.sh` to `/root/`, then run:

```sh
bash /root/h728-emmc-probe.sh install
```

Read the displayed device and CID and enter the requested token. Success ends
with `EMMC_PROBE_INSTALLED`. Do not reboot on an error. Send installation output
for review before testing. No network access or package installation is needed.

## Test and recover

After successful installation is confirmed: `poweroff`, disconnect power,
remove SD, wait 30 seconds, reconnect power and allow five minutes. If SSH
works, verify `findmnt /` shows the expected eMMC UUID before claiming success.
If SSH does not work, disconnect power before reinserting the preserved SD.
The SD must use its working eMMC-enabled DTB for exporting eMMC evidence.
Stock DTB can recover SD networking but cannot expose the eMMC partitions.
Do not reinstall the system, and do not select stock DTB for an eMMC root.

From SD, export read-only (ext4 `ro,noload`):

```sh
bash /root/h728-emmc-probe.sh export
```

Download the printed `/root/h728-emmc-evidence.XXXXXX/results.tar.gz` path.
Exports are written on SD, never on eMMC. Logs can contain network identifiers;
share privately and do not commit the raw archive.

## Evidence and limitations

Installed files: `/usr/local/sbin/h728-emmc-probe-v1`, its service/timer below
`/etc/systemd/system/`, two enablement symlinks, and
`/var/lib/h728-emmc-probe-v1/INSTALLATION.txt`. The latter only proves
installation, not boot. New evidence is keyed by kernel boot ID in
`/var/lib/h728-emmc-probe-v1/<boot-id>/`, with an optional FAT mirror at
`/boot/h728-emmc-probe-v1/<boot-id>/`.

The early service runs after root remount and before sysinit completes, with
no network or /boot dependency. It flushes a minimal `started.txt` marker
before running bounded diagnostic commands. A timer requests later snapshots
at 60-second intervals, with at most four snapshots per boot. The early service
itself changes userspace timing; it does not precede initramfs or early kernel
PHY enumeration. Debugfs or network status may be unavailable in the first
snapshot. Root must be writable; absence of evidence does not identify the
failure stage. Abrupt power loss can still lose data despite explicit flushes.

To disable on a running eMMC system after testing (preserves evidence):

```sh
systemctl disable --now h728-emmc-probe-v1.timer
unlink /etc/systemd/system/sysinit.target.wants/h728-emmc-probe-v1.service
systemctl daemon-reload
```

Offline validation: Bash syntax and ShellCheck passed. No installation or
destructive storage commands were executed by the agent on physical hardware.
Runtime collection and the custom early service still require this test.

Dependency-check correction: the first installer used `test -x` on the
read-only `noexec` audit mount, falsely reporting `usr/bin/timeout` missing.
Reproduced locally with a mode-0755 binary on a noexec tmpfs. The corrected
check inspects file presence, readability, size and executable mode bits
without executing it. This specific failure occurs before the RW mount and
before any probe files are installed, so replacing the uploaded script and
retrying is safe; do not generalize that to failures after installation starts.
