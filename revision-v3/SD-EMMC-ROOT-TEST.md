# SD kernel / eMMC root experiment v1

Purpose: separate standalone eMMC boot-path failure from inability of the
known-working SD kernel/initramfs/DTB to run the installed eMMC root system.
User authorized this experiment after the first eMMC probe export contained
only INSTALLATION.txt, not a boot marker. Absence of that marker does not
identify the stage of failure.

## Arm from the working SD system

Upload `h728-sd-emmc-root-test.sh` to `/root/` and execute:

```sh
bash /root/h728-sd-emmc-root-test.sh arm
```

Stop on any error. The script requires the known SD root UUID, SD FAT mount,
corrected DTB SHA-256, loglevel-7 baseline, and the existing eMMC root UUID.
It writes only SD boot configuration and backups, not eMMC. Once booted,
the eMMC system will write its normal runtime state and diagnostic evidence.
No raw bootloader, DTB, kernel, partition or eMMC boot-setting changes occur.

The original SD menu entries remain intact. A new entry selects SD Image,
initramfs and corrected DTB with the eMMC root UUID. armbianEnv is changed too
to cover the boot.scr fallback; serial/earlycon are retained and loglevel is 7.
These two file replacements are not atomic as a pair. On an interrupted arm
or error, restore the backed-up pair before rebooting. Never remove backups
to bypass a refusal; report the error. No automatic reboot or rollback occurs.

## Test

After `SD_EMMC_ROOT_TEST_ARMED` is confirmed, run `poweroff`. KEEP THE SD IN,
disconnect power for 30 seconds, reconnect and allow five minutes.
If SSH works, inspect:

```sh
findmnt -no SOURCE,UUID /
findmnt -no SOURCE,UUID /boot
cat /proc/cmdline
```

Expected root UUID: `dd11ca3d-7015-4466-8fba-cb95a97b73ff`.
The installed eMMC fstab mounts eMMC FAT at /boot after Linux starts. Therefore
editing /boot at that point edits eMMC, NOT the SD that loaded the kernel.
Do not attempt SD recovery by blindly editing /boot from the eMMC system.
SSH may show a different DHCP address. Do not bypass a changed SSH host-key
warning without checking the device identity.

## Recovery (computer method works even without SSH)

After a successful boot use `poweroff`; if inaccessible wait five minutes,
then disconnect power before removing the SD. On the computer, open SD FAT:

1. Copy `h728-sd-emmc-root-test-v1-recovery/armbianEnv.txt` over the FAT root
   `armbianEnv.txt`.
2. Copy `h728-sd-emmc-root-test-v1-recovery/extlinux.conf` over
   `extlinux/extlinux.conf`.
3. Safely eject, insert SD in the powered-off box, then power on.

This restores the last working SD-root configuration, not necessarily stock.
Do not confuse these backups with the older stock-DTB experiment backups.
The script also provides `restore`, but deliberately only when already running
the known SD root with SD /boot. It cannot be used from the hybrid eMMC root.

After recovery to SD, retrieve eMMC evidence with the previously uploaded:

```sh
bash /root/h728-emmc-probe1.sh export
```

Use the actual uploaded filename if different. Send the new results archive.
If this test boots eMMC root, it establishes one working SD-assisted path,
not standalone eMMC boot reliability or a specific defective U-Boot component.
If it fails, UART may still be required; do not repeatedly reinstall eMMC.

## Offline validation

Bash syntax, ShellCheck on the switch script, configuration rendering fixtures
and git whitespace checks passed. Fixtures verify the original menu entries
and SD UUIDs survive, the new entry uses eMMC UUID, and earlycon/loglevel remain.
No physical-disk or hardware boot tests have been performed by the agent.
