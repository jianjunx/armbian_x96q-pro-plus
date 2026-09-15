#!/bin/bash
# Run in h728-image-build; never applies DTS hunks with unverified supply wiring.
set -euo pipefail
input=/armbian/cache/h728-source-input
# Linux source contains case-distinct headers: do not extract onto macOS bind mounts.
work=/tmp/h728-source-test1
test ! -e "$work/linux-7.2" || { echo 'Source already exists; refusing overwrite'; exit 1; }
mkdir -p "$work"
printf '%s  %s\n' f9fef3d14c0df53819026f4be74459835c2a0b0dcbf5b5bbd9ea19f0829402b3 "$input/linux-7.2.tar.xz" | sha256sum -c -
printf '%s  %s\n' f22b0c740cee79ca6bdf0b2bc5b6edf6a188b83bbf2fd35444dcc0a43c85c299 "$input/recipe.tar.gz" \
    e8a5cbbd880387d510d33451e3f43f92705235049574042dfd04de933bed041a "$input/reference.config" | sha256sum -c -
mkdir "$work/recipe"
tar -xzf "$input/recipe.tar.gz" --strip-components=1 -C "$work/recipe"
tar -xJf "$input/linux-7.2.tar.xz" -C "$work"
cd "$work/linux-7.2"
for prefix in 1201 1204 1206 1207 1208 1210 1212 1217 1218; do
    patchfile=("$work/recipe/$prefix"*.patch)
    test "${#patchfile[@]}" -eq 1
    # Select driver and binding headers only. Board description is separately
    # reconstructed from the proven reference DTB, not this older recipe DTS.
    awk '/^diff --git / { keep=($3 ~ /^a\/drivers\// || $3 ~ /^a\/include\//) } keep' \
        "${patchfile[0]}" > "$work/$prefix-selected.patch"
    patch --dry-run --batch --fuzz=0 -p1 < "$work/$prefix-selected.patch"
    patch --batch --fuzz=0 -p1 < "$work/$prefix-selected.patch"
done
patch --batch --fuzz=0 -p1 < "$input/a523-pinctrl-withstand.patch"
patch --batch --fuzz=0 -p1 < "$input/aic-linux72-api.patch"
mkdir -p "$work/obj"
cp "$input/reference.config" "$work/obj/.config"
scripts/config --file "$work/obj/.config" --set-str LOCALVERSION '-h728-test1' --disable LOCALVERSION_AUTO --disable DEBUG_INFO --disable DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT --enable DEBUG_INFO_NONE --set-str SYSTEM_TRUSTED_KEYS '' --set-str SYSTEM_REVOCATION_KEYS ''
make ARCH=arm64 O="$work/obj" olddefconfig
echo 'Prepared clean source; build Image modules next.'
