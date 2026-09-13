#!/bin/bash
# Build the standalone eMMC bootloader (u-boot-sunxi-with-spl-emmc.bin) inside a
# container, using the exact same steps as .github/workflows/uboot-emmc.yml.
#
# It runs *inside* the container; /work is the repo root bind-mounted by the
# launcher (ci/podman-build-uboot-emmc.sh). This exists so a patch change can be
# validated locally in minutes instead of waiting for a CI run, and so the
# resulting blob lands directly in the repo tree ready to copy to the SD card.
#
# Keep this in sync with .github/workflows/uboot-emmc.yml and
# revision-v3/build-emmc-uboot.sh: same pinned commits, same patch, same config.
set -euo pipefail

UBOOT_COMMIT=b99f4a9e0778f4f402619d70976537d4833d7eab
ATF_COMMIT=b5de74a685fb73b784e45bbbd18dd9a0c528d8b2

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  bc bison flex build-essential crossbuild-essential-arm64 \
  ca-certificates curl device-tree-compiler git make patch perl \
  libssl-dev libgnutls28-dev uuid-dev \
  python3 python3-dev python3-setuptools python3-yaml \
  python3-jsonschema python3-pyelftools swig

build=$(mktemp -d /tmp/h728-emmc-uboot.XXXXXX)
mkdir -p /work/out
cd "$build"

curl -fsSL --retry 3 -o u-boot.tar.gz \
  "https://github.com/apritzel/u-boot/archive/${UBOOT_COMMIT}.tar.gz"
curl -fsSL --retry 3 -o atf.tar.gz \
  "https://github.com/jernejsk/arm-trusted-firmware/archive/${ATF_COMMIT}.tar.gz"
tar -xzf u-boot.tar.gz
tar -xzf atf.tar.gz
sha256sum u-boot.tar.gz atf.tar.gz | tee /work/out/source.sha256

if [[ -f /work/ci/uboot-emmc.sha256 ]]; then
  sha256sum -c /work/ci/uboot-emmc.sha256
else
  echo 'WARNING: ci/uboot-emmc.sha256 is absent; source archives are not hash-pinned.'
fi

atf="$PWD/arm-trusted-firmware-${ATF_COMMIT}"
uboot="$PWD/u-boot-${UBOOT_COMMIT}"
test -d "$atf"
test -d "$uboot"

make -C "$atf" -j"$(nproc)" CROSS_COMPILE=aarch64-linux-gnu- PLAT=sun55i_a523 bl31
test -f "$atf/build/sun55i_a523/release/bl31.bin"
cp "$atf/build/sun55i_a523/release/bl31.bin" "$uboot/bl31.bin"

make -C "$uboot" CROSS_COMPILE=aarch64-linux-gnu- x96q_pro_plus_defconfig
cd "$uboot"

# The repo may be checked out with CRLF on Windows; patch(1) rejects that.
tr -d '\r' </work/revision-v3/uboot-emmc.patch >"$build/uboot-emmc.patch"
patch -p1 <"$build/uboot-emmc.patch"

# Optional printf instrumentation of the sunxi MMC driver, for diagnosing an
# SPL read failure on real hardware. Never part of an installable build.
if [[ "${H728_UBOOT_DEBUG:-0}" == "1" ]]; then
  tr -d '\r' </work/revision-v3/uboot-emmc-spl-debug.patch >"$build/spl-debug.patch"
  patch -p1 <"$build/spl-debug.patch"
fi

scripts/config --set-val MMC_SUNXI_SLOT_EXTRA 2
scripts/config --set-str IDENT_STRING ' H728 eMMC v3'
scripts/config --enable OF_LIBFDT_OVERLAY
# H728 / A523: cap CONFIG_SYS_MMC_MAX_BLK_COUNT at 1 for this blob.
#
# Instrumented hardware runs (2026-09-13) showed multi-block reads to the
# eMMC failing intermittently, not deterministically: `mmc read` of up to
# 1490 blocks succeeds from the U-Boot CLI, yet consecutive FAT cluster
# reads of 8 blocks fail on one cluster and succeed on the next. The failure
# is inside CMD18 (mmc_send_cmd), before the CMD12 stop. Single-block reads
# never failed once, in the SPL or in U-Boot proper.
#
# So every read this blob issues is one block per request. A failed multi-block
# transfer also costs a timeout before mmc_bread()'s block-by-block retry
# recovers it, which is what made loading the 32 MB kernel unbearably slow.
#
# This only affects the eMMC blob: the SD card keeps its own bootloader, which
# still reads in large transfers.
scripts/config --set-val CONFIG_SYS_MMC_MAX_BLK_COUNT 1

# H728_UBOOT_DEBUG=1 turns on verbose SPL logging. Use it when SPL behaviour on
# hardware has to be observed (bus width, clock, raw read errors); it is never
# enabled for a blob that is meant to be installed.
if [[ "${H728_UBOOT_DEBUG:-0}" == "1" ]]; then
  # CONFIG_LOG alone is not enough: SPL has its own SPL_LOG gate, and without
  # it every debug()/log_debug() in the SPL build stays silent.
  scripts/config --enable CONFIG_LOG \
    --enable CONFIG_SPL_LOG \
    --enable CONFIG_SPL_LOG_CONSOLE \
    --set-val CONFIG_LOGLEVEL 7 \
    --set-val CONFIG_SPL_LOGLEVEL 7 \
    --set-val CONFIG_LOG_MAX_LEVEL 7 \
    --set-val CONFIG_SPL_LOG_MAX_LEVEL 7
fi

make CROSS_COMPILE=aarch64-linux-gnu- olddefconfig
make -j"$(nproc)" CROSS_COMPILE=aarch64-linux-gnu- EXTRAVERSION=-h728-emmc-v3
test "$(grep '^CONFIG_MMC_SUNXI_SLOT_EXTRA=' .config)" = CONFIG_MMC_SUNXI_SLOT_EXTRA=2

# ---- assertions, identical in spirit to the CI job ------------------------
dtb="$uboot/arch/arm/dts/sun55i-h728-x96qpro+.dtb"
blob=/work/out/u-boot-sunxi-with-spl-emmc.bin
cp "$uboot/u-boot-sunxi-with-spl.bin" "$blob"
cp "$uboot/.config" /work/out/emmc-uboot.config

fail=0
check() { # name actual expected
  if [[ "$2" = "$3" ]]; then
    echo "OK   $1 = $2"
  else
    echo "FAIL $1 = '$2' (expected '$3')"
    fail=1
  fi
}
check "board dtb present" "$(test -f "$dtb" && echo yes || echo no)" yes
# The sunxi U-Boot driver lacks A523 timing calibration on this board.
# 1-bit/26 MHz is the only mode proven to work in BROM and U-Boot proper.
check "mmc2 status" "$(fdtget "$dtb" /soc/mmc@4022000 status 2>&1)" okay
check "mmc2 bus-width" "$(fdtget "$dtb" /soc/mmc@4022000 bus-width 2>&1)" 1
check "mmc2 max-frequency" "$(fdtget "$dtb" /soc/mmc@4022000 max-frequency 2>&1)" 26000000
# eGON.BT0 sits at byte 4 of the blob (byte 0 is the jump instruction).
# 8 KiB is where it lands on the *device*, because it is written with dd seek=8.
check "SPL magic at file offset 4" \
  "$(dd if="$blob" bs=1 skip=4 count=8 status=none)" "eGON.BT0"

size=$(stat -c%s "$blob")
if [[ $size -gt 262144 && $size -lt 2097152 ]]; then
  echo "OK   blob size = $size bytes"
else
  echo "FAIL blob size = $size bytes (expected 256 KiB..2 MiB)"
  fail=1
fi

(cd /work/out && sha256sum u-boot-sunxi-with-spl-emmc.bin >emmc-uboot.sha256)
cat /work/out/emmc-uboot.sha256

if [[ $fail -ne 0 ]]; then
  echo "ERROR: eMMC bootloader assertions failed; refusing to publish the blob."
  rm -f "$blob"
  exit 1
fi

echo "Blob written to /work/out/u-boot-sunxi-with-spl-emmc.bin"
