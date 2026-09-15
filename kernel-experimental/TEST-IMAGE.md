# H728 v3.2.0-test1 — independent SD test image

This is NOT a production release. Do not install it to eMMC or redistribute it
as a hardware-validated image. Write it to a separate SD card and preserve the
working eMMC system/recovery media. Initial SSH: root / 1234; change at first login.

Linux 7.2.0-h728-test1 is compiled from verified Linux 7.2 source plus the pinned
iuncuim 6.19-era driver patches, local Linux 7.2 AIC API adaptations and Andre
Przywara's A523 pinctrl withstand-encoding fix. This is a new source port, NOT
an exact reproduction of the reference 7.2.0-7-MANJARO-ARM binary.

Wi-Fi test control: SDIO 24 MHz requested, 4-bit bus, PG0–5 20 mA. No regulator
voltage changes. This does not promise successful Wi-Fi initialization or speed.
The patch affects both main and R pinctrl; storage, Ethernet and USB must also
be tested. The existing reference kernel is retained as a serial boot-menu
fallback, with its own modules and DTB. Its Wi-Fi behavior remains unverified.

Important limitation: the reference binary's custom H728 DE35/HDMI driver source
is not reproduced here. Use wired SSH or UART; do not expect HDMI output from
the experimental kernel. Eight CPU nodes, OPPs, thermal driver, Ethernet and
USB2/USB3 drivers are retained, but new-source hardware behavior is unverified.

After a clean power-off, insert the test SD and collect:

```sh
uname -r
findmnt -no SOURCE,UUID /
cat /sys/kernel/debug/mmc1/ios
ip -br link
dmesg | grep -Ei 'aic|sunxi-mmc|sdio|data error|regulator|thermal'
```

Expected kernel: 7.2.0-h728-test1. Expected root: SD, not eMMC. Then test three
cold boots, Wi-Fi association and transfers, wired Ethernet, USB storage and
CPU/thermal status. Do not raise the SDIO clock until this baseline passes.
The build cannot test these remotely; successful offline verification is not
proof that the hardware works.
