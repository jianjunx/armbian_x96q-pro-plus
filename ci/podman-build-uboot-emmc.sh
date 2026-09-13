#!/usr/bin/env bash
# Launcher for ci/build-uboot-emmc-container.sh on Windows.
#
# Builds the eMMC U-Boot blob locally in Podman instead of waiting for GitHub
# Actions. The result lands in <repo>/out/u-boot-sunxi-with-spl-emmc.bin, ready
# to copy to the FAT partition of the SD card.
#
# Usage (Git Bash):  bash ci/podman-build-uboot-emmc.sh
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)

# podman.exe is not on PATH for every install; fall back to the default location.
if command -v podman.exe >/dev/null 2>&1; then
  podman=podman.exe
elif command -v podman >/dev/null 2>&1; then
  podman=podman
else
  podman="${LOCALAPPDATA:-$USERPROFILE/AppData/Local}/Programs/Podman/podman.exe"
  [[ -f $podman ]] || { echo "podman.exe not found; install Podman Desktop or add it to PATH." >&2; exit 1; }
fi

# The WSL machine must be running before any container command works.
if ! "$podman" machine list --format '{{.Name}} {{.Running}}' 2>/dev/null | grep -q '^[^ ]* true$'; then
  echo "Starting podman machine..."
  "$podman" machine start >/dev/null
fi

echo "Building eMMC U-Boot blob in a container (this takes several minutes)..."
# H728_UBOOT_DEBUG=1 builds a blob with verbose SPL logging, for diagnosis only.
"$podman" run --rm \
  -v "$repo:/work" \
  -e "H728_UBOOT_DEBUG=${H728_UBOOT_DEBUG:-0}" \
  -w /work \
  ubuntu:24.04 \
  bash -c "tr -d '\r' </work/ci/build-uboot-emmc-container.sh >/tmp/build.sh && bash /tmp/build.sh"
