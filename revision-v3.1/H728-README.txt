X96Q Pro+ H728 v3.1 - FULL SD SYSTEM
Debian 13 Trixie / reference Linux 7.2.0-7-MANJARO-ARM

Flash the entire image to SD with write verification. This image defaults to
SD root and does not migrate or overwrite the existing eMMC installation.
Back up your current SD card first: flashing destroys its existing contents.
Boot with Ethernet attached. SSH: root / 1234, then finish first-login setup.
Credentials and files from your existing eMMC are NOT copied into this image.

Corrected eMMC DTB supply; paired Image/modules/DTB; AIC8800D80 firmware;
schedutil with 408 MHz minimum. loglevel=7 aids diagnostics, not a proven fix.
Wi-Fi association, USB device transfers, temperature and repeated cold boots
must be retested. HDMI and deep CPU idle are not fixed. Kernel is a repackaged
reference binary; complete matching source history is not available here.

No automatic eMMC installation. h728-install-emmc only supports --check.
Standalone eMMC boot is unresolved. Do not use an old installer to bypass this.

After Linux starts: h728-diagnostics.txt and h728-logs/<boot-id>/ contain
diagnostics (may contain private network identifiers). Keep them for analysis.
If SD has no Ethernet, switch extlinux/extlinux.conf DEFAULT to stock-dtb AND
armbianEnv.txt fdtfile to allwinner/sun55i-h728-x96qpro+-stock.dtb on a computer.
Do not change root UUID. This disables eMMC in Linux; use only for SD recovery.
No report does not identify where boot failed. UART may still be necessary.
