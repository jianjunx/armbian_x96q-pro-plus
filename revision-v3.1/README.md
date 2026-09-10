# v3.1 full SD image

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
