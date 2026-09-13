#!/bin/bash
set -euo pipefail
test "$(uname -m)" = aarch64
test "$(id -u)" -eq 0
cd /armbian
sha256sum -c /src/ci/inputs.sha256
src=/armbian/cache/h728-v3.1-input
test ! -e "$src"
mkdir -p "$src" /armbian/delivery
cp /src/revision-v3.1/* "$src/"
cp /src/revision-v3/common.sh "$src/common.sh"
cp /src/revision-v3/common.sh "$src/base-common.sh"
cp /src/revision-v3/verify.sh "$src/base-verify.sh"
cp /src/revision-v3/patch-emmc-dtb.sh "$src/"
cp /src/ci/uboot-emmc.sha256 "$src/emmc-source.expected"
sha256sum /src/revision-v3/uboot-emmc.patch /src/revision-v3/configure-emmc-uboot.sh | sed 's@/src/@/work/@' > "$src/emmc-recipe.expected"
shellcheck -x -P "$src" "$src/"*.sh "$src/h728-diagnostics" "$src/h728-install-emmc"
bash "$src/build.sh" 2>&1 | tee /armbian/delivery/build.txt
bash "$src/verify.sh" 2>&1 | tee /armbian/delivery/verification.txt
# Move the verified image, avoiding a third 4 GiB copy on the hosted runner.
image=Armbian_X96Q-Pro-Plus_H728_Trixie_7.2.0-7_v3.1.2_SD.img
test ! -e "/armbian/delivery/$image"
mv /armbian/cache/h728-v3.1.2/v3.1.2-working.img "/armbian/delivery/$image"
cp /armbian/cache/h728-v3.1.2/installed-packages.txt /armbian/delivery/packages.txt
cp /armbian/cache/h728-emmc-build/bundle.sha256 /armbian/delivery/emmc-payload-hashes.txt
cp /armbian/cache/h728-emmc-build/source.sha256 /armbian/delivery/emmc-source-hashes.txt
cp /armbian/cache/h728-emmc-build/recipe.sha256 /armbian/delivery/emmc-recipe-hashes.txt
cp /src/ci/inputs.sha256 /armbian/delivery/build-inputs.sha256
cp /src/revision-v3.1/H728-README.txt /armbian/delivery/H728-README.txt
cd /armbian/delivery
sha256sum "$image" >SHA256SUMS
xz -T2 -3 -k "$image"
xz -t "$image.xz"
# Check the compressed stream really reconstructs the verified raw image.
xz -dc "$image.xz" | sha256sum | awk '{print $1}' >compressed-raw.sha256
test "$(cat compressed-raw.sha256)" = "$(awk '{print $1}' SHA256SUMS)"
sha256sum "$image.xz" >>SHA256SUMS
test "$(stat -c%s "$image.xz")" -lt 2147483648
sha256sum -c SHA256SUMS
# Files were created by the privileged root container, while the following
# GitHub Actions release step runs as the host runner user.
chown -R "$(stat -c %u /src):$(stat -c %g /src)" /armbian/delivery
