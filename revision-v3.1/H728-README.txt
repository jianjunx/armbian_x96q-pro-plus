X96Q Pro+ H728 v3.1.3 - EXPERIMENTAL FULL SD / eMMC INSTALL CANDIDATE
Debian 13 Trixie / reference Linux 7.2.0-7-MANJARO-ARM

Flash the entire image to SD with write verification. This image defaults to
SD root and does not migrate or overwrite the existing eMMC installation.
Back up your current SD card first: flashing destroys its existing contents.
Boot with Ethernet attached. SSH: root / 1234, then finish first-login setup.
Credentials and files from your existing eMMC are NOT copied into this image.

Corrected eMMC DTB supply; paired Image/modules/DTB; AIC8800D80 firmware;
kernel package +h728.7 includes Wi-Fi SDIO max-frequency=24000000.
Observed actual clock is 22222222 Hz. On the user's box this configuration
passed three cold boots and 5 minutes per TCP direction (64.3/66.0 Mbit/s).
This newly assembled image still requires hardware retesting.
Wi-Fi credentials are not included. Configure wlan0 with Netplan/networkd;
NetworkManager/nmcli is not installed. Do not publish Wi-Fi passwords or use
one shared fixed MAC address across multiple devices.
Wi-Fi recovery: use dtb/allwinner/sun55i-h728-x96qpro+-wifi20.dtb (20 MHz)
in BOTH armbianEnv.txt fdtfile and the active extlinux.conf FDT entry, then
cold boot. Keep root UUIDs unchanged. Restore the normal DTB path to undo.
schedutil with 408 MHz minimum. loglevel=7 aids diagnostics, not a proven fix.
Wi-Fi association, USB device transfers, temperature and repeated cold boots
must be retested. HDMI and deep CPU idle are not fixed. Kernel is a repackaged
reference binary; complete matching source history is not available here.

No automatic eMMC installation. First run: sudo h728-install-emmc --check
Full wipe without backup (irreversible):
  sudo h728-install-emmc --install --no-backup
Type the exact device/CID confirmation printed by the tool. ALL eMMC user-area
data is erased. Alternatively use --install --backup-dir /mnt/usb for a verified
full backup on an external USB disk. Both root and /boot must be on SD.
Wait for INSTALL COMPLETE, poweroff, remove SD, cold boot and test.
Standalone eMMC boot was observed on the patched box, not this new image.
A newly built eMMC U-Boot (1-bit/26 MHz, single-block reads) is stored under
/usr/lib/h728/uboot with config, DTB and source/recipe hashes. Merely booting
this SD image does not install it. Do not use old UART writers or installers.
This new installation workflow still needs end-to-end hardware validation.

After Linux starts: h728-diagnostics.txt and h728-logs/<boot-id>/ contain
diagnostics (may contain private network identifiers). Keep them for analysis.
If SD has no Ethernet, switch extlinux/extlinux.conf DEFAULT to stock-dtb AND
armbianEnv.txt fdtfile to allwinner/sun55i-h728-x96qpro+-stock.dtb on a computer.
Do not change root UUID. This disables eMMC in Linux; use only for SD recovery.
No report does not identify where boot failed. UART may still be necessary.
