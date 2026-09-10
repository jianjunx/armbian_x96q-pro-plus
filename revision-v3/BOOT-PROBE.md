# SD boot probe v1 (2026-09-10)

Purpose: collect the running DT, regulator summary and kernel log when enabling
eMMC makes Ethernet unavailable. This is not an image or an eMMC boot fix.
Only run on the physical X96Q Pro+ booted from SD with the v3 kernel.
The script checks that `/` and the exact FAT `/boot` mount belong to the same SD.
It does not mount eMMC, install a bootloader, change voltages or reboot.
Kernel probing of enabled hardware still occurs during the experiment.

## Procedure

1. Transfer `h728-boot-probe.sh` to `/root/` while stock DTB networking works.
2. Run `sudo bash /root/h728-boot-probe.sh install`. It installs a systemd timer
   and collector on SD and takes a baseline, without changing boot settings.
   Stop on any error. Confirm a nonempty `snapshot-1.txt` and `running.dts`
   exist below `/boot/h728-boot-probe-v1/<boot-id>/`.
3. Run `sudo bash /root/h728-boot-probe.sh arm`. It requires the inspected DTB
   hashes, stock menu default, a baseline snapshot and current loglevel 7.
   It backs up BOTH boot settings to `/boot/h728-boot-probe-v1/recovery/`,
   then selects the corrected eMMC DTB and loglevel 7 in extlinux and the
   armbianEnv fallback. It never changes the DTB files or root UUIDs.
4. If and only if arm succeeds, run `sudo poweroff`. Keep SD inserted, remove
   power for 30 seconds and reconnect. Allow five minutes for snapshots.
   Keep Ethernet, power supply and peripherals the same as the baseline.
5. If SSH works, run `sudo /usr/local/sbin/h728-boot-probe-v1 restore` before
   shutting down. Otherwise power off after the waiting period and use the
   computer recovery below. Do not remove SD while powered.
6. Send the entire `h728-boot-probe-v1` directory, including both boot IDs.
   Logs contain network identifiers; share privately, never commit raw logs.

## Recovery using a computer

On the SD FAT partition (shown WITHOUT the Linux `/boot` prefix):

- Copy `h728-boot-probe-v1/recovery/armbianEnv.txt` over `armbianEnv.txt`.
- Copy `h728-boot-probe-v1/recovery/extlinux.conf` over `extlinux/extlinux.conf`.

If backups are unavailable, restore `DEFAULT stock-dtb` in extlinux and
`fdtfile=allwinner/sun55i-h728-x96qpro+-stock.dtb` in armbianEnv. Keep UUIDs.
Safely eject before reinserting in the powered-off box. Recovery is manual,
not guaranteed automatic rollback. A hard power-off may lose buffered data;
the collector flushes each completed snapshot but cannot prevent all loss.

## Collector scope and limitations

The timer requests capture at 30 seconds after boot and then every 60 seconds,
without network-online dependencies. Actual execution depends on systemd and
the SD boot mount being available. Maximum three snapshots per boot, protected
against concurrent execution. Each optional command has a timeout; missing
debugfs is recorded rather than mounted. Evidence uses random kernel boot ID,
not the potentially inaccurate system clock. Captures stop below 16 MiB free.
No snapshots can be made if Linux never reaches userspace or `/boot` fails.
Absence of snapshots alone does not identify the failing boot stage.

After testing, stop collection with:

```sh
sudo systemctl disable --now h728-boot-probe-v1.timer
```

Keep evidence and recovery backups. This v1 intentionally refuses to overwrite
an existing installation or recovery directory. It is for one experiment;
do not delete backups simply to bypass those checks.

Offline validation: shell syntax and ShellCheck; no physical-box test yet.
