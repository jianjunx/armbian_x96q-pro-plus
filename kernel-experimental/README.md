# Source-built kernel SD test image

## Current delivery recipe

The new clean build is `v3.2.0-test1`, kernel `7.2.0-h728-test1`.
Read [TEST-IMAGE.md](TEST-IMAGE.md) for limitations and hardware acceptance.
The historical audit below is not used as the build source.
The complete kernel/modules build and SD image offline verification passed on
2026-09-13. The raw 4 GiB image and ~1007 MiB xz are in `armbian-build/output/images/`;
patched source, configuration and reconstruction recipe are in
`armbian-build/output/h728-source-test1/`. Hashes are in top-level SHA256SUMS.
No physical-device validation, Git push or Release publication was performed.

Build on the Linux filesystem inside `h728-image-build`; a default macOS bind
mount cannot faithfully extract Linux's case-distinct `ipt_ECN.h`/`ipt_ecn.h`.
Never reuse the earlier partially patched shared-directory source tree.

Stage this directory and `revision-v3/common.sh` in
`/armbian/cache/h728-source-input/`. Required inputs there:

- `linux-7.2.tar.xz`: top-level SHA256SUMS-pinned upstream archive.
- `recipe.tar.gz`: pinned iuncuim source recipe archive, unchanged.
- `reference.config`: config extracted from the reference kernel package,
  SHA-256 `e8a5cbbd880387d510d33451e3f43f92705235049574042dfd04de933bed041a`.

Container sequence (no physical disks are targeted):

```sh
bash /armbian/cache/h728-source-input/prepare-source.sh
make -C /tmp/h728-source-test1/linux-7.2 ARCH=arm64 \
  O=/tmp/h728-source-test1/obj -j8 Image modules
bash /armbian/cache/h728-source-input/package.sh
bash /armbian/cache/h728-source-input/assemble.sh
bash /armbian/cache/h728-source-input/verify.sh
```

Preparation selects only driver/header hunks from patches 1201, 1204, 1206,
1207, 1208, 1210, 1212, 1217 and 1218, in that order, with zero fuzz. This
retains dual-PMIC handling, AIC, thermal, Ethernet PHY clock, CPU clocks,
USB3 combo PHY and MMC clock changes. Then applies the pinctrl fix and the
reviewable Linux 7.2 AIC compatibility patch. It does not import the older
recipe's unsafe board DTS/eMMC supply changes or unrelated H616 patches.

`sun55i-h728-test1.dts` is a decompilation of the controlled 24 MHz/4-bit/20 mA
DTB (input hash `4898a7abe86e08c533ace788604a90ce58401dd2fc63ae42a31a5e8249c7e357`).
It contains no device-specific network identity. DTS recompilation can change
binary layout, so verification compares the compiled payload, not the old hash.
Board wiring and regulator voltages are preserved. Reference custom DE35/HDMI
driver support is **not** reproduced; this is a headless/UART test, not a
feature-equivalent production replacement.

Assembly clones the pristine locally assembled v3.1.3 image after exact hash
verification, not a device backup. It retains the old kernel/modules/DTB as a
menu fallback, generates new filesystem IDs, clears first-boot identities,
and disables eMMC installation. Build scripts refuse existing outputs.

## Historical investigation checkpoint

### Subsequent hardware feedback (recorded 2026-09-15)

The user booted `7.2.0-h728-test1` with root on SD. Ethernet was up and
Wi-Fi scanned both 2.4 and 5 GHz, then associated on 5240 MHz. The SSH
connection reset immediately after the association status was printed;
address acquisition, transfer stability and whether the box rebooted remain
unconfirmed. Do not treat this as a successful throughput/stability test.

The same boot reported eMMC controller `4022000` data/stop-command errors
and both thermal sensor probes failed with -2. The ported thermal driver
requires a `gpadc` clock absent from the retained DTS clock names: an identified
driver/DT integration defect missed by the initial offline checks. CPU4's
1992 MHz OPP was rejected by regulator limits. AIC also rejected several
`lvl_adj_5g_chan_*` configuration keys. These remain unresolved; preserve the
eMMC installation block and do not run prolonged stress tests or raise SDIO
frequency until the thermal and storage regressions are addressed.

This feedback supersedes earlier statements that no hardware feedback exists.
No raw logs, device addresses, filesystem IDs or credentials are recorded here.

Objective: validate the A523 pinctrl withstand fix without replacing the known
SD recovery or writing eMMC. No shipping build workflow is changed here.

## Pinned inputs

See top-level SHA256SUMS and MATERIALS.md. Linux 7.2 archive is verified against
kernel.org HTTPS SHA-256; the PGP signature itself has not been verified.
Author recipe: iuncuim/linux-sunxi commit
014fe35ca1ecb5b2f4bd42629cb35ab407ee8bb5, which targets **6.19-rc1**.
It is not the full matching source recipe for the installed 7.2-7 kernel.
Do not source/execute PKGBUILD; read its ordered patch list as build metadata.

The copied `a523-pinctrl-withstand.patch` retains upstream authorship and the
Armbian wrapper. It passed `patch --dry-run --batch --fuzz=0 -p1` on pristine
7.2 pinctrl files and applied to the experimental tree. This modifies both
main and R pinctrl, not just Wi-Fi; test storage/Ethernet/regulator consumers.

## Local checkpoint

Container: h728-image-build.
- Recipe: /armbian/cache/h728-source-kernel-audit/recipe
- Source: /armbian/cache/h728-source-kernel-audit/linux-7.2
- Object output: /tmp/h728-linux72-compile-audit
- Compiler diagnostics: /armbian/cache/h728-source-kernel-audit/compile-errors.log

The source directory is a **partial patch-application audit**, NOT a coherent
release tree. Each author 1*.patch was dry-run with zero fuzz in name order;
only passing patches were applied. Rejected patches were not partially applied.
Pristine archive remains available for a clean, reviewed rebuild.

Passing relevant patches: 1201 PMIC, 1204 regulator, 1205 Wi-Fi DT, 1206 AIC
source, 1207 AIC fixes, 1213 WalnutPi, 1218 clock. Rejected relevant patches:
1208 thermal, 1210 Ethernet, 1212 CPU OPP, 1216 GPU, 1217 USB3, 1219 MCU.
Some 100x H616/unrelated patches also rejected; do not blindly port unrelated
board changes. Resolve each relevant reject against 7.2 upstream and reference
DTB; a reject may mean already upstream, not simply missing support.

Old recipe 1205 uses the unsafe eMMC reg_cldo3 supply. A delivery must instead
preserve the verified vcc3v3 wiring, and retain the 24 MHz/4-bit/20 mA Wi-Fi
control while isolating the pinctrl fix. Never boot this audit tree as-is.

Reference config was copied from the retained +h728.7 package, then processed
with olddefconfig. Focused pinctrl directory build succeeded, including main
A523 and common pinctrl objects. This is compilation only, not hardware proof.
Combined AIC build failed on API changes:
- legacy linux/of_gpio.h removed (Bluetooth low-power rfkill component);
- TDLS management-frame structure no longer has the expected nested `u`;
- strncpy unavailable in rwnx_msg_tx.c and rwnx_platform.c.
Do not suppress errors or disable needed features merely to obtain a green build.
No modules_install, initramfs, image replacement or device access performed.

## Next work

1. Port/review the AIC API deltas preserving copy/length semantics and decide
   whether Bluetooth low-power support can be retained with descriptor GPIOs.
2. Resolve Ethernet/OPP/thermal/USB3 deltas and produce a clean ordered patch
   series with hashes. Export every patch, not just an ignored working tree.
3. Build a separately versioned Image/modules/DTB set and validate every
   previously supported subsystem offline before an SD-only test image.
4. Pin test conditions at 24 MHz/4-bit/20 mA, confirm boot and CRC behavior,
   then test 40 MHz. Do not promise a particular speed or a Wi-Fi root cause.

No code commit, push, Actions build, Release or installable kernel delivered.
