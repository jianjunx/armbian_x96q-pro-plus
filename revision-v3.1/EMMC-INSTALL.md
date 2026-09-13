# v3.1.3 eMMC installation candidate

This is experimental, not a general hardware-support certification. A patched
box booted independently from eMMC; this new installation workflow still needs
the owner's complete end-to-end hardware test. Keep a known-working SD card.

1. Flash the **v3.1.3** full image to SD and verify the write. Boot with Ethernet.
2. Complete first-login setup. Check Wi-Fi/USB, then stop containers, databases
   and other write-heavy workloads. This copies the live SD system, including
   its current users/passwords/SSH keys, not an application-consistent snapshot.
3. Run `sudo h728-install-emmc --check`. Root **and** /boot must be on the same
   separate SD. Mounted eMMC partitions, swap and holders are rejected.
4. Recommended backup mode (USB filesystem with >eMMC capacity + 1 GiB free):
   `sudo h728-install-emmc --install --backup-dir /mnt/usb`.
   This creates a private full user-area image, checks it against a second
   read, then proceeds. boot0/boot1 and EXT_CSD are not backed up or modified.
5. If intentionally discarding ALL existing eMMC data, explicitly use
   `sudo h728-install-emmc --install --no-backup`.
   Type the exact **NO BACKUP ERASE /dev/mmcblkN CID-suffix** printed by the
   tool. There is no automatic rollback; do not copy a device name from docs.
6. Only after INSTALL COMPLETE: `sudo poweroff`, remove SD, power on, collect
   UART and verify `findmnt /`, `findmnt /boot`, Ethernet and Wi-Fi. On failure
   retain the SD and full error output; do not repeatedly erase/reflash.

The tool checks the matched 24 MHz Linux DTB, bootloader manifest/config/DTB,
image size, device CID/type/capacity and source filesystem before wiping.
The new layout is DOS, FAT starts at 4 MiB, root follows the 512 MiB FAT.
SPL is written at 8 KiB only after copying and checking boot-critical files
and rewriting root/boot UUIDs. It verifies bootloader bytes and filesystem
integrity. These checks do not establish long-term hardware reliability.

## Before public release

- At least three SD-removed cold boots and warm reboots from the fresh install;
  confirm root AND /boot on eMMC. Record build hash and board revision.
- Ethernet/SSH, Wi-Fi association and sustained bidirectional transfer; USB2/3
  with actual peripherals and negotiated speeds.
- Sustained eMMC file writes with fsync, hash read-back, clean cold boot and
  hash recheck; no MMC errors. Never pull power during writes as a routine test.
- Publish only the clean CI-built SD image, **not a dump of the installed box**.
  No personal credentials, network profiles, host keys or raw diagnostic logs.
- Keep experimental/prerelease labelling until these results exist; one board
  does not establish compatibility with all X96Q Pro+ hardware revisions.
- Kernel remains reference-binary based; AIC firmware redistribution permission
  remains unresolved. Verify redistribution rights before offering it publicly.
