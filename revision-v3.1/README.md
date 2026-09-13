# v3.1 full SD image

RELEASE BRANCH: v3.1.2, +h728.6, refusal-only eMMC installer. The v3.1.3
candidate notes below refer to parallel development, not this release.

## Current candidate: v3.1.3

User explicitly requested complete eMMC replacement and selected no backup.
The new installer supports `--check` (default), `--install --no-backup` with
typed target/CID consent, or `--install --backup-dir /mnt/usb`. It only runs
from independent SD root/boot and preserves boot0/1 and EXT_CSD. See
[EMMC-INSTALL.md](EMMC-INSTALL.md) before use. New cache/output and +h728.7
preserve earlier deliverables. Installer execution is NOT tested offline.
Earlier v3.1.2/refusal-only descriptions below are historical.

## Current build target: v3.1.2

v3.1.2 stores a freshly source-built eMMC U-Boot under `/usr/lib/h728/uboot`,
including its config, board DTB, archive/recipe hashes and bundle manifest.
The proven SD bootloader remains byte-identical; no eMMC writes or installer
enablement are added. Kernel package revision is +h728.6 (same Image/modules
and Wi-Fi DTB as +h728.5). Use a new h728-v3.1.2 cache and output filename.
CI builds the payload from the same checkout before image assembly, verifies
the pinned archives and recipe, and compares the installed payload byte-for-byte.
Local builds must stage the payload in `/armbian/cache/h728-emmc-build` and
the expected source/recipe hashes alongside the scripts as shown in ci/build.sh.
This new image is not yet hardware-tested. The following v3.1.1 results are
historical, not a v3.1.2 delivery claim.

Local v3.1.2 image assembly and full read-only verification passed on 2026-09-13.
The independent `.img`, hash and verification report are under
`armbian-build/output/images/`; SHA-256 is recorded in MATERIALS.md.
The new workflow has not yet been run on GitHub; no new Release is claimed.

The scripts in this directory now produce
`Armbian_X96Q-Pro-Plus_H728_Trixie_7.2.0-7_v3.1.1_SD.img`, in a separate
`/armbian/cache/h728-v3.1.1` workspace. Kernel package +h728.5 carries the
Wi-Fi 24 MHz ceiling in its postinst DTB payload; Image/modules are unchanged.
The actual observed clock is 22.22 MHz. The user confirmed three cold boots,
5 GHz association, DHCP and 300-second transfers in both directions:
64.3 Mbit/s download, 66.0 Mbit/s upload with zero upload TCP retransmissions.
These tests were on the patched existing system, not the new CI image.
20 MHz fallback DTB is included alongside the untouched stock DTB. See
H728-README.txt for selecting it. No private Wi-Fi credentials or device MAC
are embedded. Detailed experiment history: [WIFI-TEST.md](WIFI-TEST.md).
The delivery filenames and hashes below refer to the preserved v3.1 release.

2026-09-10 hardware update: the user booted the CI SD image and accessed wired
SSH. Wi-Fi enumerates on SDIO but fails during firmware transfer with -110;
it is not working. See [Wi-Fi investigation and reversible test](WIFI-TEST.md).
The 12 MHz experiment is not included in the default image and is not yet
hardware-validated. Earlier "not hardware-tested" statements below describe
the state at image delivery, not the latest feedback.

Scope agreed 2026-09-10: a fresh standalone SD system; preserve the box eMMC.
This is NOT a copy of the user's running eMMC, nor an eMMC bootloader fix.
The version remains Debian 13 Trixie / reference Linux 7.2.0-7-MANJARO-ARM.
Matching complete kernel source history is still unavailable in this project.

Delivered artifact (4 GiB; use >=8 GB SD):
`armbian-build/output/images/Armbian_X96Q-Pro-Plus_H728_Trixie_7.2.0-7_v3.1_SD.img`

SHA-256: `d9357a2223d29fdfa8373c9a37b35b3384e53edb14013b4b2ae9f086f776f408`.
Read-only verification passed, with adjacent `.sha256`, `.verification.txt`
and `.packages.txt` files. This new image has not yet been hardware-tested.
Back up the current working SD before flashing: it is the user's sole proven
boot path. Existing eMMC data remains in place, but its users/passwords are
not imported. Login to the fresh SD as root/1234 and complete first-login setup.

Changes from the original v3 delivery:

- Correct eMMC DTB main supply to /vcc3v3 (the byte-verified board fix).
- Keep the proven SD U-Boot unchanged, use loglevel 7 in BOTH boot paths.
  Logging level is a diagnostic choice, not a demonstrated PHY timing fix.
- Retain the matched Wi-Fi firmware and schedutil/408 MHz minimum frequency.
- Store boot-ID-tagged diagnostics and running DT, with bounded retention.
- Disable the unused Exim mail service; do not claim its actual failure cause.
- Replace eMMC installation entry with a read-only check; refuse --install.
- Generate fresh SD filesystem UUIDs and first-boot identities.
- Repackage the corrected DTB into kernel package revision +h728.4 so a kernel
  postinst cannot silently reinstall the original defective DTB.

The original v2/v3 artifacts remain untouched. This image defaults to SD root,
not the old SD UUID and not the existing eMMC UUID. Initial SSH root/1234 and
Armbian first-login setup apply to THIS new SD system only.

Build in the existing privileged h728-image-build container. Stage this directory
plus v3 common.sh as both base-common.sh and common.sh (ShellCheck lookup), verify.sh as base-verify.sh and
patch-emmc-dtb.sh into /armbian/cache/h728-v3.1-input. Then run build.sh and
verify.sh. Use publish.sh to repeat verification and publish a separate image,
checksum, package inventory and verification log. Existing v3.1 working/output
images are never overwritten.
The original v3 image is SHA-256 pinned as the offline base; this build does not
fetch package updates or swap to an untested new kernel. All reused source
packages and boot blobs remain pinned by top-level SHA256SUMS.

Before delivery run read-only verification and retain its log next to the image.
Hardware boot/network/USB/Wi-Fi/temperature must be retested after flashing.
Independent eMMC boot remains unresolved; do not run an older installer.
HDMI output and deep CPU idle are NOT fixed by this release. Test idle temperature
after >=10 minutes at a recorded room temperature. Failed boot: use FAT
h728-diagnostics.txt and h728-logs; stock-dtb is a SD-only fallback.
