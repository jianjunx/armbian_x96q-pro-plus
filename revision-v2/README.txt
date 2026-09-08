X96Q Pro+ / Allwinner H728 - Armbian Bookworm SD image v2

The previous 6.18 image had GMAC1 disabled and no active USB3/CPU OPP setup
in its board DTB. This version uses junari's matched linux-sunxi 6.17-2
Image + modules + X96Q Pro+ DTB. Actual kernel: 6.17.0-rc1-2-MANJARO-ARM+.
This is an experimental hardware compatibility image, not a current stable
or security-maintained kernel. Physical hardware testing is still required.

HDMI output is unsupported. A black screen alone does not mean boot failed.
Connect Ethernet to a DHCP router, then insert SD with power disconnected.
Power on and wait 2 minutes; look for x96q-pro-plus in the DHCP leases.
Use the IP address for SSH. The original Armbian first-login setup remains.

CPU: 8 Cortex-A55 cores, two frequency domains, reference voltage/OPP tables.
Ethernet: enabled GMAC1, RGMII PHY address 1, reset and power configuration.
USB: enabled USB2 hosts and DWC3 USB3 + matched SUN55I combo PHY driver.
USB3 powering a spinning disk may be limited by board power hardware.

After 60 seconds, a report is saved to h728-diagnostics.txt on this FAT
partition and refreshed every 3 minutes. Read it on a PC after powering off
the box if networking is unavailable. It contains CPU online/frequency data,
Ethernet link/address/driver, USB topology, temperature and kernel messages.
You can run sudo /usr/local/sbin/h728-diagnostics over SSH at any time.
If the report never appears, capture 3.3V UART0 at 115200 baud, 8N1.

The kernel/boot packages are held to avoid replacing this board-specific
combination through a generic update. Debian APT uses Tsinghua mirrors.
Flash the complete .img to SD, not the extracted partition files.
The image build never writes to box eMMC or to any physical SD device.
