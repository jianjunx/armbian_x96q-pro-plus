# X96Q Pro+ / Allwinner H728 Armbian materials

Downloaded on 2026-08-28 for building an experimental Armbian image for the
X96Q Pro+ (Allwinner H728).

## Current delivery: v3 Trixie / Linux 7.2 image (2026-09-09)

Image: `armbian-build/output/images/Armbian_X96Q-Pro-Plus_H728_Trixie_7.2.0-7_v3.img`
(4 GiB; use an SD card of at least 8 GB).
SHA-256: `46b5720330065a731169f60bab260b0b46a23f8b1ec37e4497e690078ddebfec`.

See `revision-v3/README.md` for SD boot, Wi-Fi, diagnostics and the eMMC
migration tool. The user requested Trixie, the new reference kernel and eMMC
installation support. The new image upgrades a pristine v2 release copy
offline; it does not contain data from the user's running box. Kernel version
is `7.2.0-7-MANJARO-ARM`, paired with its modules and board DTB, plus an explicit
eMMC-only DTB change (8-bit, matched regulators, 52 MHz SDR). AIC8800D80 firmware
and schedutil configuration are included. The SD bootloader is unchanged;
the separately built eMMC bootloader enables MMC slot 2 and conservative timing.

Offline verification passed. Filesystem checks, package inventory and SHA-256
are next to the image. New-kernel SD boot, Wi-Fi association, USB transfers,
DVFS, eMMC writes and standalone eMMC boot still require physical testing.
The eMMC installer defaults to read-only checks and requires an exact typed
device/CID confirmation before overwriting the eMMC user area and Android.

## Previous delivery: v2 compatibility image (2026-09-08)

2026-09-09 update: the user confirmed v2 boots. Their diagnostic report
confirms eight CPUs online and Ethernet at 1000 Mbps/full duplex with DHCP.
USB host controllers enumerate, but that report contains no external USB
peripheral transfer test. Wi-Fi probes successfully but fails while loading
missing AIC8800D80 firmware. See `revision-v2.1/README.md` for the prepared
firmware + schedutil repair bundle and `revision-v2.1/ASSESSMENT.md` for the
kernel/Trixie assessment. This repair has passed offline installation checks;
post-repair Wi-Fi operation and DVFS stability await the user's test.

Use `armbian-build/output/images/Armbian_X96Q-Pro-Plus_H728_Bookworm_6.17-2_v2.img`.
SHA-256: `f3718e92a5ee1bfbc2f227bd3144f2c6f0234e6a761b5facd7ddd8b63c91ec29`.
See `revision-v2/使用说明.md` for flashing, limitations and diagnostics.
The original 6.18.48 image is preserved, but is not the recommended test image.

The original image's board DTB disabled GMAC1 and lacked the reference
USB3 enablement and CPU OPP/topology configuration. These are confirmed
offline defects; without UART output they do not prove where the reported
black-screen boot stopped. V2 replaces the kernel, modules and DTB together
with the retained forum reference package. Its actual kernel release is
`6.17.0-rc1-2-MANJARO-ARM+`, not stable Linux 6.17. This is an experimental
compatibility image, not a security-maintained production release.

`revision-v2/rebuild.sh` records the image/package modifications;
`revision-v2/verify.sh` checks the image read-only. The adjacent
`*.verification.txt` records successful offline verification, not physical
board testing. Normal `compile.sh` still targets the original mainline-based
configuration and does NOT reproduce the v2 kernel replacement.

## Directories

- `armbian-build/`: official Armbian build framework, shallow clone updated to
  commit `474593ad4140d8457ed0e43e3807f87fb90074e2`. This revision contains the
  `sun55iw3` family plus Linux 6.18 and 7.1 A523/H728 patch sets.
  - `config/boards/x96q-pro-plus.csc` is the local experimental board target.
    It selects mainline `x96q_pro_plus_defconfig`, the
    `sun55i-h728-x96qpro+.dtb`, UART0 at 115200 baud, and an 8 KiB sunxi
    U-Boot offset with a separate FAT boot partition.
  - `Dockerfile.h728-bootstrap` provides the Ubuntu 24.04 ARM64 build
    toolchain. It uses the USTC Ubuntu Ports mirror and includes the
    AArch64 cross compiler, DTC, binman dependencies, and TF-A/U-Boot build
    dependencies.
- `manjaro-linux-a523/`: extracted Manjaro recipe from the `a523` branch. Its
  PKGBUILD selects Linux commit `5a8a8dbd857f8c670c15ea482095becfaf622458`
  and contains the matching kernel configuration and packaging hooks.
- `uboot-x96qproplus/`: the three files published in the forum author's Google
  Drive U-Boot folder. `0001.patch` is an empty placeholder at the source.
- `source-archives/`: source archives pinned by the Manjaro recipes:
  - Linux: `apritzel/linux@5a8a8dbd857f8c670c15ea482095becfaf622458`
  - U-Boot: `apritzel/u-boot@b99f4a9e0778f4f402619d70976537d4833d7eab`
  - TF-A: `jernejsk/arm-trusted-firmware@b5de74a685fb73b784e45bbbd18dd9a0c528d8b2`
- `source-metadata/`: downloaded public folder index and GitLab branch metadata
  used to resolve the source files.
- `reference-packages/`: the forum author's later `linux-sunxi-6.17-2`
  binary package. It contains `boot/Image`, modules and
  `boot/dtbs/allwinner/sun55i-h728-x96qpro+.dtb`. This is retained as a
  behavioral/DTB reference originally; v2 now repackages its matching kernel,
  DTB and modules into `linux-image-h728-manjaro_6.17.0~rc1-2+h728.2_arm64.deb`.
  Gzip-compressed modules are decompressed without changing their ELF content
  because the Debian kmod build does not support loading `.ko.gz`.

## Source URLs

- Armbian build: <https://github.com/armbian/build>
- Manjaro Linux recipes: <https://gitlab.manjaro.org/iuncuim/linux/-/tree/a523>
- Forum U-Boot folder: <https://drive.google.com/drive/folders/1PVYzsNJZ0nwhF_LSPSIL8wZgevlXjo5M>
- Forum thread: <https://forum.manjaro.org/t/allwinner-h728-a523-a527-t527-initial-support-thread/173654>

## Important limitation

The downloaded `a523` source recipe is the reproducible early Linux 6.13
recipe. The forum author's later source fixes were moved to the GitLab
`master` branch, but repeated Git clone, archive API, repository-tree API and
raw-file requests failed or stalled on 2026-08-28. The corresponding 6.17-2
binary package was successfully downloaded from Google Drive, but it does not
replace the missing source recipe. The current Armbian tree carries newer
mainline-based A523/H728 support, but its first generated board DTB was
incomplete for this box. V2 therefore uses the retained binary reference for
hardware compatibility testing; a fully source-rebuilt maintained kernel
remains future work.

The Armbian configuration resolver successfully selected `sun55iw3`, U-Boot
`v2026.07`, `x96q_pro_plus_defconfig`, TF-A branch `a523-v4`, and Linux 6.18.
The first U-Boot build attempt downloaded and cached TF-A successfully but a
full U-Boot Git clone ended with a GitHub TLS `early EOF`. A later codeload
attempt is retained only as `source-archives/u-boot-v2026.07.tar.gz.partial`
and is intentionally not listed in `SHA256SUMS`.

## Built bootloader

`build-artifacts/u-boot-sunxi-with-spl-x96qproplus-b99f4a9.bin` was built
successfully on 2026-08-31 from the downloaded Manjaro U-Boot and TF-A source
archives. It is a 755 KiB Allwinner eGON/SPL image, embeds the
`sun55i-h728-x96qpro+` device tree, and identifies itself as U-Boot SPL
2025.01-1. Its SHA-256 is recorded in `SHA256SUMS`.

This proves the known X96Q Pro+ bootloader recipe builds reproducibly. It is
included unchanged at offset 8192 bytes in both SD images. The user tested
the original SD image and reported a black screen and no DHCP lease. V2 has
passed offline checks and the user's physical SD-card boot test. We have not
written any physical SD card or box eMMC. Do not install to eMMC until an
SD-card boot has been validated, preferably over the 3.3 V UART console.
