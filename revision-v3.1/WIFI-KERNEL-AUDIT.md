# Reference kernel binary audit — 2026-09-13

Scope: read-only analysis of the retained reference Image. No patched Image,
on-device register writes, new kernel installation or hardware fix is claimed.

## Input and method

Image SHA-256:
`0bd464bb4b836187cfb680c64be360fd56cd2e3d78cd9c311a075c045739b806`.
Path: `armbian-build/cache/h728-audit/reference-7.2/boot/Image`.
Analysis tool: `marin-m/vmlinux-to-elf` 1.3.6, executed in an isolated uv tool
environment. Reconstructed ELF is a disposable analysis artifact, NOT bootable
delivery material. GNU AArch64 objdump/readelf used in h728-image-build.

Important extraction caveat: tool found kallsyms names but emitted symbol values
relative to a different origin (_text=0x020d0000), marking them UND. Do not use
those values as absolute runtime addresses. For inspection, mapped offsets as
symbol minus _text into the Image; corroborated function entry, descriptor
layout, and the regulator_get_voltage call target. Analysis ELF base was
0xffff800080000000. No addresses below authorize physical-memory access.

## Findings

- `sunxi_pinctrl_set_io_bias_cfg.isra.0`: symbol 0x0292c600, Image offset
  0x85c600. Function loads descriptor io_bias_cfg_variant at +36; switch has
  variants 1, 2, 3 only. SEL branch compares supply voltage against 1800000
  and uses `cset w4, le` (Image offset 0x85c770). No inverted variant exists.
- `a523_pinctrl_data`: symbol 0x03f02ef0, Image offset 0x1e32ef0. Descriptor
  variant at +36 is 2 (PIO_POW_MODE_SEL). This agrees with pre-fix upstream
  behavior, not the CTL_INV fix. The function's call at offset 0x85c630 lands
  at 0x9940c0, matching regulator_get_voltage minus _text.
- Upstream A523 withstand fix adds CTL_INV and inverts SEL encoding; current
  binary does not implement that logic. This is a concrete missing fix but
  NOT proof it causes the observed Wi-Fi CRC errors.
- Matched board DTB assigns PIO vcc-pg-supply to phandle 0x18, BLDO1 named
  vcc-pg-wifi-lvds, fixed 1800000 uV. MMC ios reports logical 3.3 V signalling
  without proving actual pad voltage. Do not change BLDO1 to 3.3 V.
- `sunxi_mmc_clk_set_rate`: symbol 0x02e5dde8, Image offset 0xd8dde8.
  New-timing branch bypasses old clk_set_phase tables. Calibration path writes
  0x80 to host offset 0x144 (software delay enable with zero taps), without a
  sample-window search in that path. This matches generic upstream's limited
  calibration implementation, not evidence of a board-calibrated delay.

## Hardware evidence and next gate

User's 40 MHz / 4-bit / 20 mA boot failed CMD53 RD DCE. Earlier 24 MHz / 4-bit
/ 40 mA failed WR DCE; 24 MHz / 4-bit / 20 mA passed finite cold-boot and
transfer tests. Do not infer a damaged data line or guarantee a throughput.

Before a targeted kernel replacement, confirm runtime BLDO1 voltage/consumers
from regulator_summary and reference Image hash on device. Full matching 7.2
source remains unavailable. Safest implementation is a source-built matched
Image/modules/DTB test set incorporating the scoped upstream fix, not hex edits
to this Image or a global voltage-comparison inversion affecting other SoCs.
The pinctrl change can affect Ethernet/SD/eMMC as well as Wi-Fi, so it requires
SD-only recovery-first validation of all those subsystems. Existing eMMC must
remain untouched. No release/default clock change is justified yet.

## Sources

- https://github.com/marin-m/vmlinux-to-elf
- https://github.com/warpme/minimyth2/blob/8d68d845fb304c9296b28ab26ba5faa4e7c72a11/script/kernel/linux-7.2/files/2706-pinctrl-sunxi-A523-fix-voltage-withstand-encoding.patch
- https://github.com/torvalds/linux/blob/master/drivers/mmc/host/sunxi-mmc.c
- Local corroborating patch: armbian-build/patch/kernel/archive/sunxi-7.1/patches.armbian/drv-pinctrl-sunxi-a523-fix-voltage-withstand-encoding.patch
