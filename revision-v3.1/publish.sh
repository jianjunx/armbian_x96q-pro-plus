#!/bin/bash
set -euo pipefail
src=/armbian/cache/h728-v3.1-input
# shellcheck source=settings.sh
source "$src/settings.sh"
out=/armbian/output/images/Armbian_X96Q-Pro-Plus_H728_Trixie_7.2.0-7_v3.1.2_SD.img
for path in "$out" "$out.sha256" "$out.verification.txt" "$out.packages.txt"; do
    test ! -e "$path" || { echo "Refusing overwrite: $path"; exit 1; }
done
bash "$src/verify.sh" 2>&1 | tee "$H728_CACHE_DIR/verification.txt"
cp --sparse=never "$H728_IMAGE" "$out"
cmp "$H728_IMAGE" "$out"
cp "$H728_CACHE_DIR/verification.txt" "$out.verification.txt"
cp "$H728_CACHE_DIR/installed-packages.txt" "$out.packages.txt"
cd /armbian/output/images
sha256sum "${out##*/}" >"$out.sha256"
sha256sum -c "$out.sha256"
echo "Published: $out"
