X96Q Pro+ H728 v3 - Debian 13 Trixie / Linux 7.2.0-7-MANJARO-ARM

Flash the complete image to an SD card (8 GB or larger), connect Ethernet,
then power on. Allow 2 minutes for first boot and check the router DHCP list.
SSH login: root / 1234; complete the first-login password/user setup.
The original v2 image remains the known-booting fallback.

This is an unofficial integration image. Its kernel/DTB/modules come from
junari's linux-sunxi 7.2-7 package. No RC suffix. Debian 13 userspace was
assembled by upgrading a pristine, never-booted copy of the v2 release image
offline; this does not copy any data from the user's running box.
The image uses Tsinghua Debian/Trixie mirrors.

Wi-Fi: AIC8800D80 SDIO firmware is included. Wireless credentials are not
preconfigured; iw, rfkill and wpasupplicant are installed. Ethernet uses DHCP.
CPU: schedutil governor, 408 MHz minimum, original per-cluster maximum limits.
HDMI/display support in this newer reference kernel is not hardware-verified.
Use Ethernet/SSH or UART for the first test.

eMMC: enabled with matched regulators and 8-bit bus, capped at 52 MHz SDR.
HS200/DDR timing is not enabled. The original upstream DTB is also retained
as dtb/allwinner/sun55i-h728-x96qpro+-stock.dtb for diagnosis.

From a working SD boot:
  sudo h728-install-emmc --check
This performs detection, capacity/mount checks and a read-only I/O test.
After backing up Android and testing this kernel:
  sudo h728-install-emmc --install
This requires typing the detected device and CID suffix. It ERASES eMMC
user-area partitions (including Android), tests a new file's write/read,
copies the running SD system, rewrites UUIDs and installs the eMMC-enabled
U-Boot. It does not reboot automatically or modify eMMC boot0/boot1/EXT_CSD.
Standalone eMMC boot and sustained I/O are not yet hardware-tested. Retain SD
for recovery. Stop databases/write-heavy applications before live migration.

After about 60 seconds of userspace operation, h728-diagnostics.txt is saved
on this FAT partition. It includes CPU, frequency/idle state, temperature,
network, SDIO, USB and kernel messages. Read it on a PC if networking fails.
If no report appears, capture UART0 at 3.3V TTL, 115200/8N1.

If the new eMMC node causes an SD boot regression: on this FAT partition,
set DEFAULT stock-dtb in extlinux/extlinux.conf, and set fdtfile in
armbianEnv.txt to allwinner/sun55i-h728-x96qpro+-stock.dtb.

Offline checks are not hardware validation. Do not unhold board kernel/boot
packages or install a generic kernel until a replacement has been validated.
